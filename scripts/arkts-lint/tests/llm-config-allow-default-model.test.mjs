// scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs
//
// Phase 1 模型适配回归:
//   - 删除 isAllowedDeepSeekModel 三个字符串相等白名单
//   - 删除 v3 / flash / r1 子串抛 NORMALIZE_KEYWORD_REJECTED 的路径
//   - normalizeModel 改调 model-resolver: catalog 规范 ID 直接可用, 旧别名归一化
//
// 背景: 旧守卫不在白名单里的含 'flash' 输入会被拒绝, 导致官方规范 ID
// `deepseek-flash` 无法保存/加载。本测试锁定"清单存在即允许 + alias resolver"。

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');

const read = (path) => readFileSync(resolve(root, path), 'utf8').replace(/\r\n/g, '\n');

const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');

async function loadResolver() {
  const catalog = read('common/src/main/ets/llm/model-catalog.ets');
  const resolver = read('common/src/main/ets/llm/model-resolver.ets')
    .replace(/import\s+(?:type\s+)?\{[^}]*\}\s+from\s+'\.\/model-catalog';/g, '');
  const js = ts.transpileModule(catalog + '\n' + resolver, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
  return await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}

const resolverModules = loadResolver();

test('normalizeModel delegates to catalog/alias resolver instead of a flash allowlist', () => {
  assert.doesNotMatch(
    llmConfig,
    /isAllowedDeepSeekModel/,
    'the old three-string DeepSeek allowlist must be deleted'
  );
  assert.doesNotMatch(
    llmConfig,
    /lower\.indexOf\(['"]flash['"]\)\s*>=\s*0/,
    'flash substring must no longer reject a model ID'
  );
  assert.doesNotMatch(
    llmConfig,
    /lower\.indexOf\(['"]v3['"]\)\s*>=\s*0/,
    'v3 substring must no longer reject a model ID'
  );
  assert.doesNotMatch(
    llmConfig,
    /lower\.indexOf\(['"]r1['"]\)\s*>=\s*0/,
    'r1 substring must no longer reject a model ID'
  );

  assert.match(llmConfig,
    /private\s+normalizeModelForVendor\s*\([\s\S]*?resolveModel\s*\(\s*vendorId\s*,\s*v\s*\)/,
    'normalizeModel must delegate to resolveModel(vendorId, v)');
  assert.match(llmConfig, /return\s+resolved\.canonicalId/,
    'normalizeModel must return the resolver canonical ID');
});

test('canonical deepseek-flash is accepted and both legacy aliases resolve to it', async () => {
  const mod = await resolverModules;

  const canonical = mod.resolveModel('deepseek', 'deepseek-flash');
  assert.equal(canonical.usable, true, 'deepseek-flash must be usable (not rejected)');
  assert.equal(canonical.canonicalId, 'deepseek-flash');
  assert.equal(canonical.reason, '');

  const aliases = ['deepseek-v4-flash', 'deepseek-v4-flash-vision-exp'];
  for (const alias of aliases) {
    const resolved = mod.resolveModel('deepseek', alias);
    assert.equal(resolved.canonicalId, 'deepseek-flash', alias + ' must resolve to deepseek-flash');
    assert.equal(resolved.degraded, false, alias + ' alias resolution is not a degradation');
    assert.equal(resolved.reason, 'ALIAS_RESOLVED:' + alias);
  }
});

test('normalizeEndpoint does not reject DEFAULT_ENDPOINT itself', () => {
  // normalizeEndpoint 应该没有 `lower === DEFAULT_ENDPOINT` 检查
  assert.doesNotMatch(
    llmConfig,
    /normalizeEndpoint[\s\S]*?lower\s*===\s*DEFAULT_ENDPOINT/,
    'normalizeEndpoint must not reject DEFAULT_ENDPOINT itself (potential P0 bug pattern)'
  );

  // siliconflow 必须仍然被拒
  assert.match(
    llmConfig,
    /lower\.indexOf\(['"]siliconflow['"]\)\s*>=\s*0/,
    'normalizeEndpoint must still reject siliconflow (ticket #9 intent)'
  );
});

test('PROVIDERS deepseek.defaultModel equals LlmConfig.DEFAULT_MODEL', () => {
  const providers = read('common/src/main/ets/llm/providers.ets');
  const firstProviderMatch = providers.match(
    /id:\s*['"]deepseek['"][\s\S]*?defaultModel:\s*['"]([^'"]+)['"]/
  );
  assert.ok(firstProviderMatch !== null, 'PROVIDERS deepseek.defaultModel must exist in providers.ets');
  const providerModel = firstProviderMatch[1];

  const defaultModelMatch = llmConfig.match(/DEFAULT_MODEL\s*=\s*['"]([^'"]+)['"]/);
  assert.ok(defaultModelMatch !== null, 'DEFAULT_MODEL constant must exist in LlmConfig.ets');
  const defaultModel = defaultModelMatch[1];

  assert.equal(
    providerModel,
    defaultModel,
    `PROVIDERS deepseek.defaultModel=${providerModel} must equal LlmConfig.DEFAULT_MODEL=${defaultModel}.`
  );
});
