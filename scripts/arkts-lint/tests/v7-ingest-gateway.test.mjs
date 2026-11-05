// 路径: scripts/arkts-lint/tests/v7-ingest-gateway.test.mjs
// 职责: IngestGateway 是 A2A / 分享 / inbox 的唯一模式决策点；入口层不得直连底层整理服务。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('IngestGateway 统一 inline/background 模式', () => {
  const gateway = read('entry/src/main/ets/services/IngestGateway.ets');
  assert.match(gateway, /export type IngestMode = 'inline' \| 'background'/);
  assert.match(gateway, /INGEST_MODE_INLINE/);
  assert.match(gateway, /INGEST_MODE_BACKGROUND/);
  assert.match(gateway, /AgentIngestService\.ingestTextBatch\(context, text\)/);
  assert.match(gateway, /AgentIngestService\.ingestSingleText\(context, text, 'background'\)/);
  assert.match(gateway, /AgentIngestService\.ingestOutcome\(context, request\)/);
  assert.match(gateway, /AgentIngestService\.planItemsFromRequest\(request\)/);
});

test('A2A 控制器只经 IngestGateway，不直连 AgentIngestService', () => {
  const controller = [
    read('entry/src/main/ets/services/A2AController.ets'),
    read('entry/src/main/ets/services/A2AIngestHandler.ets'),
    read('entry/src/main/ets/services/A2AConstants.ets'),
    read('entry/src/main/ets/services/A2AAnswerHandler.ets'),
    read('entry/src/main/ets/services/A2ASession.ets'),
  ].join('\n');
  assert.match(controller, /IngestGateway\.plan\(request\)/);
  assert.match(controller, /IngestGateway\.ingest\((?:this\.context|this\.host\.ingestContext\(\)), request, INGEST_MODE_INLINE\)/);
  assert.match(controller, /IngestGateway\.ingestText\((?:this\.context|this\.host\.ingestContext\(\)), text, INGEST_SOURCE_XIAOYI, INGEST_MODE_INLINE\)/);
  assert.equal(controller.includes('AgentIngestService.ingestTextBatch'), false);
  assert.equal(controller.includes('AgentIngestService.ingestSingleText'), false);
});

test('分享/卡片选图经 IngestGateway，inbox 走 background', () => {
  const entry = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(entry, /IngestGateway\.ingest\((?:this\.context|this\.host\.ingestContext\(\)), request, INGEST_MODE_INLINE\)/);
  assert.equal(entry.includes('AgentIngestService.ingest('), false);
  const inbox = read('entry/src/main/ets/services/A2AInboxIngestService.ets');
  assert.match(inbox, /IngestGateway\.ingestText\(/);
  assert.match(inbox, /INGEST_MODE_BACKGROUND/);
  assert.equal(inbox.includes('AiService.ingestText'), false);
});
