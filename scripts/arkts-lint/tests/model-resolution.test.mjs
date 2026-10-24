// scripts/arkts-lint/tests/model-resolution.test.mjs
//
// Phase 1 模型适配分层的纯逻辑测试:
//   - model-catalog.ets 的两个 DeepSeek 规范条目能力字段 (官方 /models 清单)
//   - model-resolver.ets 的四条解析规则 (空输入 / catalog 命中 / 别名 / 未知)
//   - ModelCapabilities.resolveCapabilities 只读 listing, 未知条目保守处理
//
// 这些 .ets 文件不依赖 HarmonyOS Kit, 因此可以直接 transpile 后执行真实逻辑,
// 而不是用正则断言源码文本。

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');

async function loadModelModules() {
  const catalog = readFileSync(resolve(root, 'common/src/main/ets/llm/model-catalog.ets'), 'utf8');
  const resolver = readFileSync(resolve(root, 'common/src/main/ets/llm/model-resolver.ets'), 'utf8')
    .replace(/import\s+(?:type\s+)?\{[^}]*\}\s+from\s+'\.\/model-catalog';/g, '');
  const capabilities = readFileSync(resolve(root, 'common/src/main/ets/llm/ModelCapabilities.ets'), 'utf8')
    .replace(/import\s+(?:type\s+)?\{[^}]*\}\s+from\s+'\.\/model-resolver';/g, '')
    .replace(/import\s+(?:type\s+)?\{[^}]*\}\s+from\s+'\.\/model-catalog';/g, '');
  const js = ts.transpileModule(catalog + '\n' + resolver + '\n' + capabilities, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ES2022,
    },
  }).outputText;
  return await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}

const modelModules = loadModelModules();

test('catalog: DeepSeek canonical listings match the official /models payload', async () => {
  const mod = await modelModules;
  const catalog = mod.getProviderCatalog('deepseek');
  assert.ok(catalog !== null, 'deepseek catalog must exist');
  assert.equal(catalog.defaultModelId, 'deepseek-v4-pro');
  assert.equal(catalog.models.length, 2);

  const flash = catalog.models.find((model) => model.id === 'deepseek-flash');
  assert.ok(flash !== undefined, 'catalog must contain canonical deepseek-flash');
  assert.equal(flash.displayName, 'DeepSeek-V4.1-Flash');
  assert.equal(flash.providerId, 'deepseek');
  assert.equal(flash.contextWindow, 1048576);
  assert.equal(flash.maxOutputTokens, 393216);
  assert.deepEqual(flash.inputModalities, ['text', 'image']);
  assert.deepEqual(flash.effort.supportedLevels, ['low', 'high', 'max']);
  assert.equal(flash.effort.defaultLevel, 'high');
  assert.equal(flash.source, 'catalog');

  const pro = catalog.models.find((model) => model.id === 'deepseek-v4-pro');
  assert.ok(pro !== undefined, 'catalog must contain canonical deepseek-v4-pro');
  assert.equal(pro.displayName, 'DeepSeek-V4-Pro');
  assert.equal(pro.contextWindow, 1048576);
  assert.equal(pro.maxOutputTokens, 393216);
  assert.deepEqual(pro.inputModalities, ['text']);
  assert.deepEqual(pro.effort.supportedLevels, ['low', 'high', 'max']);
  assert.equal(pro.effort.defaultLevel, 'high');

  assert.equal(mod.getCatalogDefaultListing('deepseek').id, 'deepseek-v4-pro');
});

test('catalog: other vendors keep their existing defaults without invented capabilities', async () => {
  const mod = await modelModules;
  const expected = [
    ['tongyi', 'qwen3-max'],
    ['glm', 'glm-5.3'],
    ['kimi', 'kimi-k2.6'],
    ['doubao', 'doubao-seed-1.6'],
  ];
  for (const [providerId, defaultModelId] of expected) {
    const catalog = mod.getProviderCatalog(providerId);
    assert.ok(catalog !== null, providerId + ' catalog must exist');
    assert.equal(catalog.defaultModelId, defaultModelId);
    assert.deepEqual(catalog.models, [], providerId + ' must not invent capability data');
    assert.equal(mod.getCatalogDefaultListing(providerId), null);
  }
  assert.equal(mod.getProviderCatalog('custom-test'), null);
});

