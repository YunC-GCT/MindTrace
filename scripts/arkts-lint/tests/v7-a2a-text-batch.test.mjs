// 路径: scripts/arkts-lint/tests/v7-a2a-text-batch.test.mjs
// 职责: A2A「图片识别后的文字」通道契约：一段 OCR 文本按题切分（036 planner），
//       首题同步入库、其余转待整理队列，避免超出端A2A 35s 预算。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('AgentIngestService 文本入口复用 036 planner 并按题拆分', () => {
  const service = read('entry/src/main/ets/services/AgentIngestService.ets');
  assert.match(service, /static async ingestTextBatch\(context: common\.Context, text: string\): Promise<AgentTextBatchResult>/);
  assert.match(service, /planCaptureSet\(pages\)/);
  assert.match(service, /queuedTexts: queued/);
  assert.match(service, /plan\.problems\.length <= 1/);
});

test('A2A 文本路径：首题同步回执，其余入待整理队列', () => {
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.match(ability, /AgentIngestService\.ingestTextBatch\(this\.context, request\.text\)/);
  assert.match(ability, /private handleTextBatch\(/);
  assert.match(ability, /private enqueueTexts\(texts: string\[\]\): void/);
  assert.match(ability, /已转待整理/);
  assert.match(ability, /打开 MindTrace 会自动补齐/);
});

test('e2e agentTextBatch 已注册（真机可自检）', () => {
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(entry, /mode === 'agentTextBatch'/);
  const runner = read('entry/src/main/ets/services/DebugCaptureRunner.ets');
  assert.match(runner, /static async runAgentTextBatch\(/);
});
