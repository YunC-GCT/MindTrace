// 路径: scripts/arkts-lint/tests/v7-a2a-error-taxonomy.test.mjs
// 职责: A2A 错误分类/文案统一映射，以及 controller/ability 不再各自拼错误字符串。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const taxonomy = loadNoteReviewEtsModule('entry/src/main/ets/services/A2AErrorTaxonomy.ets');
const { a2aErrorKind, a2aErrorText } = taxonomy;

test('A2A 错误分类覆盖 protocol/config/model/timeout/ingest', () => {
  assert.equal(a2aErrorKind('A2A_PARSE_ERROR'), 'protocol');
  assert.equal(a2aErrorKind('A2A_CONFIG_READ_TIMEOUT'), 'config');
  assert.equal(a2aErrorKind('A2A_MODEL_UNUSABLE'), 'model');
  assert.equal(a2aErrorKind('A2A_MODEL_ID_UNRESOLVED'), 'model');
  assert.equal(a2aErrorKind('A2A_MODEL_NOT_READY'), 'model');
  assert.equal(a2aErrorKind('A2A_LLM_FAILED'), 'model');
  assert.equal(a2aErrorKind('A2A_LLM_TIMEOUT'), 'timeout');
  assert.equal(a2aErrorKind('A2A_DEADLINE_EXCEEDED'), 'timeout');
  assert.equal(a2aErrorKind('A2A_INGEST_TIMEOUT'), 'ingest');
  assert.equal(a2aErrorKind('A2A_INGEST_FAILED'), 'ingest');
  assert.equal(a2aErrorKind('A2A_REPLY_SENT'), 'none');
});

test('A2A 错误文案保持既有口径', () => {
  assert.equal(a2aErrorText('A2A_PARSE_ERROR'), '请求解析失败，请重试。');
  assert.equal(a2aErrorText('A2A_CONFIG_READ_TIMEOUT', '4000'), '模型配置读取超时（4000 ms），请稍后再试。');
  assert.equal(a2aErrorText('A2A_MODEL_UNUSABLE', 'deepseek-x（MODEL_UNAVAILABLE）'), '模型不可用：deepseek-x（MODEL_UNAVAILABLE）');
  assert.equal(a2aErrorText('A2A_MODEL_NOT_READY'), '端侧模型未就绪（model file not found），请先在 MindTrace 设置里配置模型');
  assert.equal(a2aErrorText('A2A_LLM_TIMEOUT'), '模型响应超时，稍后再试。');
  assert.equal(a2aErrorText('A2A_DEADLINE_EXCEEDED'), '模型响应超时，稍后再试。');
  assert.equal(a2aErrorText('A2A_LLM_FAILED', 'API_ERROR'), '模型暂时不可用：API_ERROR');
  assert.equal(a2aErrorText('A2A_INGEST_TIMEOUT'), '这次整理较慢，已转待整理；打开 MindTrace 会自动补齐，稍后也能在 App 里看到。');
  assert.equal(a2aErrorText('A2A_INGEST_FAILED', 'NOTE_WRITE_FAILED'), '这次没整理成（NOTE_WRITE_FAILED），换个说法再发一次试试。');
});

test('controller / ability 只经 taxonomy 拼错误文案', () => {
  const controller = [
    read('entry/src/main/ets/services/A2AController.ets'),
    read('entry/src/main/ets/services/A2AIngestHandler.ets'),
    read('entry/src/main/ets/services/A2AConstants.ets'),
    read('entry/src/main/ets/services/A2AAnswerHandler.ets'),
    read('entry/src/main/ets/services/A2ASession.ets'),
  ].join('\n');
  assert.match(controller, /import \{ a2aErrorText \} from '\.\/A2AErrorTaxonomy'/);
  for (const legacy of ['A2A_INGEST_TIMEOUT_TEXT', 'A2A_TIMEOUT_TEXT', 'A2A_CONFIG_TIMEOUT_TEXT', 'MODEL_NOT_READY']) {
    assert.equal(controller.includes('const ' + legacy), false, legacy + ' should be removed');
  }
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.match(ability, /a2aErrorText\('A2A_PARSE_ERROR'\)/);
  assert.doesNotMatch(ability, /const PARSE_ERROR/);
});
