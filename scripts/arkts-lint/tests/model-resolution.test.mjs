// scripts/arkts-lint/tests/model-resolution.test.mjs
//
// 模型规格分层测试 (2026-10-26):
//   - ModelListing 只描述"能发现的清单" (id/displayName/context/maxOutput/modalities)
//   - ModelSpec 逐型号描述"请求怎么构造" (thinking/effort/sampling/evidence)
//   - model-resolver 四条解析规则 + 准确型号 spec 查找
//   - ModelCapabilities 只读 spec 的 control, 区分 unverified 与 unsupported
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

test('catalog: DeepSeek canonical listings hold discovery fields only', async () => {
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
  assert.equal(flash.source, 'catalog');
  // Listing 不再承载请求能力: effort 是 ModelSpec 的事。
  assert.equal(flash.effort, undefined);
  assert.equal(flash.thinking, undefined);

  const pro = catalog.models.find((model) => model.id === 'deepseek-v4-pro');
  assert.ok(pro !== undefined, 'catalog must contain canonical deepseek-v4-pro');
  assert.equal(pro.displayName, 'DeepSeek-V4-Pro');
  assert.equal(pro.contextWindow, 1048576);
  assert.equal(pro.maxOutputTokens, 393216);
  assert.deepEqual(pro.inputModalities, ['text']);
  assert.equal(pro.effort, undefined);

  assert.equal(mod.getCatalogDefaultListing('deepseek').id, 'deepseek-v4-pro');
});

test('catalog: other vendors keep their existing listing defaults without invented capabilities', async () => {
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
    assert.deepEqual(catalog.models, [], providerId + ' must not invent listing data');
    assert.equal(mod.getCatalogDefaultListing(providerId), null);
  }
  assert.equal(mod.getProviderCatalog('custom-test'), null);
});

test('spec: DeepSeek toggle writes thinking.type and the documented effort levels', async () => {
  const mod = await modelModules;
  for (const modelId of ['deepseek-flash', 'deepseek-v4-pro']) {
    const spec = mod.getModelSpec('deepseek', modelId);
    assert.ok(spec !== null, modelId + ' spec must exist');
    assert.equal(spec.evidence.status, 'verified');
    assert.deepEqual(spec.request.outputTokenPath, ['max_tokens']);

    assert.equal(spec.request.thinking.control, 'toggle');
    assert.equal(spec.request.thinking.defaultEnabled, true, 'DeepSeek thinking defaults on');
    assert.deepEqual(spec.request.thinking.on, [
      { path: ['thinking', 'type'], value: 'enabled' },
    ]);
    assert.deepEqual(spec.request.thinking.off, [
      { path: ['thinking', 'type'], value: 'disabled' },
      { path: ['reasoning_effort'], value: 'none' },
    ]);

    assert.deepEqual(spec.request.effort.path, ['reasoning_effort']);
    assert.deepEqual(spec.request.effort.levels, ['low', 'high', 'max']);
    assert.equal(spec.request.effort.defaultLevel, 'high');
    assert.equal(spec.request.effort.requiredWhen, 'thinking_on');

    // 思考开启时 temperature/top_p 不生效。
    assert.equal(spec.request.sampling.temperature.support, 'yes');
    assert.equal(spec.request.sampling.temperature.when, 'thinking_off');
  }
});

test('spec: only tongyi/qwen3-max stays unverified instead of being called unsupported', async () => {
  const mod = await modelModules;
  const spec = mod.getModelSpec('tongyi', 'qwen3-max');
  assert.ok(spec !== null, 'tongyi/qwen3-max spec must exist');
  assert.equal(spec.evidence.status, 'unverified');
  assert.equal(spec.request.thinking.control, 'unverified');
  assert.deepEqual(spec.request.thinking.on, []);
  assert.deepEqual(spec.request.thinking.off, []);
  assert.equal(spec.request.effort, null);
  assert.equal(spec.request.sampling.temperature.support, 'unknown');
  assert.equal(mod.getModelSpec('deepseek', 'deepseek-v4-unknown'), null);
});

