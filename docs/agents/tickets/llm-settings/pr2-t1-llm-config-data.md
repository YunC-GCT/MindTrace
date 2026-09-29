# PR2-T1 — feat(common): 新增 provider 预设 + CustomVendorConfig + vendorId/customVendorConfig 字段

> **分支**:`bugfix/llm-config-audit-2026-09-06`
> **Spec**:[016](../specs/016-llm-settings-redesign.md)
> **源 ADR**:[0013](../adr/0013-llm-provider-presets.md)
> **依赖**:PR1(AssetStoreKit 必须先做,本 PR 增加 vendor 字段也涉及 LlmConfig)
> **工作量**:1 新建文件 + LlmConfig 增加 4 个方法 + 5 个单元测试
> **风险**:低(增量改动,不影响旧 API)
> **顺序**:第 3 个 PR

## 为什么

详见 [ADR 0013 §背景](../adr/0013-llm-provider-presets.md#背景)。

## 改动

### 新建 `common/src/main/ets/llm/providers.ets`

5 厂商预设 + DEFAULT_VENDOR_ID + findProvider + CustomVendorConfig interface(详见 spec 016 §公共接口变更)。

> **2026-09 时点调研**:`PROVIDERS` 数组的 baseUrl 与 defaultModel 已用一手信源核实:
>
> | 厂商 | 当前模型 | baseUrl |
> |---|---|---|
> | DeepSeek | `deepseek-v4-pro`(DeepSeek-V4-Pro-0813) | `https://api.deepseek.com` |
> | 通义 | `qwen3-max` 系列(具体子型号待用户确认) | `https://dashscope.aliyuncs.com/compatible-mode/v1`(含 `{WorkspaceId}` 占位符) |
> | 智谱 GLM | `glm-5.3`(2026 旗舰,已升 5.x) | `https://open.bigmodel.cn/api/paas/v4/` |
> | Kimi | `kimi-k2.6`(2026 通用旗舰;K3 更强但 K2.6 更稳定) | `https://api.moonshot.cn/v1` |
> | 豆包 | `doubao-seed-1.6`(2026 Seed 系列) | `https://ark.cn-beijing.volces.com/api/v3` |
>
> 详见 `docs/agents/llm-settings-scope-2026-09-06.md` §附录 C 调研报告(一手 URL 信源)。

### 修改 `common/src/main/ets/llm/LlmConfig.ets`

新增 4 个方法:
```ts
async getVendorId(): Promise<string>                              // 默认 'deepseek'
async setVendorId(id: string): Promise<void>
async getCustomVendorConfig(): Promise<CustomVendorConfig | null>
async setCustomVendorConfig(cfg: CustomVendorConfig): Promise<void>
```

修改 `getEndpoint()` 解析逻辑:根据 vendorId 返回对应 baseUrl(`vendorId === 'custom'` 时返回 `customVendorConfig.baseUrl`)。

修改 `getModel()`:同上模式。

### 修改 `common/src/main/ets/Index.ets`

加 re-export:
```ts
export { PROVIDERS, DEFAULT_VENDOR_ID, findProvider } from './llm/providers'
export type { ProviderConfig, CustomVendorConfig } from './llm/providers'
```

## 测试计划(TDD)

5 个单元测试:
1. `providers.test.mjs`:`PROVIDERS.length === 5`,DeepSeek 排在首位
2. `providers.test.mjs`:`findProvider('deepseek')` 返回正确 config
3. `providers.test.mjs`:`findProvider('not-exist')` 返回 null
4. `llm-config.test.mjs`:`LlmConfig.getEndpoint()` 默认 = `'https://api.deepseek.com'`(vendorId='deepseek')
5. `llm-config.test.mjs`:`LlmConfig.setVendorId('tongyi')` 后 `getEndpoint()` = 通义 baseUrl

## 验收

- [ ] 5 个单元测试通过
- [ ] 现有所有 arkts-lint 测试通过
- [ ] 端到端冒烟:可手动验证(不是 PR2-T1 的硬验收,但 PR2-T2 必跑)

## 回滚

`git revert` 后 LlmConfig 回到无 vendor 字段;`providers.ets` 删除即可。无旧数据需要迁移(vendor 字段是新增)。

## 最后更新

2026-09-06