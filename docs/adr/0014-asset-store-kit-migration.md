# 0014 — API key 从 preferences 迁移到 @kit.AssetStoreKit(TEE 加密)

> **状态**: accepted (2026-09-06);实施跟随 [spec 016](../specs/016-llm-settings-redesign.md)

## 背景

MindTrace 当前 API key 用 `@kit.ArkData preferences` 存储(`common/src/main/ets/llm/LlmConfig.ets`):

```ts
// 当前实现(简化)
const p = await preferences.getPreferences(getContext(), 'mindtrace_llm')
await p.put('api_key', key)
await p.flush()
```

这是 **明文 KV**,违反 [docs/agents/security.md](../agents/security.md) 长期意图("API Key 不入 git" 是防止提交,不防止设备本地明文)。调研 [docs/research/llm-provider-patterns-2026-09-06.md §1.3](../research/llm-provider-patterns-2026-09-06.md) 强推:`@kit.AssetStoreKit` 是 TEE 硬件加密 + AES256-GCM,正是为 Token 类凭据设计。

## 候选方案

1. **AssetStoreKit + 兼容读取**(选用,Q13=C)
   - 写入只走 AssetStoreKit
   - 读取优先 AssetStoreKit;AssetStoreKit 空时 fallback Preferences 旧 key,并自动写回 AssetStoreKit(迁移透明)
   - 不主动清 Preferences(降低风险);下次清理是独立 PR

2. **AssetStoreKit 一次性迁移**(Q13=A):读 Preferences → 写 AssetStoreKit → 清 Preferences
   - 用户体验差:迁移失败时 key 丢失
   - 激进,违反 "渐进式" 精神

3. **自加密 Preferences**(Q13=C 的备选):`@ohos.security.cryptoFramework` 加密后写 preferences
   - 不利用 TEE,密钥管理也是问题
   - 重复造轮子
   - 不推荐

4. **继续用 preferences**(用户原 Q5=A 推荐,但被调研推翻)
   - 明文,合规风险;security review 可能被打回

## 影响

### 选用(1)

- `common/src/main/ets/security/ApiKeyVault.ets` 新建,封装 AssetStoreKit 操作
- `LlmConfig.getApiKey / setApiKey / clearApiKey` 委托 `ApiKeyVault`
- 用户体验:**打开 app 自动迁移,UI 无感知**;旧 Preferences key 自动写 AssetStoreKit
- API 表面不变(`LlmConfig.getApiKey` 还是返回 `string | null`)
- 已卸载重装的用户:Preferences 已空,AssetStoreKit 也空,key 需重输(无 key 丢失问题,因为 preferences 也已丢)

### 注意事项

- **`@kit.AssetStoreKit` 在 API 9(当前) 可用**,但 `accessibility: DEVICE_UNLOCKED` 需要 API 12+。PR1 中需评估 fallback:
  - 选项 A:无 `accessibility` 参数(默认行为,可能限制较少)
  - 选项 B:`DEVICE_PASSED`(API 12+ 才有,fallback 到 A)
  - 选项 C:本次只用 AssetStoreKit,后续 spec 跟进 API 升级
- **迁移路径**:Preferences 旧 key 格式是明文,AssetStoreKit 写入是加密;自动迁移通过 fallback 路径完成

### Future work

- 主动清理 Preferences(后续 PR):AssetStoreKit 写入成功后删除 Preferences key
- API 升级到 12+ 后用 `accessibility: DEVICE_UNLOCKED` 增强安全

## 可逆性

**中** — AssetStoreKit 路径是新增;fallback Preferences 保证旧 key 不丢;git revert 后旧 Preferences 路径可用(无数据迁移,只是路径切回)。**唯一风险**:用户已迁移到 AssetStoreKit 的 key,git revert 后无法读取(因为代码回到 Preferences)— 但 Preferences 旧 key 还在 fallback 路径,**代码可以读 fallback 重新恢复**。所以可逆。

## 关联

- [spec 016](../specs/016-llm-settings-redesign.md) — 实施 spec
- [ADR 0013](./0013-llm-provider-presets.md) — 配套(同一个 spec)
- [research §1.3 AssetStoreKit](../research/llm-provider-patterns-2026-09-06.md#1-鸿蒙生态现有方案) — TEE + AES256-GCM 细节
- [docs/agents/security.md](../agents/security.md) — 当前凭据存储描述(待更新)

## 最后更新

2026-09-06