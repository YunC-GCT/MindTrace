// 路径: scripts/arkts-lint/tests/v7-agent-ingest-request.test.mjs
// 职责: 入口层与整理层之间数据契约的契约测试（装载真实 .ets）。
// Why: 所有入口（小艺文字 / 小艺图片 / 应用选图 / 分享）都折成同一个请求，
//      如果「空请求」判定松了，就会拿空文本去调模型或入队。

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('entry/src/main/ets/services/AgentIngestRequest.ets');
const { buildIngestRequest, hasIngestPayload, INGEST_SOURCE_XIAOYI, INGEST_SOURCE_APP_SHARE } = mod;

test('buildIngestRequest keeps source, text and images as given', () => {
  const req = buildIngestRequest(INGEST_SOURCE_XIAOYI, '存笔记：矩阵的秩', []);
  assert.equal(req.source, 'xiaoyi');
  assert.equal(req.text, '存笔记：矩阵的秩');
  assert.equal(req.images.length, 0);
});

test('image-only request is a valid payload', () => {
  const req = buildIngestRequest(INGEST_SOURCE_APP_SHARE, '', [{ kind: 'uri', value: 'file:///x.png' }]);
  assert.equal(hasIngestPayload(req), true);
  assert.equal(req.images.length, 1);
});

test('whitespace-only text with no images is not a payload', () => {
  assert.equal(hasIngestPayload(buildIngestRequest(INGEST_SOURCE_XIAOYI, '   \n ', [])), false);
});

test('empty request is not a payload', () => {
  assert.equal(hasIngestPayload(buildIngestRequest(INGEST_SOURCE_XIAOYI, '', [])), false);
});

test('sources are distinct strings (log field, not an enum index)', () => {
  assert.notEqual(INGEST_SOURCE_XIAOYI, INGEST_SOURCE_APP_SHARE);
  assert.equal(typeof INGEST_SOURCE_XIAOYI, 'string');
});
