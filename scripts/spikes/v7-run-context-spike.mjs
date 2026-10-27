// #240 spike probe - parent/child graph sharing of RunContext, deadline and cancellation.
//
// Run: node scripts/spikes/v7-run-context-spike.mjs
// Exit code is 0 for every spike verdict (PASS / FAIL / NEEDS-CHANGE); only a broken
// harness exits non-zero.
//
// The probe loads the real StateGraph.ets / CaptureGraph.ets through the existing
// arkts-lint loader. It does not modify any production .ets file and does not add
// runtime dependencies.
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';
import { loadNoteReviewEtsModule } from '../arkts-lint/tests/note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../..');

// The loader evaluates .ets in a separate vm context. Passing the host Error keeps the
// harness realistic for `e instanceof Error` checks; domain checks below deliberately use
// name / own fields instead of `instanceof` (cross-realm identity is not a product fact).
const vmGlobals = { Error };

function loadEts(relativePath, options = {}) {
  return loadNoteReviewEtsModule(relativePath, { cache: new Map(), globals: vmGlobals, ...options });
}

const { StateGraph, StateGraphError } = loadEts('common/src/main/ets/workflow/StateGraph.ets');
const { CancellationToken } = loadEts('common/src/main/ets/llm/CancellationToken.ets');

const commonMock = {
  StateGraph,
  StateGraphError,
  StateGraphNode: undefined,
};
const { CaptureGraph } = loadEts('agents/src/main/ets/graph/CaptureGraph.ets', {
  mocks: {
    common: commonMock,
    'common/src/main/ets/Index': commonMock,
  },
});

// The real CaptureGraphError is an interface (AgentState.ets:26-32), so it has no runtime
// constructor. This class is only a stand-in with the same own fields, used to observe
// what crosses the subgraph boundary.
class ProbeDomainError extends Error {
  constructor(kind, step, retriable, message) {
    super(message);
    this.name = 'CaptureGraphError';
    this.kind = kind;
    this.step = step;
    this.retriable = retriable;
  }
}

function linearGraph(steps, onNode) {
  const graph = new StateGraph('START', 'END');
  for (const step of steps) {
    graph.addNode(step, async (state) => {
      onNode(step);
      return state;
    });
  }
  graph.addEdge('START', steps[0]);
  for (let i = 0; i < steps.length - 1; i++) {
    graph.addEdge(steps[i], steps[i + 1]);
  }
  graph.addEdge(steps[steps.length - 1], 'END');
  return graph;
}

function captureState(token) {
  return {
    captureText: 'probe',
    source: 'app',
    currentStep: 'START',
    persist: false,
    analysisOnly: false,
    cancellationToken: token,
  };
}

const verdicts = [];

function report(question, verdict, evidence) {
  const line = `Q${question} ${verdict} ${evidence}`;
  console.log(line);
  verdicts.push({ question, verdict, evidence });
}

