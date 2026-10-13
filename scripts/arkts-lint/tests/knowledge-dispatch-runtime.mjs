// #210: real ETS business modules; only external LLM/platform/storage boundaries are faked.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { posix } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const require = createRequire(import.meta.url);
const ts = require('typescript');
const barrelPath = 'common/src/main/ets/Index.ets';
const barrel = ts.createSourceFile(barrelPath,
  readFileSync(new URL('../../../common/src/main/ets/Index.ets', import.meta.url), 'utf8'),
  ts.ScriptTarget.Latest, true);

export function createRuntime(respond = () => { throw new Error('Unexpected LLM request'); }) {
  const requests = [];
  class LlmClient {
    async call(request) {
      requests.push(request);
      const response = await respond(request, requests.length);
      return { text: typeof response === 'string' ? response : JSON.stringify(response), streamed: false };
    }
  }
  const unavailable = new Proxy({}, { get: (_target, name) => () => {
    throw new Error(`Unexpected platform IO: ${String(name)}`);
  } });
  const common = {};
  const options = { cache: new Map(), globals: { Error }, mocks: {
    common,
    'common/src/main/ets/llm/LlmClient.ets': { LlmClient },
    '@ohos.hilog': { debug() {}, info() {}, warn() {}, error() {} },
    '@kit.ArkData': { preferences: unavailable },
    '@kit.AssetStoreKit': { asset: unavailable },
    '@kit.ArkTS': { util: { TextEncoder, TextDecoder } },
    '@kit.CoreVisionKit': { textRecognition: unavailable },
    '@kit.ImageKit': { image: unavailable },
    '@kit.NetworkKit': { http: unavailable },
  } };
  const load = path => options.mocks[path] ?? loadNoteReviewEtsModule(path, options);
  // Resolve the real public barrel lazily: loading UI-only exports must not be necessary in Node.
  for (const statement of barrel.statements) {
    if (!ts.isExportDeclaration(statement) || !statement.moduleSpecifier ||
        !statement.exportClause || !ts.isNamedExports(statement.exportClause)) continue;
    const path = posix.join(posix.dirname(barrelPath), `${statement.moduleSpecifier.text}.ets`);
    for (const item of statement.exportClause.elements) {
      Object.defineProperty(common, item.name.text, { configurable: true,
        get: () => load(path)[(item.propertyName ?? item.name).text] });
    }
  }
  const { Dispatcher } = load('agents/src/main/ets/core/Dispatcher.ets');
  const { KnowledgeModel } = load('agents/src/main/ets/agents/KnowledgeModel.ets');
  return { common, load, requests, dispatcher: new Dispatcher(), model: new KnowledgeModel(new LlmClient()) };
}

export function generationRequest(route = 'light') {
  return { source: 'text', payload: { kind: 'text', text: '函数在一点连续。' }, generation: {
    runId: 'baseline-run', instruction: '保留定义', mode: 'create', route,
    sources: { fragments: [{ id: 'src-1', kind: 'conversation', originId: 'origin-1',
      sequence: 0, fingerprint: 'fp-1', text: '函数在一点连续。' }] },
  } };
}

export function draft(content = '函数在一点连续。') {
  return { schemaVersion: 'mm-note-draft-v1', title: '连续性', summary: '函数连续性的定义',
    subject: '数学分析', category: '概念', chapter: '连续性', difficulty: 1, tags: [],
    sections: [{ id: 'sec-1', label: '定义', content, sourceIds: ['src-1'], state: 'generated', baseHash: '' }] };
}

export function memoryStorage() {
  const checkpoints = [], commits = [], writes = [], events = [];
  let run;
  return { checkpoints, commits, writes, events,
    repository: {
      async saveRun(value) { run = value; events.push(`run:${value.status}`); },
      async saveCheckpoint(value) { checkpoints.push(value); events.push('checkpoint'); },
      async restore() { return { run, checkpoints }; },
      async getCommitResult(key) { return commits.find(c => c.commitKey === key); },
      async saveCommitResult(value) { commits.push(value); events.push('commit'); },
      async appendLifecycleLog(value) { events.push(value.event); },
    },
    dao: {
      async insert(value) { writes.push(value); events.push('insert'); return 42; },
      async insertWithCommitKey(value) {
        writes.push(value); events.push('insert');
        return { success: true, noteId: value.id, version: value.version, duplicate: false };
      },
    },
  };
}
