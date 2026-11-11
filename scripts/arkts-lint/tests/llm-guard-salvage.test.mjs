import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

// 真机现象: A2A 聊天回复走 LlmGuard 的严格 JSON 校验, 模型偶尔不按 JSON 回
// (纯文本 / 多个对象 / 被截断), A2A 又是 0 重试, 于是一整条回复变成
// 「模型暂时不可用: chat answer validation failed after retry: JSON object extraction failed」。
// 这里把三类坏样本直接喂给真实的 LlmGuard.ets, 锁住「能救就救, 救不了才抛」。

function loadGuard(responses) {
  let index = 0;
  class FakeClient {
    async call() {
      const value = responses[Math.min(index, responses.length - 1)];
      index += 1;
      return { text: value, streamed: false };
    }
  }
  const mod = loadNoteReviewEtsModule('common/src/main/ets/llm/LlmGuard.ets', {
    mocks: {
      'common/src/main/ets/llm/LlmClient.ets': { LlmClient: FakeClient },
      'common/src/main/ets/llm/LlmOutputRules.ets': {
        buildGuardRetryMessage: () => ({ role: 'user', content: 'retry' }),
      },
    },
  });
  return { LlmGuard: mod.LlmGuard, calls: () => index };
}

function validator(json) {
  const answer = json.answer;
  if (typeof answer !== 'string' || answer.trim().length === 0) {
    return { ok: false, issues: ['answer must be a non-empty string'] };
  }
  return { ok: true, issues: [] };
}

const jsonCall = (mod, responses, salvageKey) => new mod.LlmGuard().callJsonWithRetry(
  [{ role: 'user', content: '整理数学题' }],
  Object.assign({ maxRetries: 0, label: 'chat answer' },
    salvageKey === undefined ? {} : { salvageKey }),
  validator,
);

test('严格 JSON 正常时照旧取 answer, 不走救回', async () => {
  const { LlmGuard } = loadGuard(['{"answer":"先看题目。"}']);
  const result = await jsonCall({ LlmGuard }, ['{"answer":"先看题目。"}'], 'answer');
  assert.equal(result.json.answer, '先看题目。');
  assert.equal(result.salvaged, undefined);
});

test('模型回了纯文本: 有 salvageKey 就把原文当答案, 不再整条失败', async () => {
  const raw = '你只说了「整理数学题」，还缺少要整理的内容。请把题目发给我。';
  const { LlmGuard } = loadGuard([raw]);
  const result = await jsonCall({ LlmGuard }, [raw], 'answer');
  assert.equal(result.json.answer, raw);
  assert.equal(result.salvageMode, 'plain_text');
});

test('模型套了 ```json 围栏: 能从围栏里取出对象', async () => {
  const raw = '```json\n{"answer":"围栏里的答案"}\n```';
  const { LlmGuard } = loadGuard([raw]);
  const result = await jsonCall({ LlmGuard }, [raw], 'answer');
  assert.equal(result.json.answer, '围栏里的答案');
});

test('模型回了两个对象: 取第一个带 answer 的', async () => {
  const raw = '{"note":"x"}\n{"answer":"第二个对象里的答案"}';
  const { LlmGuard } = loadGuard([raw]);
  const result = await jsonCall({ LlmGuard }, [raw], 'answer');
  assert.equal(result.json.answer, '第二个对象里的答案');
  assert.equal(result.salvageMode, 'multi_object');
});

test('回复被截断: 捞回已生成的那部分正文, 转义按 JSON 规则还原', async () => {
  const raw = '{"answer":"第一段\\n第二段讲到一半';
  const { LlmGuard } = loadGuard([raw]);
  const result = await jsonCall({ LlmGuard }, [raw], 'answer');
  assert.equal(result.json.answer, '第一段\n第二段讲到一半');
  assert.equal(result.salvageMode, 'truncated');
});

test('没开 salvageKey 的结构化链路仍然抛错, 半成品不许当成品', async () => {
  const raw = '这是一段不该被当成 JSON 的纯文本';
  const { LlmGuard } = loadGuard([raw]);
  await assert.rejects(
    () => jsonCall({ LlmGuard }, [raw], undefined),
    /JSON object extraction failed/,
  );
});

test('救不回来的内容(只有半截对象且没有 answer)仍然抛错', async () => {
  const raw = '{"note":"只有 note 字段';
  const { LlmGuard } = loadGuard([raw]);
  await assert.rejects(
    () => jsonCall({ LlmGuard }, [raw], 'answer'),
    /validation failed after 1 attempt/,
  );
});
