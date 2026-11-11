// scripts/arkts-lint/tests/model-request-spec.test.mjs
//
// 2026-10-26 ModelSpec 请求构造契约 (design §请求构造契约):
//   - JSON 与 SSE 共用的纯函数 planModelRequest 真实可执行
//   - thinking toggle / always_on / unsupported / unverified 四态
//   - 非法 effort 本地收敛; 默认缺失且必填 → 返回 null (规格不完整)
//   - max_tokens = min(max(1, floor(v)), maxOutputTokens), cap 缺失不夹取
//   - sampling 只在 support='yes' 且 when 条件成立时下发
//
// ModelRequestBuilder.ets 只有 import type, 剥掉后可直接 transpile 执行。

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');

async function loadBuilder() {
  const catalog = readFileSync(resolve(root, 'common/src/main/ets/llm/model-catalog.ets'), 'utf8');
  const builder = readFileSync(resolve(root, 'common/src/main/ets/llm/ModelRequestBuilder.ets'), 'utf8')
    .replace(/import\s+type\s+\{[\s\S]*?\}\s+from\s+'\.\/model-catalog';/g, '');
  const js = ts.transpileModule(catalog + '\n' + builder, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ES2022,
    },
  }).outputText;
  return await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}

const mod = await loadBuilder();

function bodyOf(plan) {
  const body = {};
  mod.applyFieldWrites(body, plan.writes);
  return body;
}

test('putField creates nested objects for path writes', () => {
  const body = {};
  mod.putField(body, ['thinking', 'type'], 'enabled');
  mod.putField(body, ['enable_thinking'], true);
  mod.putField(body, ['model'], 'deepseek-flash');
  assert.deepEqual(body, {
    thinking: { type: 'enabled' },
    enable_thinking: true,
    model: 'deepseek-flash',
  });
});

test('DeepSeek spec: thinking defaults on, effort defaults to high, temperature withheld', () => {
  const spec = mod.getModelSpec('deepseek', 'deepseek-flash');
  const plan = mod.planModelRequest(spec, {
    maxTokens: 12000,
    maxOutputTokens: spec.maxOutputTokens,
    temperature: 0.1,
  });
  assert.equal(plan.thinkingControl, 'toggle');
  assert.equal(plan.thinkingEnabled, true);
  assert.equal(plan.effort, 'high');
  // 思考开启时 temperature/top_p 不生效。
  assert.deepEqual(bodyOf(plan), {
    max_tokens: 12000,
    thinking: { type: 'enabled' },
    reasoning_effort: 'high',
  });
});

test('DeepSeek spec: explicit off writes disabled + reasoning_effort=none, keeps temperature', () => {
  const spec = mod.getModelSpec('deepseek', 'deepseek-flash');
  const plan = mod.planModelRequest(spec, {
    maxTokens: 12000,
    maxOutputTokens: spec.maxOutputTokens,
    temperature: 0.1,
    thinking: false,
  });
  assert.equal(plan.thinkingEnabled, false);
  assert.equal(plan.effort, '');
  assert.deepEqual(bodyOf(plan), {
    max_tokens: 12000,
    thinking: { type: 'disabled' },
    reasoning_effort: 'none',
    temperature: 0.1,
  });
});

test('DeepSeek spec: illegal effort falls back to the valid default, never levels[0]', () => {
  const spec = mod.getModelSpec('deepseek', 'deepseek-v4-pro');
  for (const illegal of ['medium', 'none', 'MAX', '']) {
    const plan = mod.planModelRequest(spec, {
      maxTokens: 100,
      maxOutputTokens: spec.maxOutputTokens,
      thinking: true,
      effort: illegal,
    });
    assert.equal(plan.effort, 'high', 'illegal effort "' + illegal + '" must use defaultLevel');
  }
  const valid = mod.planModelRequest(spec, {
    maxTokens: 100,
    maxOutputTokens: spec.maxOutputTokens,
    thinking: true,
    effort: 'max',
  });
  assert.equal(valid.effort, 'max');
});

test('unverified spec: no thinking/effort/temperature is guessed', () => {
  const spec = mod.getModelSpec('tongyi', 'qwen3-max');
  const plan = mod.planModelRequest(spec, {
    maxTokens: 512,
    maxOutputTokens: 0,
    temperature: 0.7,
    thinking: true,
    effort: 'high',
  });
  assert.equal(plan.thinkingControl, 'unverified');
  assert.equal(plan.thinkingEnabled, false);
  assert.deepEqual(bodyOf(plan), { max_tokens: 512 });
});

