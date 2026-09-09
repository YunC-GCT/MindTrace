// scripts/arkts-lint/tests/api-key-vault.test.mjs
//
// PR1 测试套件: API key 凭据升级到 @kit.AssetStoreKit (TEE + AES256-GCM)
// 兼容读取: AssetStoreKit 优先,空时 fallback Preferences 旧 key 并自动写回。
//
// 一手信源:
//   docs/specs/016-llm-settings-redesign.md §公共接口变更 (ApiKeyVault)
//   docs/adr/0014-asset-store-kit-migration.md
//   docs/agents/security.md (凭据存储描述,待 PR1 同步更新)
//   docs/agents/tickets/llm-settings/pr1-asset-store-kit-upgrade.md

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');

const read = (p) => readFileSync(resolve(root, p), 'utf8');

// 文件存在性
test('ApiKeyVault.ets exists', () => {
  assert.ok(
    existsSync(resolve(root, 'common/src/main/ets/security/ApiKeyVault.ets')),
    'ApiKeyVault.ets must exist at common/src/main/ets/security/'
  );
});

const apiKeyVault = read('common/src/main/ets/security/ApiKeyVault.ets');

// 测试 1: 导入 @kit.AssetStoreKit
test('ApiKeyVault imports @kit.AssetStoreKit as asset', () => {
  assert.match(
    apiKeyVault,
    /import\s*\{\s*asset\s*\}\s*from\s*['"]@kit\.AssetStoreKit['"]/,
    'ApiKeyVault must import { asset } from @kit.AssetStoreKit'
  );
});

// 测试 2: ASSET_NAME 常量定义
test('ApiKeyVault defines ASSET_NAME = "llm_api_key"', () => {
  assert.match(
    apiKeyVault,
    /(?:const|let|var)\s+ASSET_NAME\s*:\s*string\s*=\s*['"]llm_api_key['"]/,
    'ApiKeyVault must define ASSET_NAME = "llm_api_key"'
  );
});

// 测试 3: ApiKeyVault 类导出(必须 export class ApiKeyVault)
test('ApiKeyVault exports class ApiKeyVault', () => {
  assert.match(
    apiKeyVault,
    /export\s+class\s+ApiKeyVault/,
    'ApiKeyVault must export class ApiKeyVault'
  );
});

// 测试 4: get 方法存在 + 优先 AssetStoreKit (写路径)
test('ApiKeyVault.get() prefers AssetStoreKit (write path)', () => {
  assert.match(
    apiKeyVault,
    /public\s+static\s+async\s+get\s*\(\s*\)\s*:\s*Promise\s*<\s*string\s*\|\s*null\s*>/,
    'ApiKeyVault.get() must be public static async (): Promise<string | null>'
  );
  assert.match(
    apiKeyVault,
    /asset\.query\s*\(\s*\w+\s*\)/,
    'ApiKeyVault.get() must call asset.query(<AssetMap>)'
  );
  assert.match(
    apiKeyVault,
    /asset\.Tag\.ALIAS/,
    'ApiKeyVault.get() must use asset.Tag.ALIAS for query'
  );
  assert.match(
    apiKeyVault,
    /results\[0\]/,
    'ApiKeyVault.get() must read results[0] (first match)'
  );
});

// 测试 4b: get 的 query 必须设 RETURN_TYPE = ALL(SDK 默认 ATTRIBUTES 不返回明文)
// 不设这个,query 结果不含 SECRET,get(SECRET) 返回 undefined
// 来源: AssetStoreKit query 文档(ost.51cto.com/posts/52405 的 queryPlaintext 示例)
test('ApiKeyVault.get() query must set RETURN_TYPE = ALL to retrieve plaintext', () => {
  // get() 内调 asset.query 的 queryMap 必须设 asset.Tag.RETURN_TYPE
  // 找 get() 函数体内的 query 调用
  const getFnBody = apiKeyVault.match(/public\s+static\s+async\s+get\s*\([\s\S]*?return\s+legacy/);
  assert.ok(getFnBody !== null, 'get() function body must exist');
  const getBody = getFnBody[0];

  // query 调用的 queryMap 必须设 RETURN_TYPE
  // 简化验证: get() 函数体内必须出现 asset.Tag.RETURN_TYPE
  assert.match(
    getBody,
    /asset\.Tag\.RETURN_TYPE/,
    'ApiKeyVault.get() query must set asset.Tag.RETURN_TYPE (SDK default is ATTRIBUTES which does not return SECRET)'
  );

  // 而且必须设为 ALL(才能拿明文)
  assert.match(
    getBody,
    /asset\.ReturnType\.ALL/,
    'ApiKeyVault.get() must use asset.ReturnType.ALL to retrieve plaintext (vs ATTRIBUTES only)'
  );
});

// 测试 5: 兼容读取 — fallback 到 Preferences
test('ApiKeyVault.get() falls back to Preferences on AssetStoreKit empty', () => {
  // 必须有 fallback 路径(读 preferences mindtrace_llm api_key)
  // 接受字面 'mindtrace_llm' 或常量引用(如 LEGACY_STORE_NAME 常量);
  // 第一个参数接受任意变量或函数调用(如 getContext())
  assert.match(
    apiKeyVault,
    /preferences\.getPreferences\s*\(\s*[\w()]+\s*,\s*(?:['"]mindtrace_llm['"]|LEGACY_STORE_NAME)\s*\)/,
    'ApiKeyVault.get() must fallback to preferences.getPreferences(ctx, "mindtrace_llm")'
  );
  assert.match(
    apiKeyVault,
    /['"]api_key['"]/,
    'ApiKeyVault fallback must read preferences key "api_key"'
  );
});

// 测试 6: 兼容读取 — fallback 后自动写回 AssetStoreKit(迁移透明)
test('ApiKeyVault.get() auto-writes legacy key back to AssetStoreKit', () => {
  // 找到 fallback 后的 put 调用(static method 调用形如 ApiKeyVault.put(...))
  assert.match(
    apiKeyVault,
    /ApiKeyVault\.put\s*\(\s*\w+\s*\)/,
    'ApiKeyVault.get() must call ApiKeyVault.put(legacyKey) after fallback to migrate'
  );
});

// 测试 7: put 方法存在 + 写入 AssetStoreKit
test('ApiKeyVault.put() writes to AssetStoreKit', () => {
  assert.match(
    apiKeyVault,
    /public\s+static\s+async\s+put\s*\(\s*\w+\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'ApiKeyVault.put() must exist with (key: string) -> Promise<void>'
  );
  assert.match(
    apiKeyVault,
    /asset\.add\s*\(/,
    'ApiKeyVault.put() must call asset.add(...)'
  );
});

// 测试 7b: put 必须支持"已存在则 update"(避免 24000003)
test('ApiKeyVault.put() falls back to update on "already exists" error', () => {
  // 关键:catch 24000003 后必须调用 asset.update 而不是抛错
  assert.match(
    apiKeyVault,
    /24000003/,
    'ApiKeyVault.put() must catch error code 24000003 (asset already exists)'
  );
  assert.match(
    apiKeyVault,
    /asset\.update\s*\(/,
    'ApiKeyVault.put() must call asset.update(...) on 24000003 fallback'
  );
});

// 测试 7c: update fallback 的 attributesToUpdate 必须独立(不含 ALIAS/ACCESSIBILITY)
// SDK 约束: asset.update(query, attrsToUpdate) 的 attrsToUpdate 只能含 SECRET + DATA_LABEL_*
// ALIAS immutable, ACCESSIBILITY 不在 update attrsToUpdate 列表中
// 来源: @ohos.security.asset.d.ts + seaxiang.com/blog/Xo8bKb
test('ApiKeyVault.put() update fallback uses SDK-valid attributesToUpdate (no ALIAS / no ACCESSIBILITY)', () => {
  // 找真正的 asset.update(<var>, <var>) 函数调用(非注释)
  // regex 匹配 `asset.update(变量, 变量)` 形式
  const updateCallRegex = /asset\.update\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)/g;
  const matches = [];
  let m;
  while ((m = updateCallRegex.exec(apiKeyVault)) !== null) {
    matches.push(m);
  }
  assert.ok(matches.length >= 1, 'at least one asset.update(<var>, <var>) call must exist');
  // 取最后一个 update 调用(put() 内的)
  const lastUpdate = matches[matches.length - 1];
  const updateIdx = lastUpdate.index;
  const attrsVarName = lastUpdate[2];  // 第二个参数名 = attributesToUpdate

  // 从 update 调用向前找最近的 `attrsVarName =` 声明
  const declRegex = new RegExp(`(?:const|let|var)\\s+${attrsVarName}\\s*[:=]`, 'g');
  const declMatch = declRegex.exec(apiKeyVault);
  assert.ok(declMatch !== null, `variable ${attrsVarName} must be declared before asset.update call`);

  // 抓 attrsVarName 声明到 asset.update 调用的代码(attrsToUpdate 构造)
  const attrsConstruction = apiKeyVault.substring(declMatch.index, updateIdx);

  // 验证 attrsToUpdate 不包含 ALIAS/ACCESSIBILITY
  assert.doesNotMatch(
    attrsConstruction,
    /asset\.Tag\.ALIAS/,
    `attributesToUpdate (${attrsVarName}) must NOT set asset.Tag.ALIAS (SDK: ALIAS is immutable in update)`
  );
  assert.doesNotMatch(
    attrsConstruction,
    /asset\.Tag\.ACCESSIBILITY/,
    `attributesToUpdate (${attrsVarName}) must NOT set asset.Tag.ACCESSIBILITY (SDK: not in update attrsToUpdate list)`
  );

  // attrsToUpdate 必须至少含 SECRET(SDK 实际允许但语义需要)
  assert.match(
    attrsConstruction,
    /asset\.Tag\.SECRET/,
    `attributesToUpdate (${attrsVarName}) must set asset.Tag.SECRET (这是 update 的实际目的)`
  );
});

// 测试 8: clear 方法存在
test('ApiKeyVault.clear() removes AssetStoreKit entry', () => {
  assert.match(
    apiKeyVault,
    /public\s+static\s+async\s+clear\s*\(\s*\)\s*:\s*Promise\s*<\s*void\s*>/,
    'ApiKeyVault.clear() must exist with () -> Promise<void>'
  );
  assert.match(
    apiKeyVault,
    /asset\.remove\s*\(/,
    'ApiKeyVault.clear() must call asset.remove(...)'
  );
});

// 测试 9: accessibility 兼容性 — API 9 fallback
// (API 12+ 才支持 DEVICE_UNLOCKED; API 9 必须能运行)
test('ApiKeyVault.put() accessibility is API 9 compatible', () => {
  // 不应该强制 DEVICE_UNLOCKED(需要 API 12+);可以无 accessibility 或 DEVICE_PASSED
  const accessibilityMatch = apiKeyVault.match(/accessibility\s*:\s*asset\.Accessibility\.(\w+)/);
  if (accessibilityMatch !== null) {
    const kind = accessibilityMatch[1];
    assert.ok(
      kind !== 'DEVICE_UNLOCKED',
      `accessibility kind ${ kind } requires API 12+; current API is 9. Use no accessibility or DEVICE_PASSED.`
    );
  }
  // 如果无 accessibility 字段,默认行为 OK
});

// === LlmConfig 委托 ===

const llmConfig = read('common/src/main/ets/llm/LlmConfig.ets');

// 测试 10: LlmConfig.getApiKey() 委托 ApiKeyVault
test('LlmConfig.getApiKey() delegates to ApiKeyVault.get()', () => {
  const getApiKeyMatch = llmConfig.match(
    /public\s+async\s+getApiKey\s*\(\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*string\s*\|\s*null\s*>\s*\{([\s\S]*?)\n\s*\}\n\s*\n\s*\/\//m
  );
  assert.ok(getApiKeyMatch !== null, 'LlmConfig.getApiKey() method not found');
  assert.match(
    getApiKeyMatch[1],
    /ApiKeyVault\.get\s*\(\s*\)/,
    'LlmConfig.getApiKey() must call ApiKeyVault.get()'
  );
});

// 测试 11: LlmConfig.setApiKey() 委托 ApiKeyVault.put()
test('LlmConfig.setApiKey() delegates to ApiKeyVault.put()', () => {
  // 用 lazy match 跨多行捕获整个方法 body(含嵌套 {})
  assert.match(
    llmConfig,
    /public\s+async\s+setApiKey\s*\(\s*\w+\s*:\s*string\s*,\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{[\s\S]*?ApiKeyVault\.put\s*\(\s*\w+\s*\)/,
    'LlmConfig.setApiKey() must call ApiKeyVault.put(<some-var>)'
  );
});

// 测试 12: LlmConfig.clearApiKey() 委托 ApiKeyVault.clear()
test('LlmConfig.clearApiKey() delegates to ApiKeyVault.clear()', () => {
  const clearApiKeyMatch = llmConfig.match(
    /public\s+async\s+clearApiKey\s*\(\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}\n\s*\n\s*\/\//m
  );
  assert.ok(clearApiKeyMatch !== null, 'LlmConfig.clearApiKey() method not found');
  assert.match(
    clearApiKeyMatch[1],
    /ApiKeyVault\.clear\s*\(\s*\)/,
    'LlmConfig.clearApiKey() must call ApiKeyVault.clear()'
  );
});

// 测试 13: LlmConfig 不再直接调用 preferences for api_key
test('LlmConfig no longer uses preferences for api_key', () => {
  // getApiKey / setApiKey / clearApiKey 三个方法内部不应有 preferences.* 调用
  const getApiKeyBody = llmConfig.match(
    /public\s+async\s+getApiKey\s*\(\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*string\s*\|\s*null\s*>\s*\{([\s\S]*?)\n\s*\}/m
  );
  const setApiKeyBody = llmConfig.match(
    /public\s+async\s+setApiKey\s*\(\s*\w+\s*:\s*string\s*,\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}/m
  );
  const clearApiKeyBody = llmConfig.match(
    /public\s+async\s+clearApiKey\s*\(\s*vendorId\s*\?\s*:\s*string\s*\)\s*:\s*Promise\s*<\s*void\s*>\s*\{([\s\S]*?)\n\s*\}/m
  );
  for (const [name, body] of [['getApiKey', getApiKeyBody], ['setApiKey', setApiKeyBody], ['clearApiKey', clearApiKeyBody]]) {
    assert.ok(body !== null, `LlmConfig.${ name }() method not found`);
    assert.doesNotMatch(
      body[1],
      /preferences\./,
      `LlmConfig.${ name }() must not call preferences.* (PR1 fix: delegate to ApiKeyVault)`
    );
  }
});

// 测试 14: KEY_API_KEY 常量从 LlmConfig 移除(不再需要)
test('LlmConfig removes KEY_API_KEY constant', () => {
  assert.doesNotMatch(
    llmConfig,
    /(?:const|let|var)\s+KEY_API_KEY\s*=/,
    'LlmConfig must no longer define KEY_API_KEY (apiKey moved to ApiKeyVault)'
  );
});

// === Index.ets re-export ===

const commonIndex = read('common/src/main/ets/Index.ets');

// 测试 15: Index.ets re-export ApiKeyVault
test('common Index.ets re-exports ApiKeyVault', () => {
  assert.match(
    commonIndex,
    /export\s*\{\s*ApiKeyVault\s*\}\s*from\s*['"]\.\/security\/ApiKeyVault['"]/,
    'common Index.ets must re-export ApiKeyVault from ./security/ApiKeyVault'
  );
});

// === security.md 文档同步 ===

const securityMd = read('docs/agents/security.md');

// 测试 16: security.md 描述更新(提到 AssetStoreKit)
test('security.md mentions AssetStoreKit for API key', () => {
  assert.match(
    securityMd,
    /AssetStoreKit/,
    'security.md must be updated to mention AssetStoreKit for API key storage'
  );
});
