import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const uiRoot = resolve(root, 'entry/src/main/ets');

function collectEtsFiles(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      collectEtsFiles(p, acc);
    } else if (name.endsWith('.ets')) {
      acc.push(p);
    }
  }
  return acc;
}

const FORBIDDEN = [
  { pattern: /from\s+['"][^'"]*database\/(NoteDao|AgentMemoryDao|ChatMessageDao|StudyPlanDao)['"]/, label: 'direct dao import' },
  { pattern: /new\s+NoteDao\s*\(/, label: 'direct NoteDao instantiation' },
  { pattern: /from\s+['"]agents['"]/, label: "direct 'agents' package import" },
  { pattern: /new\s+(Dispatcher|KnowledgeModel|LlmClient|TypeClassifier|OcrTool)\s*\(/, label: 'direct agents-internal instantiation' },
];

// D3 spec 012: UI 层 (pages/ + overlays/) 禁止直连 database/dao 与 agents 内部实现;
// 必须经由 services/ 或 viewmodels/。
test('pages and overlays never import database/dao or agents internals directly', () => {
  const violations = [];
  for (const scope of ['pages', 'overlays']) {
    const files = collectEtsFiles(join(uiRoot, scope));
    assert.ok(files.length > 0, `expected .ets files under ${scope}`);
    for (const file of files) {
      const text = readFileSync(file, 'utf8');
      for (const rule of FORBIDDEN) {
        if (rule.pattern.test(text)) {
          violations.push(`${file.replace(uiRoot + '\\', '').replace(uiRoot + '/', '')}: ${rule.label}`);
        }
      }
    }
  }
  assert.deepEqual(violations, []);
});

// F2 小步先修 (agent-tools inventory 2026-09-06): StudyPlan AI 生成抽到 Service 层,
// ViewModel 不再直连 LlmClient / 自带解析; 持久化仍由 ViewModel 的 UI-CRUD 路径执行
// (行为零变化), 写路径统一属 F2 长期项。
test('StudyPlan AI generation lives in services layer (F2 small step)', () => {
  const vm = readFileSync(resolve(root, 'entry/src/main/ets/viewmodels/StudyPlanViewModel.ets'), 'utf8');
  const svc = readFileSync(resolve(root, 'entry/src/main/ets/services/StudyPlanService.ets'), 'utf8');
  assert.doesNotMatch(vm, /LlmClient|LlmCallResult|ChatMessage/, 'StudyPlanViewModel must not touch the LLM layer');
  assert.doesNotMatch(vm, /parsePlanTitles/, 'parsing must live in StudyPlanService');
  assert.match(svc, /class StudyPlanService/);
  assert.match(svc, /static async generateTitles\(knownTitles: string\[\]\): Promise<string\[\]>/);
  assert.match(svc, /new LlmClient\(\)/);
  assert.match(vm, /StudyPlanService\.generateTitles\(knownTitles\)/);
  assert.match(vm, /this\.dao\.insert\(item\)/, 'insert stays in the ViewModel until F2 write-path unification');
});