test('always_on spec: never writes a thinking switch, keeps the rest per spec', () => {
  const spec = mod.getModelSpec('tongyi', 'glm-5.3');
  const plan = mod.planModelRequest(spec, {
    maxTokens: 512,
    maxOutputTokens: 0,
    temperature: 0.7,
    thinking: false,
  });
  assert.equal(plan.thinkingControl, 'always_on');
  assert.equal(plan.thinkingEnabled, true);
  assert.deepEqual(bodyOf(plan), { max_tokens: 512 });
});

test('GLM direct: 5.3 is always_on, 5/5.1/5.2/4.7 toggle thinking.type', () => {
  const alwaysOn = mod.getModelSpec('glm', 'glm-5.3');
  const alwaysOnPlan = mod.planModelRequest(alwaysOn, {
    maxTokens: 256,
    maxOutputTokens: 0,
    thinking: false,
  });
  assert.equal(alwaysOnPlan.thinkingControl, 'always_on');
  assert.equal(alwaysOnPlan.thinkingEnabled, true);
  assert.deepEqual(bodyOf(alwaysOnPlan), { max_tokens: 256 });

  for (const modelId of ['glm-5', 'glm-5.1', 'glm-5.2', 'glm-4.7']) {
    const spec = mod.getModelSpec('glm', modelId);
    const on = mod.planModelRequest(spec, {
      maxTokens: 256,
      maxOutputTokens: 0,
      thinking: true,
    });
    assert.deepEqual(bodyOf(on), {
      max_tokens: 256,
      thinking: { type: 'enabled' },
    }, modelId + ' on branch');

    const off = mod.planModelRequest(spec, {
      maxTokens: 256,
      maxOutputTokens: 0,
      thinking: false,
    });
    assert.deepEqual(bodyOf(off), {
      max_tokens: 256,
      thinking: { type: 'disabled' },
    }, modelId + ' off branch');
  }
});

test('Kimi k2.6: toggle writes thinking.type and never reasoning_effort', () => {
  const spec = mod.getModelSpec('kimi', 'kimi-k2.6');

  const on = mod.planModelRequest(spec, {
    maxTokens: 256,
    maxOutputTokens: 0,
    thinking: true,
    effort: 'high',
  });
  assert.deepEqual(bodyOf(on), {
    max_tokens: 256,
    thinking: { type: 'enabled' },
  }, 'k2.6 must not send reasoning_effort');

  const off = mod.planModelRequest(spec, {
    maxTokens: 256,
    maxOutputTokens: 0,
    thinking: false,
  });
  assert.deepEqual(bodyOf(off), {
    max_tokens: 256,
    thinking: { type: 'disabled' },
  });
});

test('Kimi k2.7-code: always_on never writes a thinking field, even when disabled is requested', () => {
  for (const modelId of ['kimi-k2.7-code', 'kimi-k2.7-code-highspeed']) {
    const spec = mod.getModelSpec('kimi', modelId);
    const plan = mod.planModelRequest(spec, {
      maxTokens: 256,
      maxOutputTokens: 0,
      thinking: false,
    });
    assert.equal(plan.thinkingControl, 'always_on');
    assert.equal(plan.thinkingEnabled, true);
    assert.deepEqual(bodyOf(plan), { max_tokens: 256 }, modelId + ' must not send thinking');
  }
});

test('Kimi k3: always_on + reasoning_effort defaults to max, no thinking field', () => {
  const spec = mod.getModelSpec('kimi', 'kimi-k3');
  const plan = mod.planModelRequest(spec, {
    maxTokens: 512,
    maxOutputTokens: 0,
    thinking: false,
  });
  assert.equal(plan.thinkingControl, 'always_on');
  assert.equal(plan.effort, 'max');
  assert.deepEqual(bodyOf(plan), {
    max_tokens: 512,
    reasoning_effort: 'max',
  });

  const selected = mod.planModelRequest(spec, {
    maxTokens: 512,
    maxOutputTokens: 0,
    effort: 'low',
  });
  assert.equal(bodyOf(selected).reasoning_effort, 'low');
});

test('sampling support=no: temperature/top_p are omitted even when the caller passes values', () => {
  for (const modelId of ['kimi-k2.6', 'kimi-k3']) {
    const spec = mod.getModelSpec('kimi', modelId);
    const plan = mod.planModelRequest(spec, {
      maxTokens: 256,
      maxOutputTokens: 0,
      temperature: 0.2,
      topP: 0.9,
      thinking: false,
    });
    const body = bodyOf(plan);
    assert.equal(body.temperature, undefined, modelId + ' must omit temperature');
    assert.equal(body.top_p, undefined, modelId + ' must omit top_p');
  }
});