// ---------------------------------------------------------------------------
// Q1: can a child graph receive the parent runId / deadline / CancellationToken,
// and does cancellation bubble out of the child?
// ---------------------------------------------------------------------------
async function q1() {
  // (a) StateGraph kernel: the graph object itself holds no run context. The token only
  // travels because it is placed in the generic State by hand.
  const contextFields = ['runId', 'deadline', 'token'].filter((field) => field in new StateGraph('START', 'END'));

  const kernelToken = new CancellationToken();
  const kernelTrace = { parent: [], child: [] };
  // child2 cancels and rethrows, i.e. a cooperative node.
  const kernelChild2 = new StateGraph('START', 'END');
  kernelChild2.addNode('child1', async (state) => {
    kernelTrace.child.push('child1');
    return state;
  });
  kernelChild2.addNode('child2', async (state) => {
    kernelTrace.child.push('child2');
    state.token.cancel();
    state.token.throwIfCancelled();
    return state;
  });
  kernelChild2.addNode('child3', async (state) => {
    kernelTrace.child.push('child3');
    return state;
  });
  kernelChild2.addEdge('START', 'child1');
  kernelChild2.addEdge('child1', 'child2');
  kernelChild2.addEdge('child2', 'child3');
  kernelChild2.addEdge('child3', 'END');

  const kernelParent = new StateGraph('START', 'END');
  kernelParent.addNode('p1', async (state) => {
    kernelTrace.parent.push('p1');
    return state;
  });
  kernelParent.addNode('p2', async (state) => {
    kernelTrace.parent.push('p2');
    return await kernelChild2.run(state, 8);
  });
  kernelParent.addNode('p3', async (state) => {
    kernelTrace.parent.push('p3');
    return state;
  });
  kernelParent.addEdge('START', 'p1');
  kernelParent.addEdge('p1', 'p2');
  kernelParent.addEdge('p2', 'p3');
  kernelParent.addEdge('p3', 'END');

  let kernelCaught;
  try {
    await kernelParent.run({ step: 'START', token: kernelToken }, 8);
  } catch (error) {
    kernelCaught = error;
  }
  const kernelBubbled = kernelCaught !== undefined
    && kernelCaught.message === 'CONVERSATION_CANCELLED'
    && !kernelTrace.child.includes('child3')
    && !kernelTrace.parent.includes('p3');

  // (b) Production shape: the child is a CaptureGraph. Its node wrapper checks the token
  // before/after each node (CaptureGraph.ets:37,39) and its catch rewrites any throw to
  // NODE_ERROR (CaptureGraph.ets:41-43). A cancellation in the child is therefore a value,
  // not an exception, and the parent keeps running.
  const productionToken = new CancellationToken();
  const productionTrace = { parent: [], child: [] };
  const productionChild = new CaptureGraph();
  productionChild.addNode('capture', async (state) => {
    productionTrace.child.push('capture');
    state.cancellationToken.cancel();
    return { state: state };
  });
  productionChild.addNode('classify', async (state) => {
    productionTrace.child.push('classify');
    return { state: state };
  });
  productionChild.addEdge('START', 'capture');
  productionChild.addEdge('capture', 'classify');
  productionChild.addEdge('classify', 'END');

  const productionParent = new StateGraph('START', 'END');
  productionParent.addNode('p1', async (state) => {
    productionTrace.parent.push('p1');
    return state;
  });
  productionParent.addNode('p2', async (state) => {
    productionTrace.parent.push('p2');
    return await productionChild.run(captureState(productionToken));
  });
  productionParent.addNode('p3', async (state) => {
    productionTrace.parent.push('p3');
    return state;
  });
  productionParent.addEdge('START', 'p1');
  productionParent.addEdge('p1', 'p2');
  productionParent.addEdge('p2', 'p3');
  productionParent.addEdge('p3', 'END');

  let productionCaught;
  let productionFinal;
  try {
    productionFinal = await productionParent.run({ step: 'START', token: productionToken }, 8);
  } catch (error) {
    productionCaught = error;
  }
  const productionError = productionFinal === undefined ? undefined : productionFinal.error;
  const cancellationSwallowed = productionCaught === undefined
    && productionError !== undefined
    && productionError.kind === 'NODE_ERROR'
    && productionError.retriable === false;
  const parentContinued = productionTrace.parent.includes('p3');

  const verdict = contextFields.length === 0 || !kernelBubbled || cancellationSwallowed ? 'FAIL' : 'PASS';
  report(1, verdict,
    `StateGraph fields=${JSON.stringify(contextFields)}; token only via state; `
    + `kernelBubble=${kernelBubbled} trace=${JSON.stringify(kernelTrace)}; `
    + `CaptureGraph cancel->kind=${productionError === undefined ? 'none' : productionError.kind} `
    + `retriable=${productionError === undefined ? 'none' : productionError.retriable} `
    + `parentContinued=${parentContinued}`);
}