test('spec: GLM direct follows the documented always-on / toggle matrix', async () => {
  const mod = await modelModules;
  for (const modelId of ['glm-5.3', 'glm-5.3-flash']) {
    const spec = mod.getModelSpec('glm', modelId);
    assert.ok(spec !== null, modelId + ' spec must exist');
    assert.equal(spec.evidence.status, 'verified');
    assert.equal(spec.request.thinking.control, 'always_on', modelId + ' cannot disable thinking');
    assert.equal(spec.request.thinking.defaultEnabled, true);
    assert.deepEqual(spec.request.thinking.on, [], 'always_on must not write an on field');
    assert.deepEqual(spec.request.thinking.off, [], 'always_on must never write a close field');
    assert.equal(spec.request.effort, null, 'GLM has no effort parameter');
  }
  for (const modelId of ['glm-5', 'glm-5.1', 'glm-5.2', 'glm-4.7']) {
    const spec = mod.getModelSpec('glm', modelId);
    assert.ok(spec !== null, modelId + ' spec must exist');
    assert.equal(spec.evidence.status, 'verified');
    assert.equal(spec.request.thinking.control, 'toggle');
    assert.equal(spec.request.thinking.defaultEnabled, true, modelId + ' defaults to thinking on');
    assert.deepEqual(spec.request.thinking.on, [
      { path: ['thinking', 'type'], value: 'enabled' },
    ]);
    assert.deepEqual(spec.request.thinking.off, [
      { path: ['thinking', 'type'], value: 'disabled' },
    ]);
    assert.equal(spec.request.effort, null);
  }
});

test('spec: Kimi splits k2.6 / k2.7-code / k3 by documented thinking behaviour', async () => {
  const mod = await modelModules;
  const k26 = mod.getModelSpec('kimi', 'kimi-k2.6');
  assert.ok(k26 !== null, 'kimi-k2.6 spec must exist');
  assert.equal(k26.request.thinking.control, 'toggle');
  assert.equal(k26.request.thinking.defaultEnabled, true);
  assert.deepEqual(k26.request.thinking.on, [
    { path: ['thinking', 'type'], value: 'enabled' },
  ]);
  assert.deepEqual(k26.request.thinking.off, [
    { path: ['thinking', 'type'], value: 'disabled' },
  ]);
  assert.equal(k26.request.effort, null, 'k2.6 does not support reasoning_effort');

  for (const modelId of ['kimi-k2.7-code', 'kimi-k2.7-code-highspeed']) {
    const spec = mod.getModelSpec('kimi', modelId);
    assert.ok(spec !== null, modelId + ' spec must exist');
    assert.equal(spec.request.thinking.control, 'always_on');
    assert.deepEqual(spec.request.thinking.on, []);
    assert.deepEqual(spec.request.thinking.off, [], 'disabled is an error on k2.7-code');
    assert.equal(spec.request.effort, null);
  }

  const k3 = mod.getModelSpec('kimi', 'kimi-k3');
  assert.ok(k3 !== null, 'kimi-k3 spec must exist');
  assert.equal(k3.request.thinking.control, 'always_on');
  assert.deepEqual(k3.request.thinking.on, [], 'k3 must not send a thinking field at all');
  assert.deepEqual(k3.request.thinking.off, []);
  assert.deepEqual(k3.request.effort.path, ['reasoning_effort']);
  assert.deepEqual(k3.request.effort.levels, ['low', 'high', 'max']);
  assert.equal(k3.request.effort.defaultLevel, 'max');
});

test('spec: Kimi fixed temperature/top_p use support=no (must be omitted)', async () => {
  const mod = await modelModules;
  for (const modelId of ['kimi-k2.6', 'kimi-k2.7-code', 'kimi-k2.7-code-highspeed', 'kimi-k3']) {
    const spec = mod.getModelSpec('kimi', modelId);
    assert.ok(spec !== null, modelId + ' spec must exist');
    assert.equal(spec.request.sampling.temperature.support, 'no');
    assert.equal(spec.request.sampling.topP.support, 'no');
    assert.equal(spec.request.sampling.temperature.when, 'never');
  }
});

test('spec: Doubao toggles thinking with partial evidence and no effort', async () => {
  const mod = await modelModules;
  const spec = mod.getModelSpec('doubao', 'doubao-seed-1.6');
  assert.ok(spec !== null, 'doubao-seed-1.6 spec must exist');
  assert.equal(spec.evidence.status, 'partial', 'documented fields verified, default value not');
  assert.equal(spec.request.thinking.control, 'toggle');
  assert.equal(spec.request.thinking.defaultEnabled, true);
  assert.deepEqual(spec.request.thinking.on, [
    { path: ['thinking', 'type'], value: 'enabled' },
  ]);
  assert.deepEqual(spec.request.thinking.off, [
    { path: ['thinking', 'type'], value: 'disabled' },
  ]);
  assert.equal(spec.request.effort, null);
  assert.equal(spec.request.sampling.temperature.support, 'unknown');
});