test('Doubao: toggle off writes thinking.type=disabled and no effort', () => {
  const spec = mod.getModelSpec('doubao', 'doubao-seed-1.6');
  const off = mod.planModelRequest(spec, {
    maxTokens: 256,
    maxOutputTokens: 0,
    thinking: false,
  });
  assert.deepEqual(bodyOf(off), {
    max_tokens: 256,
    thinking: { type: 'disabled' },
  });
  assert.equal(spec.request.effort, null);
});

test('Bailian toggle spec: flat enable_thinking follows the user selection', () => {
  const spec = mod.getModelSpec('tongyi', 'qwen3.6-plus');

  const on = mod.planModelRequest(spec, { maxTokens: 256, maxOutputTokens: 0, thinking: true });
  assert.deepEqual(bodyOf(on), { max_tokens: 256, enable_thinking: true });

  const off = mod.planModelRequest(spec, { maxTokens: 256, maxOutputTokens: 0, thinking: false });
  assert.deepEqual(bodyOf(off), { max_tokens: 256, enable_thinking: false });

  // defaultEnabled=null 且用户未选择 → 不猜, 让服务端默认生效。
  const undecided = mod.planModelRequest(spec, { maxTokens: 256, maxOutputTokens: 0 });
  assert.deepEqual(bodyOf(undecided), { max_tokens: 256 });
});

test('missing spec: only the OpenAI-compatible base field is written', () => {
  const plan = mod.planModelRequest(null, {
    maxTokens: 100,
    maxOutputTokens: 0,
    temperature: 0.5,
  });
  assert.equal(plan.thinkingControl, 'unverified');
  assert.deepEqual(bodyOf(plan), { max_tokens: 100 });
});

test('max_tokens: clamp to [1, maxOutputTokens]; missing cap means no clamp', () => {
  assert.equal(mod.boundOutputTokens(12000, 4096), 4096);
  assert.equal(mod.boundOutputTokens(12000, 0), 12000);
  assert.equal(mod.boundOutputTokens(12000, -1), 12000);
  assert.equal(mod.boundOutputTokens(0.5, 0), 1);
  assert.equal(mod.boundOutputTokens(-5, 100), 1);
  assert.equal(mod.boundOutputTokens(100, 100), 100);
});

test('incomplete spec: required effort without a valid default returns null', () => {
  const base = mod.getModelSpec('deepseek', 'deepseek-flash');
  const incomplete = Object.assign({}, base, {
    request: Object.assign({}, base.request, {
      effort: {
        path: ['reasoning_effort'],
        levels: ['low'],
        defaultLevel: null,
        sendWhen: 'thinking_on',
        requiredWhen: 'thinking_on',
      },
    }),
  });
  const plan = mod.planModelRequest(incomplete, {
    maxTokens: 100,
    maxOutputTokens: 0,
    thinking: true,
  });
  assert.equal(plan, null, 'must reject instead of silently picking levels[0]');

  // requiredWhen='never' 时允许省略, 但仍不得取 levels[0]。
  const optional = Object.assign({}, incomplete, {
    request: Object.assign({}, incomplete.request, {
      effort: Object.assign({}, incomplete.request.effort, { requiredWhen: 'never' }),
    }),
  });
  const optionalPlan = mod.planModelRequest(optional, {
    maxTokens: 100,
    maxOutputTokens: 0,
    thinking: true,
  });
  assert.notEqual(optionalPlan, null);
  assert.equal(optionalPlan.effort, '');
  assert.equal(bodyOf(optionalPlan).reasoning_effort, undefined);
});

test('sampling: top_p only when support=yes and the condition holds', () => {
  const spec = mod.getModelSpec('deepseek', 'deepseek-flash');
  const off = mod.planModelRequest(spec, {
    maxTokens: 100,
    maxOutputTokens: 0,
    temperature: 0.2,
    topP: 0.9,
    thinking: false,
  });
  assert.equal(bodyOf(off).temperature, 0.2);
  assert.equal(bodyOf(off).top_p, 0.9);

  const on = mod.planModelRequest(spec, {
    maxTokens: 100,
    maxOutputTokens: 0,
    temperature: 0.2,
    topP: 0.9,
    thinking: true,
  });
  assert.equal(bodyOf(on).temperature, undefined);
  assert.equal(bodyOf(on).top_p, undefined);
});
