# 0013 — LLM Provider 预设表(5 家国内大模型);factory + 静态 const,UI 仅暴露 baseUrl/model/apiKey 4 字段

> **状态**: accepted (2026-09-06);实施跟随 [spec 016](../specs/016-llm-settings-redesign.md)

## 背景

AI 设置页(2026-09-06 用户反馈)三大痛点之一:**UI 不尽人意,缺少国内大模型厂商列表**。当前 `entry/src/main/ets/pages/AiSettings/EndpointPicker.ets` 只有 2 个选项:DeepSeek 官方 + 自定义 OpenAI 兼容端点。

调研 [docs/research/llm-provider-patterns-2026-09-06.md](../research/llm-provider-patterns-2026-09-06.md) §6 给出 5 个 seam 候选。本 ADR 决策 **seam #3** 的具体设计:静态 const + factory + provider 预设表。

## 候选方案

1. **静态 const + factory + 4 字段最小自定义**(选用)
   - `PROVIDERS: ProviderConfig[]` 5 家国内大模型(DeepSeek / 通义 / GLM / Kimi / 豆包)
   - 工厂 `findProvider(id)` 做线性查找(5 项,n=小)
   - 自定义厂商字段最小:vendor name / baseUrl / model / apiKey(Q7=A);temp / maxT / timeout 全局共享
   - Q1=C 渐进式;Q2=A 仅 OpenAI 兼容;Q4=A 单 provider 当前激活

2. **JSON 配置文件**(`resources/rawfile/providers.json`,动态加载)
   - 灵活,可热更新;但引入新风险(JSON 校验、加载失败 fallback、类型擦除)
   - 5 家预设不需要动态,Q12=A 否定

3. **Adapter 抽象**(`BaseLlmAdapter` interface + 各 provider 实现类)
   - 调研 seam #1 强推;但需要协议差异(Anthropic / Gemini)— Q2=A 不需要
   - 5 家都是 OpenAI 兼容,1 个 if-else 工厂足够,不需要 interface
   - 工作量大(Q1=C 渐进式精神否定)

4. **多 provider 运行时切换**(保存多个,UI 切换激活哪个)
   - Q4=A 否定(用户原话 "默认 + 自定义",不是 "多 provider 切换")

## 影响

### 选用(1)

- `common/src/main/ets/llm/providers.ets` 新建,导出 `PROVIDERS / DEFAULT_VENDOR_ID / findProvider / CustomVendorConfig`
- `LlmConfig` 增加 `vendorId / customVendorConfig` 字段
- ViewModel 增加 `vendorId / customVendor` + setter
- `entry/src/main/ets/pages/AiSettings/VendorPicker.ets` 新建(默认 5 厂商 Radio + "自定义" 选项)
- `entry/src/main/ets/pages/AiSettings/CustomVendorForm.ets` 新建(vendor name / baseUrl / model / apiKey 输入)

### Future work(留 ADR 跟踪)

- **seam #1** `BaseLlmAdapter` interface:未来要加 Anthropic / Gemini 时做(spec 016 §Future work)
- **seam #4** `LlmConfigSnapshot` validate:未来要做配置导出/分享/恢复时做
- **seam #5** Anthropic 协议独立路径:spec 005 §"Out of scope" 已声明;后续 spec
- 多 provider 运行时切换:产品后续评估

## 可逆性

**高** — PROVIDERS 是常量数组 + factory 是纯函数;LlmConfig 新增字段可独立删除;UI 新增组件可独立删除。`git revert` 即可。

## 关联

- [spec 016](../specs/016-llm-settings-redesign.md) — 实施 spec
- [ADR 0014](./0014-asset-store-kit-migration.md) — 凭据存储升级(配套)
- [research §6 seam 候选](../research/llm-provider-patterns-2026-09-06.md#6-seam-候选) — 5 个候选
- [frontend-component-audit-2026-09-06.md §5 finding 5](../research/frontend-component-audit-2026-09-06.md) — AiSettings 9 子件不上收(本 ADR 不上收)

## 最后更新

2026-09-06