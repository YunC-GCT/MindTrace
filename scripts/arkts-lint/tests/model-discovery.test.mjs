// scripts/arkts-lint/tests/model-discovery.test.mjs
//
// /models 解码回归测试 (Phase 1 模型适配分层):
//   - 官方 DeepSeek 响应体的真实形状 (2026-10-25 抓取, key 已脱敏):
//       data[].id / name / context_window / max_output_tokens / input_modalities
//   - 网关 (OpenRouter 风格) 形状: context_length + limit.context + top_provider.max_completion_tokens
//   - 回归点: limit.context 是上下文窗口, 曾经被错映射成 max_output_tokens
//   - 2026-10-26: discovery 只产出清单, 不再把 /models 的 effort 当请求能力
//
// 这个模块只 import HarmonyOS Kit 用于真正发网络; 解析函数是纯逻辑,
// 因此剥掉 kit import 后可以直接 transpile 执行真实代码。

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');

const OFFICIAL_PAYLOAD = {
  object: 'list',
  data: [
    {
      id: 'deepseek-flash',
      object: 'model',
      owned_by: 'deepseek',
      name: 'DeepSeek-V4.1-Flash',
      context_window: 1048576,
      max_output_tokens: 393216,
      input_modalities: ['text', 'image'],
      output_modalities: ['text'],
      effort: { supported_levels: ['low', 'high', 'max'], default_level: 'high' },
    },
    {
      id: 'deepseek-v4-pro',
      object: 'model',
      owned_by: 'deepseek',
      name: 'DeepSeek-V4-Pro',
      context_window: 1048576,
      max_output_tokens: 393216,
      input_modalities: ['text'],
      output_modalities: ['text'],
      effort: { supported_levels: ['low', 'high', 'max'], default_level: 'high' },
    },
  ],
};

async function loadDiscovery() {
  const catalog = readFileSync(resolve(root, 'common/src/main/ets/llm/model-catalog.ets'), 'utf8');
  const discovery = readFileSync(resolve(root, 'common/src/main/ets/llm/model-discovery.ets'), 'utf8')
    .replace(/^import .*@kit\.NetworkKit.*$/gm, '')
    .replace(/^import .*@kit\.ArkTS.*$/gm, '')
    .replace(/^import .*@kit\.BasicServicesKit.*$/gm, '')
    .replace(/^import .*'\.\/model-catalog'.*$/gm, '');
  const js = ts.transpileModule(catalog + '\n' + discovery, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ES2022,
    },
  }).outputText;
  const url = 'data:text/javascript;base64,' + Buffer.from(js, 'utf8').toString('base64');
  return await import(url);
}

const discovery = await loadDiscovery();

function listingOf(result, id) {
  return result.models.find((m) => m.id === id);
}

test('decodes the official DeepSeek /models payload', () => {
  const result = discovery.parseDiscoveryPayload('deepseek', JSON.stringify(OFFICIAL_PAYLOAD));
  assert.equal(result.ok, true);
  assert.equal(result.models.length, 2);

  const flash = listingOf(result, 'deepseek-flash');
  assert.equal(flash.displayName, 'DeepSeek-V4.1-Flash');
  assert.equal(flash.contextWindow, 1048576);
  assert.equal(flash.maxOutputTokens, 393216);
  assert.deepEqual(flash.inputModalities, ['text', 'image']);
  assert.equal(flash.source, 'discovery');
  // 发现结果不能自动变成请求能力: effort / thinking 不属于 Listing。
  assert.equal(flash.effort, undefined);
  assert.equal(flash.thinking, undefined);

  const pro = listingOf(result, 'deepseek-v4-pro');
  assert.deepEqual(pro.inputModalities, ['text']);
  assert.equal(pro.contextWindow, 1048576);
});

test('limit.context is the context window, not the output budget (regression)', () => {
  const payload = {
    data: [
      {
        id: 'vendor/model-x',
        name: 'Model X',
        context_length: 131072,
        limit: { context: 131072, output: 8192 },
      },
    ],
  };
  const result = discovery.parseDiscoveryPayload('custom-1', JSON.stringify(payload));
  assert.equal(result.ok, true);
  const listing = listingOf(result, 'vendor/model-x');
  assert.equal(listing.contextWindow, 131072);
  assert.equal(listing.maxOutputTokens, 8192);
});

test('falls back to top_provider.max_completion_tokens for output cap', () => {
  const payload = {
    data: [{ id: 'gateway/model-y', top_provider: { max_completion_tokens: 4096 } }],
  };
  const result = discovery.parseDiscoveryPayload('custom-2', JSON.stringify(payload));
  const listing = listingOf(result, 'gateway/model-y');
  assert.equal(listing.maxOutputTokens, 4096);
  assert.equal(listing.contextWindow, 0);
  assert.deepEqual(listing.inputModalities, []);
  assert.equal(listing.effort, undefined);
});

test('accepts a gateway models{} map', () => {
  const payload = { models: { 'vendor/model-z': 'Model Z', 'vendor/model-w': { id: 'vendor/model-w' } } };
  const result = discovery.parseDiscoveryPayload('custom-3', JSON.stringify(payload));
  assert.equal(result.ok, true);
  assert.equal(result.models.length, 2);
  assert.equal(listingOf(result, 'vendor/model-z').displayName, 'Model Z');
  assert.equal(listingOf(result, 'vendor/model-w').displayName, 'vendor/model-w');
});

test('reports parse failures instead of inventing models', () => {
  const broken = discovery.parseDiscoveryPayload('deepseek', 'not json');
  assert.equal(broken.ok, false);
  assert.equal(broken.errorCode, 'DISCOVERY_PARSE_FAILED');
  assert.equal(broken.models.length, 0);

  const empty = discovery.parseDiscoveryPayload('deepseek', JSON.stringify({ data: [] }));
  assert.equal(empty.ok, false);
  assert.equal(empty.errorCode, 'DISCOVERY_EMPTY_LIST');
});
