# PR1 — feat(common): LlmConfig apiKey 升级到 AssetStoreKit

> **分支**:`bugfix/llm-config-audit-2026-09-06`
> **Spec**:[016](../specs/016-llm-settings-redesign.md)
> **源 ADR**:[0014](../adr/0014-asset-store-kit-migration.md)
> **依赖**:无(独立可做)
> **工作量**:1 个新文件 + LlmConfig 委托改造 + 单元测试
> **风险**:中(Q13=C 兼容读取降低风险)
> **顺序**:第 2 个 PR

## 为什么

详见 [ADR 0014 §背景](../adr/0014-asset-store-kit-migration.md#背景)。

## 改动

### 新建 `common/src/main/ets/security/ApiKeyVault.ets`

封装 `@kit.AssetStoreKit` 操作(详见 spec 016 §公共接口变更)。

### 修改 `common/src/main/ets/llm/LlmConfig.ets`

```ts
// 改动前
async getApiKey(): Promise<string | null> {
  const p = await preferences.getPreferences(getContext(), 'mindtrace_llm')
  return (await p.get('api_key', '')) as string
}
async setApiKey(key: string): Promise<void> {
  const p = await preferences.getPreferences(getContext(), 'mindtrace_llm')
  await p.put('api_key', key)
  await p.flush()
}
async clearApiKey(): Promise<void> {
  const p = await preferences.getPreferences(getContext(), 'mindtrace_llm')
  await p.delete('api_key')
  await p.flush()
}

// 改动后
async getApiKey(): Promise<string | null> {
  return ApiKeyVault.get()
}
async setApiKey(key: string): Promise<void> {
  await ApiKeyVault.put(key)
}
async clearApiKey(): Promise<void> {
  await ApiKeyVault.clear()
}
```

### 修改 `common/src/main/ets/Index.ets`

加 re-export:`export { ApiKeyVault } from './security/ApiKeyVault'`

## 测试计划(TDD)

Red(写失败测试):
1. `api-key-vault.test.mjs`:`ApiKeyVault.put('sk-test')` → `ApiKeyVault.get()` === 'sk-test'
2. `api-key-vault.test.mjs`:Preferences 已有 'sk-legacy' → `ApiKeyVault.get()` 返回 'sk-legacy'(fallback)
3. `api-key-vault.test.mjs`:fallback 后再读 `ApiKeyVault.get()` 仍返回 'sk-legacy'(已迁移到 AssetStoreKit)
4. `llm-config.test.mjs`:`LlmConfig.getApiKey()` 委托 ApiKeyVault(验证 mock 后委托调用)

Green:实现 ApiKeyVault + LlmConfig 委托改造。

## 验收

- [ ] ApiKeyVault 3 个单元测试通过
- [ ] LlmConfig 委托 1 个测试通过
- [ ] 现有所有 arkts-lint 测试通过(回归)
- [ ] 端到端冒烟:打开 app,旧 key 自动迁移,UI 显示 "已配置"
- [ ] `docs/agents/security.md` 更新凭据存储描述

## 回滚

`git revert` 后 LlmConfig 回到 Preferences 实现;fallback 路径保证用户 key 可访问。

## 注意事项

- `@kit.AssetStoreKit` 的 `accessibility: DEVICE_UNLOCKED` 需要 API 12+,当前 API 9 下需 fallback 评估(详见 ADR 0014 §注意事项)

## 最后更新

2026-09-06