test('spec: provider-scoped — same modelId can differ between direct and Bailian', async () => {
  const mod = await modelModules;
  // kimi-k3 直连有 reasoning_effort; 百炼上的同名型号没有该字段。
  const direct = mod.getModelSpec('kimi', 'kimi-k3');
  const viaBailian = mod.getModelSpec('tongyi', 'kimi-k3');
  assert.equal(direct.request.thinking.control, 'always_on');
  assert.equal(viaBailian.request.thinking.control, 'always_on');
  assert.equal(direct.request.effort.defaultLevel, 'max');
  assert.equal(viaBailian.request.effort, null, 'Bailian does not expose reasoning_effort');

  const qwenPlus = mod.getModelSpec('tongyi', 'qwen3.6-plus');
  assert.equal(qwenPlus.request.thinking.control, 'toggle');
  assert.deepEqual(qwenPlus.request.thinking.on, [{ path: ['enable_thinking'], value: true }]);
  assert.deepEqual(qwenPlus.request.thinking.off, [{ path: ['enable_thinking'], value: false }]);
  assert.equal(qwenPlus.request.effort, null, 'Qwen must not inherit reasoning_effort');
});

test('resolver rule 1: empty input returns provider catalog default with EMPTY_REQUEST', async () => {
  const mod = await modelModules;
  const resolved = mod.resolveModel('deepseek', '   ');
  assert.equal(resolved.requestedId, '');
  assert.equal(resolved.canonicalId, 'deepseek-v4-pro');
  assert.equal(resolved.listing.id, 'deepseek-v4-pro');
  assert.equal(resolved.spec.id, 'deepseek-v4-pro');
  assert.equal(resolved.usable, true);
  assert.equal(resolved.degraded, false);
  assert.equal(resolved.reason, 'EMPTY_REQUEST');
});

test('resolver rule 2: a catalog ID is used as-is and carries its spec', async () => {
  const mod = await modelModules;
  const resolved = mod.resolveModel('deepseek', 'deepseek-flash');
  assert.equal(resolved.requestedId, 'deepseek-flash');
  assert.equal(resolved.canonicalId, 'deepseek-flash');
  assert.equal(resolved.listing.id, 'deepseek-flash');
  assert.equal(resolved.spec.id, 'deepseek-flash');
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
    assert.equal(resolved.spec.id, 'deepseek-flash');
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
  assert.equal(unknown.spec, null);
  assert.equal(unknown.usable, false);
  assert.equal(unknown.degraded, false);
  assert.equal(unknown.reason, 'MODEL_ID_UNRESOLVED');

  // catalog 没有条目的其它 vendor 也不能被静默换成 DeepSeek 默认。
  const otherVendor = mod.resolveModel('tongyi', 'qwen3-max');
  assert.equal(otherVendor.canonicalId, 'qwen3-max');
  assert.equal(otherVendor.usable, false);
  assert.equal(otherVendor.reason, 'MODEL_ID_UNRESOLVED');
  // 但规格仍按准确型号查到 (unverified), 不冒充 unsupported。
  assert.equal(otherVendor.spec.request.thinking.control, 'unverified');
});

test('capabilities: thinking comes from spec, image comes from listing', async () => {
  const mod = await modelModules;
  const catalog = mod.getProviderCatalog('deepseek');
  const flash = catalog.models.find((model) => model.id === 'deepseek-flash');
  const pro = catalog.models.find((model) => model.id === 'deepseek-v4-pro');
  const flashSpec = mod.getModelSpec('deepseek', 'deepseek-flash');
  const proSpec = mod.getModelSpec('deepseek', 'deepseek-v4-pro');

  const flashCapability = mod.resolveCapabilities(flash, flashSpec);
  assert.equal(flashCapability.thinking, 'toggle');
  assert.deepEqual(flashCapability.efforts, ['low', 'high', 'max']);
  assert.equal(flashCapability.defaultEffort, 'high');
  assert.equal(flashCapability.defaultThinkingEnabled, true);
  assert.equal(flashCapability.supportsImage, true);

  const proCapability = mod.resolveCapabilities(pro, proSpec);
  assert.equal(proCapability.thinking, 'toggle');
  assert.deepEqual(proCapability.efforts, ['low', 'high', 'max']);
  assert.equal(proCapability.defaultEffort, 'high');
  assert.equal(proCapability.supportsImage, false);

  // 没有规格 ≠ 不支持; 必须保留 unverified。
  const unknownCapability = mod.resolveCapabilities(null, null);
  assert.equal(unknownCapability.thinking, 'unverified');
  assert.deepEqual(unknownCapability.efforts, []);
  assert.equal(unknownCapability.defaultEffort, '');
  assert.equal(unknownCapability.supportsImage, false);

  const alwaysOnSpec = mod.getModelSpec('tongyi', 'glm-5.3');
  const alwaysOnCapability = mod.resolveCapabilities(null, alwaysOnSpec);
  assert.equal(alwaysOnCapability.thinking, 'always_on');
  assert.equal(alwaysOnCapability.defaultThinkingEnabled, true);
  assert.deepEqual(alwaysOnCapability.efforts, [], 'no verified effort levels for Bailian GLM');

  assert.equal(mod.supportsImageInput(flash), true);
  assert.equal(mod.supportsImageInput(pro), false);
  assert.equal(mod.supportsImageInput(null), false);
});