// ---------------------------------------------------------------------------
// Q2: does maxNodeRuns accumulate across the parent/child boundary?
// ---------------------------------------------------------------------------
async function q2() {
  let parentRuns = 0;
  let childRuns = 0;
  const child = linearGraph(['c1', 'c2', 'c3'], () => {
    childRuns += 1;
  });
  const parent = new StateGraph('START', 'END');
  parent.addNode('p1', async (state) => {
    parentRuns += 1;
    return state;
  });
  parent.addNode('p2', async (state) => {
    parentRuns += 1;
    return await child.run(state, 4);
  });
  parent.addNode('p3', async (state) => {
    parentRuns += 1;
    return state;
  });
  parent.addEdge('START', 'p1');
  parent.addEdge('p1', 'p2');
  parent.addEdge('p2', 'p3');
  parent.addEdge('p3', 'END');

  let combinedThrew = false;
  try {
    await parent.run({}, 4);
  } catch (error) {
    combinedThrew = true;
  }
  const total = parentRuns + childRuns;
  const notCumulative = combinedThrew === false && total > 4;

  // The other direction: the child enforces its own limit even though the parent still has
  // budget left. That is the same "each graph counts alone" fact.
  let childOnlyRuns = 0;
  let parentBeforeChild = 0;
  const childOnly = linearGraph(['d1', 'd2', 'd3', 'd4', 'd5'], () => {
    childOnlyRuns += 1;
  });
  const parent2 = new StateGraph('START', 'END');
  parent2.addNode('p1', async (state) => {
    parentBeforeChild += 1;
    return state;
  });
  parent2.addNode('p2', async (state) => {
    return await childOnly.run(state, 4);
  });
  parent2.addEdge('START', 'p1');
  parent2.addEdge('p1', 'p2');
  parent2.addEdge('p2', 'END');

  let childOnlyKind = 'none';
  try {
    await parent2.run({}, 4);
  } catch (error) {
    childOnlyKind = error instanceof StateGraphError ? error.kind : 'other';
  }

  const verdict = notCumulative || (childOnlyKind === 'MAX_NODE_RUNS' && parentBeforeChild < 4) ? 'FAIL' : 'PASS';
  report(2, verdict,
    `parentBudget=4 parentRuns=${parentRuns} childRuns=${childRuns} total=${total} `
    + `combinedThrew=${combinedThrew}; childBudget=4 childRan=${childOnlyRuns} `
    + `childError=${childOnlyKind} parentRunsBeforeChild=${parentBeforeChild}`);
}

// ---------------------------------------------------------------------------
// Q3: does a domain error cross the subgraph boundary with kind / step / retriable intact?
// ---------------------------------------------------------------------------
async function q3() {
  const domainError = new ProbeDomainError('LLM_UNAVAILABLE', 'child1', true, 'rate limited');

  // (a) Raw StateGraph: run() does not catch node errors, so the object crosses untouched.
  const kernelChild = new StateGraph('START', 'END');
  kernelChild.addNode('child1', async () => {
    throw domainError;
  });
  kernelChild.addEdge('START', 'child1');
  kernelChild.addEdge('child1', 'END');

  const kernelParent = new StateGraph('START', 'END');
  let kernelCaught;
  kernelParent.addNode('p1', async (state) => {
    try {
      return await kernelChild.run(state, 8);
    } catch (error) {
      kernelCaught = error;
      throw error;
    }
  });
  kernelParent.addEdge('START', 'p1');
  kernelParent.addEdge('p1', 'END');
  try {
    await kernelParent.run({}, 8);
  } catch (error) {
    // expected: the same object
  }
  // Do not use `instanceof ProbeDomainError` as the verdict: the loader is a vm realm and
  // identity there is a harness artifact. name + own fields are the product contract.
  const kernelPreserved = kernelCaught !== undefined
    && kernelCaught.name === 'CaptureGraphError'
    && kernelCaught.kind === 'LLM_UNAVAILABLE'
    && kernelCaught.step === 'child1'
    && kernelCaught.retriable === true;

  // (b) Production shape: CaptureGraph's wrapper catches every node throw and returns
  // NODE_ERROR (CaptureGraph.ets:41-43), so kind / step / retriable are lost.
  const productionChild = new CaptureGraph();
  productionChild.addNode('capture', async () => {
    throw new ProbeDomainError('LLM_UNAVAILABLE', 'capture', true, 'rate limited');
  });
  productionChild.addEdge('START', 'capture');
  productionChild.addEdge('capture', 'END');
  const productionFinal = await productionChild.run(captureState(new CancellationToken()));
  const flattened = productionFinal.error;
  const wrapperPreserved = flattened !== undefined
    && flattened.kind === 'LLM_UNAVAILABLE'
    && flattened.retriable === true;

  const verdict = kernelPreserved && wrapperPreserved ? 'PASS' : 'FAIL';
  report(3, verdict,
    `kernelPreserved=${kernelPreserved} name=${kernelCaught === undefined ? 'none' : kernelCaught.name} `
    + `kind=${kernelCaught === undefined ? 'none' : kernelCaught.kind} `
    + `step=${kernelCaught === undefined ? 'none' : kernelCaught.step} `
    + `retriable=${kernelCaught === undefined ? 'none' : kernelCaught.retriable}; `
    + `CaptureGraph boundary kind=${flattened === undefined ? 'none' : flattened.kind} `
    + `step=${flattened === undefined ? 'none' : flattened.step} `
    + `retriable=${flattened === undefined ? 'none' : flattened.retriable}`);
}