test('resolver rule 1: empty input returns provider catalog default with EMPTY_REQUEST', async () => {
  const mod = await modelModules;
  const resolved = mod.resolveModel('deepseek', '   ');
  assert.equal(resolved.requestedId, '');
  assert.equal(resolved.canonicalId, 'deepseek-v4-pro');
  assert.equal(resolved.listing.id, 'deepseek-v4-pro');
  assert.equal(resolved.usable, true);
  assert.equal(resolved.degraded, false);
  assert.equal(resolved.reason, 'EMPTY_REQUEST');
});

test('resolver rule 2: a catalog ID is used as-is and stays usable', async () => {
  const mod = await modelModules;
  const resolved = mod.resolveModel('deepseek', 'deepseek-flash');
  assert.equal(resolved.requestedId, 'deepseek-flash');
  assert.equal(resolved.canonicalId, 'deepseek-flash');
  assert.equal(resolved.listing.id, 'deepseek-flash');
  assert.equal(resolved.usable, true);
  assert.equal(resolved.degraded, false);
  assert.equal(resolved.reason, '');
});

test('resolver rule 3: both legacy flash aliases normalize to canonical deepseek-flash', async () => {
  const mod = await modelModules;
  const aliases = ['deepseek-v4-flash', 'deepseek-v4-flash-vision-exp'];
  for (const alias of aliases) {
    const resolved = mod.resolveModel('deepseek', alias);
    assert.equal(resolved.requestedId, alias);
    assert.equal(resolved.canonicalId, 'deepseek-flash');
    assert.equal(resolved.listing.id, 'deepseek-flash');
    assert.equal(resolved.usable, true);
    assert.equal(resolved.degraded, false);
    assert.equal(resolved.reason, 'ALIAS_RESOLVED:' + alias);
  }
});

test('resolver rule 4: unknown IDs are preserved with MODEL_ID_UNRESOLVED (no silent swap)', async () => {
  const mod = await modelModules;
  const unknown = mod.resolveModel('deepseek', 'deepseek-v4-unknown');
  assert.equal(unknown.requestedId, 'deepseek-v4-unknown');
  assert.equal(unknown.canonicalId, 'deepseek-v4-unknown');
  assert.equal(unknown.listing, null);
  assert.equal(unknown.usable, false);
  assert.equal(unknown.degraded, false);
  assert.equal(unknown.reason, 'MODEL_ID_UNRESOLVED');

  // catalog 没有条目的其它 vendor 也不能被静默换成 DeepSeek 默认。
  const otherVendor = mod.resolveModel('tongyi', 'qwen3-max');
  assert.equal(otherVendor.canonicalId, 'qwen3-max');
  assert.equal(otherVendor.usable, false);
  assert.equal(otherVendor.reason, 'MODEL_ID_UNRESOLVED');
});

test('capabilities: thinking and image are derived from listing fields only', async () => {
  const mod = await modelModules;
  const catalog = mod.getProviderCatalog('deepseek');
  const flash = catalog.models.find((model) => model.id === 'deepseek-flash');
  const pro = catalog.models.find((model) => model.id === 'deepseek-v4-pro');

  const flashCapability = mod.resolveCapabilities(flash);
  assert.equal(flashCapability.thinking, 'toggle');
  assert.deepEqual(flashCapability.efforts, ['low', 'high', 'max']);
  assert.equal(flashCapability.defaultEffort, 'high');
  assert.equal(flashCapability.supportsImage, true);

  const proCapability = mod.resolveCapabilities(pro);
  assert.equal(proCapability.thinking, 'toggle');
  assert.deepEqual(proCapability.efforts, ['low', 'high', 'max']);
  assert.equal(proCapability.defaultEffort, 'high');
  assert.equal(proCapability.supportsImage, false);

  const unknownCapability = mod.resolveCapabilities(null);
  assert.equal(unknownCapability.thinking, 'unsupported');
  assert.deepEqual(unknownCapability.efforts, []);
  assert.equal(unknownCapability.defaultEffort, '');
  assert.equal(unknownCapability.supportsImage, false);

  assert.equal(mod.supportsImageInput(flash), true);
  assert.equal(mod.supportsImageInput(pro), false);
  assert.equal(mod.supportsImageInput(null), false);
});
