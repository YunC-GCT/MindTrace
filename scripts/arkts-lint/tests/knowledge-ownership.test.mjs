import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, relative } from 'node:path';
import { ownershipViolations } from './knowledge-ownership-guard.mjs';

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
