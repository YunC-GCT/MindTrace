import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const errorText = read('entry/src/main/ets/services/StreamErrorText.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');

const mappings = [
  {
    name: 'missing API key',
    keywords: ['NO_API_KEY', '未配置模型密钥，请到设置里填写'],
  },
  {
    name: 'authentication failure',
    keywords: ['auth', '401', '403', '鉴权失败，请检查密钥是否正确'],
  },
  {
    name: 'rate limit',
    keywords: ['rate', 'too many', '429', '请求太频繁，稍后再试'],
  },
  {
    name: 'timeout',
    keywords: ['timeout', 'etimedout', '等待模型超时，可重试'],
  },
  {
    name: '5xx service failure',
    keywords: ['500', '502', '503', '模型服务异常，稍后再试'],
  },
  {
    name: 'generic fallback with 80-character clipping',
    keywords: ['请求失败：', 'substring(0, 80)'],
  },
];

test('StreamErrorText exists and exports streamErrorText(code, rawMessage)', () => {
  assert.match(
    errorText,
    /export function streamErrorText\(code: number, rawMessage: string\): string/,
  );
});

for (const mapping of mappings) {
  test('StreamErrorText maps ' + mapping.name, () => {
    for (const keyword of mapping.keywords) {
      assert.ok(errorText.includes(keyword), 'missing keyword: ' + keyword);
    }
  });
}

test('ConversationWorkflow emits stream timing and reconnect diagnostics', () => {
  assert.match(workflow, /\[StreamTiming\]/);
  assert.match(workflow, /\[StreamRecovery\] reconnect_ok/);
  assert.match(workflow, /\[StreamRecovery\] reconnect_failed/);
});
