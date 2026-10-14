import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, relative } from 'node:path';
import { ownershipViolations } from './knowledge-ownership-guard.mjs';
import ts from 'typescript';

const root = fileURLToPath(new URL('../../../', import.meta.url));
function productionSources() {
  const files = new Map();
  function walk(directory) {
    for (const item of readdirSync(directory, { withFileTypes: true })) {
      const path = resolve(directory, item.name);
      if (item.isDirectory()) walk(path);
      else if (/\.(ets|ts)$/.test(item.name)) {
        files.set(relative(root, path).replaceAll('\\', '/'), readFileSync(path, 'utf8'));
      }
    }
  }
  for (const module of ['agents', 'entry', 'common', 'skill', 'cardservice']) {
    walk(resolve(root, module, 'src/main'));
  }
  return files;
}

const fixture = () => new Map([
  ['agents/src/main/ets/graph/AgentState.ets', 'export interface AgentState { text: string }'],
  ['agents/src/main/ets/graph/CaptureGraph.ets', 'export class CaptureGraph {}'],
  ['agents/src/main/ets/agents/TruthCheckService.ets',
    'export class TruthCheckService { check(text: string) { return this.truthCheck(text); } truthCheck(text: string) { return true; } }'],
  ['agents/src/main/ets/Index.ets',
    "export { AgentState } from './graph/AgentState'; export { CaptureGraph } from './graph/CaptureGraph'; export { TruthCheckService } from './agents/TruthCheckService';"],
]);

for (const source of [
  "import type { AgentState as State } from 'agents'; let state: State;",
  "import { CaptureGraph as Graph } from 'agents'; new Graph();",
  "import * as api from 'agents'; new api.CaptureGraph();",
  "import * as graph from 'agents/src/main/ets/graph/CaptureGraph';",
]) {
  test(`guard detects entry graph/state dependency: ${source}`, () => {
    const files = fixture();
    files.set('entry/src/main/ets/services/NewCaller.ets', source);
    assert.equal(ownershipViolations(files).length, 1);
  });
}

for (const source of [
  "import { TruthCheckService as Check } from 'agents'; new Check().check('x');",
  "import * as api from 'agents'; new api.TruthCheckService().truthCheck('x');",
  "import { TruthCheckService } from 'agents'; new TruthCheckService()['check']('x');",
  "import { TruthCheckService } from 'agents'; function run(checker: TruthCheckService) { const check = checker.check; }",
]) {
  test(`guard detects TruthCheck escaping into any future module: ${source}`, () => {
    const files = fixture();
    files.set('agents/src/main/ets/agents/FutureComposer.ets', source);
    assert.equal(ownershipViolations(files).length, 1);
  });
}

test('guard allows service construction in host, node invocation and unrelated check methods', () => {
  const files = fixture();
  files.set('agents/src/main/ets/core/Dispatcher.ets',
    "import { TruthCheckService } from 'agents'; const service = new TruthCheckService();");
  files.set('agents/src/main/ets/graph/nodes/TruthCheckNode.ets',
    "import { TruthCheckService } from 'agents'; new TruthCheckService().check('x');");
  files.set('entry/src/main/ets/services/ValidCaller.ets',
    "// CaptureGraph AgentState TruthCheckService.check are documentation, not dependencies\nconst other = { check() {} }; other.check();");
  assert.deepEqual(ownershipViolations(files), []);
});

test('all production sources preserve Capture and TruthCheck ownership', () => {
  const sources = productionSources();
  assert.ok(sources.size > 100, 'scan must include the production tree, not a file allowlist');
  assert.deepEqual(ownershipViolations(sources), []);
});

test('KnowledgeModel compatibility methods contain delegation only after phase-one extraction', () => {
  const text = productionSources().get('agents/src/main/ets/agents/KnowledgeModel.ets');
  const ast = ts.createSourceFile('KnowledgeModel.ets', text, ts.ScriptTarget.Latest, true);
  const methods = ast.statements.find(ts.isClassDeclaration).members.filter(ts.isMethodDeclaration);
  assert.deepEqual(methods.map(m => m.name.getText(ast)), [
    'structure', 'structureWithClassification', 'structureLightDraft', 'structureStandardDraft',
    'structureDeepDraft', 'repairIncrementalSections', 'draftToKnowledgeUnit',
  ]);
  for (const method of methods) {
    assert.equal(method.body.statements.length, 1, `${method.name.getText(ast)} still contains implementation`);
    assert.ok(ts.isReturnStatement(method.body.statements[0]));
    let expression = method.body.statements[0].expression;
    if (ts.isAwaitExpression(expression)) expression = expression.expression;
    assert.ok(ts.isCallExpression(expression), 'compatibility method must return its collaborator result');
  }
});

test('deep and incremental own their implementations, with one shared read-only verifier', () => {
  const sources = productionSources();
  const source = name => sources.get(`agents/src/main/ets/agents/${name}.ets`);
  const methods = name => {
    const ast = ts.createSourceFile(name, source(name), ts.ScriptTarget.Latest, true);
    return ast.statements.filter(ts.isClassDeclaration).flatMap(c =>
      c.members.filter(ts.isMethodDeclaration).map(m => m.name.getText(ast)));
  };
  const deep = source('DeepDraftComposer');
  const incremental = source('IncrementalPatchComposer');
  for (const text of [deep, incremental]) {
    assert.doesNotMatch(text, /from ['"]\.\/DraftComposer['"]/);
    assert.match(text, /this\.jsonCaller\.callJson\(/);
  }
  assert.deepEqual(methods('DeepDraftComposer'),
    ['compose', 'callDeepSectionDraft', 'updateDeepLedger', 'buildDeepEvidence']);
  assert.deepEqual(methods('IncrementalPatchComposer'), ['compose']);
  assert.match(incremental, /plan\.targetSectionIds\.includes\(section\.id\)/);
  assert.match(incremental, /plan\.relevantSourceIds\.includes\(source\.id\)/);
  assert.match(incremental, /incremental repair contains an unplanned patch/);
  assert.doesNotMatch(source('DraftComposer'), /composeDeepDraft|callDeepSectionDraft|updateDeepLedger|buildDeepEvidence|composeIncrementalPatch|repairIncrementalSections|callIndependentVerifier/);
  for (const name of ['DraftComposer', 'DeepDraftComposer']) {
    assert.match(source(name), /this\.verifier\.verify\(/);
    assert.doesNotMatch(source(name), /Act as a read-only independent note verifier/);
  }
  assert.match(source('NoteDraftVerifier'), /Act as a read-only independent note verifier/);
  assert.doesNotMatch(source('NoteDraftVerifier'), /from ['"]\.\/(DraftComposer|DeepDraftComposer|NoteDraftVerifier)['"]/);
  assert.doesNotMatch(deep, /repairDeepDraft/);
});