// ---------------------------------------------------------------------------
// Q4: do Worker nodes only carry serializable data? Static evidence only.
// ---------------------------------------------------------------------------
function collectEtsFiles(directory, files = []) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'oh_modules' || entry.name === 'build'
      || entry.name === '.git' || entry.name === '.hvigor') {
      continue;
    }
    const fullPath = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      collectEtsFiles(fullPath, files);
    } else if (entry.name.endsWith('.ets')) {
      files.push(fullPath);
    }
  }
  return files;
}

function q4() {
  const files = collectEtsFiles(root);
  const addNodeFiles = [];
  const workerGraphNodes = [];
  const workerMarkers = /ThreadWorker|workerPort|postMessage/;
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    if (text.includes('.addNode(')) {
      addNodeFiles.push(relative(root, file).replace(/\\/g, '/'));
      if (workerMarkers.test(text)) {
        workerGraphNodes.push(relative(root, file).replace(/\\/g, '/'));
      }
    }
  }

  // Nearest Worker protocols: both ends are plain interfaces (string / number / boolean /
  // arrays), and the callers post only those objects. There is no token, runId, deadline or
  // class instance on the wire.
  const chatWorker = readFileSync(resolve(root, 'entry/src/main/ets/workers/ChatPersistenceWorker.ets'), 'utf8');
  const imageWorker = readFileSync(resolve(root, 'entry/src/main/ets/workers/ImageSearchWorker.ets'), 'utf8');
  const chatProtocolPlain = chatWorker.includes('interface ChatWorkerRequest')
    && chatWorker.includes('interface ChatWorkerResponse')
    && chatWorker.includes('postMessage(');
  const imageProtocolPlain = imageWorker.includes('interface SearchRequest')
    && imageWorker.includes('interface SearchReply')
    && imageWorker.includes('postMessage(');

  const noWorkerNode = workerGraphNodes.length === 0;
  const verdict = noWorkerNode && chatProtocolPlain && imageProtocolPlain ? 'PASS' : 'NEEDS-CHANGE';
  const applicability = noWorkerNode
    ? '现状无 Worker 节点，此项无适用对象'
    : 'Worker-marked graph files found';
  report(4, verdict,
    `addNodeFiles=${addNodeFiles.length} workerMarkedGraphFiles=${JSON.stringify(workerGraphNodes)}; `
    + `${applicability}; nearest protocols plain=`
    + `ChatPersistenceWorker.ets:27-43/${chatProtocolPlain} ImageSearchWorker.ets:39-55/${imageProtocolPlain}`);
}

async function main() {
  await q1();
  await q2();
  await q3();
  q4();
  const blocking = verdicts.filter((item) => item.verdict !== 'PASS');
  console.log(`SUMMARY blocking=${blocking.length} total=${verdicts.length}`);
  if (blocking.length > 0) {
    console.log('DECISION stop: any FAIL/NEEDS-CHANGE means no #241; go back to section 17 and revise.');
  } else {
    console.log('DECISION proceed: all four questions pass.');
  }
}

main().catch((error) => {
  console.error('HARNESS ERROR ' + (error === undefined ? 'undefined' : error.stack ?? error.message ?? String(error)));
  process.exitCode = 1;
});
