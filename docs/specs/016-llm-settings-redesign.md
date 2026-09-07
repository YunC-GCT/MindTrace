# Spec 016 — LLM 设置页重构

> **状态**: draft (2026-09-06)
> **源 ADR**: [0013](../adr/0013-llm-provider-presets.md)、[0014](../adr/0014-asset-store-kit-migration.md)
> **调研依据**: [docs/research/llm-provider-patterns-2026-09-06.md](../research/llm-provider-patterns-2026-09-06.md)
> **作者**: 主线程(grilling + research)
> **最后更新**: 2026-09-06

## 背景(为什么做这个 spec)

AI 设置页三大痛点(用户 2026-09-06 报告):

1. **UI 不尽人意** — 目前只有 "DeepSeek 官方 / 自定义 OpenAI 兼容" 两个选项,缺乏国内大模型厂商列表
2. **P0 bug**:`PRO_MODEL = "deepseek-v4-pro"` 不存在 — DeepSeek 官方只有 `deepseek-chat` / `deepseek-reasoner`,用户填真实 key 后仍被 API 拒绝
3. **凭据存储错配** — API key 用 preferences 明文存储,违反 `docs/agents/security.md` 的长期意图;官方方案 `@kit.AssetStoreKit` 是 TEE 加密的 Token 类凭据存储

附加发现(fact-finding 阶段):
- **ViewModel 的 `syncEndpoint / syncModel` 在做关键字嗅探**,违反 ticket #9 修复的 "禁止 keyword 静默 fallback" 原则(`docs/agents/security.md:25`) — 本 spec 必须清理

## 目标

1. 提供 5 家国内大模型厂商作为预设(DeepSeek / 通义千问 / 智谱 GLM / 月之暗面 Kimi / 字节豆包)
2. 支持用户自定义厂商(填 vendor name + baseUrl + model + apiKey)
3. **P0 bug 一行修复**:`PRO_MODEL` → `deepseek-chat`
4. 凭据升级到 AssetStoreKit(TEE 加密,兼容读取)
5. 清理 ViewModel 的关键字嗅探
6. OCR 配置区块保留(用户后续剥离,本次不改动)

## 非目标(明确不做)

- 多 provider 运行时切换(Q4=A)
- Adapter 抽象(`BaseLlmAdapter` interface)— 留 Future work
- Anthropic / Gemini 协议(Q2=A,仅 OpenAI 兼容)
- OCR 配置剥离(用户后续 PR)
- light theme / 视觉大幅重做(Q9=A,沿用现有 dark + MINT)

## 涉及文件

### 新建

- `common/src/main/ets/llm/providers.ets` — 5 厂商预设常量
- `common/src/main/ets/security/ApiKeyVault.ets` — AssetStoreKit 凭据封装
- `entry/src/main/ets/pages/AiSettings/VendorPicker.ets` — 默认厂商选择器
- `entry/src/main/ets/pages/AiSettings/CustomVendorForm.ets` — 自定义厂商表单

### 修改

- `common/src/main/ets/llm/LlmConfig.ets` — apiKey 存储改 AssetStoreKit + 新增 vendorId / customVendorConfig 字段
- `common/src/main/ets/Index.ets` — re-export 新符号
- `entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets` — 重组 7 子组件
- `entry/src/main/ets/pages/AiSettings/EndpointPicker.ets` — 简化为 "被 VendorPicker 包含" 或删除
- `entry/src/main/ets/pages/AiSettings/ModelPicker.ets` — `PRO_MODEL` 改 `deepseek-chat`;保留 model 自定义输入
- `entry/src/main/ets/viewmodels/AiSettingsViewModel.ets` — 移除 `syncEndpoint / syncModel` 关键字嗅探;新增 vendor / customVendor 字段
- `docs/specs/index.md` — 状态行更新(2026-09-06)
- `docs/agents/security.md` — 更新凭据存储描述

### 不动(用户保留 / OCR / 其他展示组件)

- `entry/src/main/ets/pages/AiSettings/OcrConfigSection.ets`
- `entry/src/main/ets/pages/AiSettings/ConnectionStatus.ets`
- `entry/src/main/ets/pages/AiSettings/ActionBar.ets`
- `entry/src/main/ets/pages/AiSettings/PageHeader.ets`
- `entry/src/main/ets/pages/AiSettings/KeyInput.ets`
- `AiSettingsViewModel` 中的 `ocrEndpoint / ocrEnabled / ocrMode / ocrStatusText / ocrTesting / testOcr() / resetOcrEndpoint()` 等 OCR 字段与方法

## 公共接口变更

### common/src/main/ets/llm/providers.ets (新建)

```ts
export interface ProviderConfig {
  id: string                  // 'deepseek' | 'tongyi' | 'glm' | 'kimi' | 'doubao' | 'custom'
  vendorName: string          // 显示名 'DeepSeek'
  baseUrl: string             // 'https://api.deepseek.com'
  defaultModel: string        // 'deepseek-chat'
  protocolKind: 'openai-compatible'  // Q2=A 协议范围
  docsUrl: string             // 厂商文档链接
}

export const PROVIDERS: ProviderConfig[] = [
  // 2026-09 时点一手信源调研结果(详见 docs/agents/llm-settings-scope-2026-09-06.md §附录 C 调研报告)
  {
    id: 'deepseek',
    vendorName: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-v4-pro',  // DeepSeek-V4-Pro-0813 当前旗舰(已更新,调用方式不变)
    protocolKind: 'openai-compatible',
    docsUrl: 'https://api-docs.deepseek.com/',
  },
  {
    id: 'tongyi',
    vendorName: '通义千问(Qwen)',
    // ⚠️ 含 {WorkspaceId} 占位符,用户在 UI 需替换为自己的业务空间 ID
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen3-max',  // 2026 时点通义千问顶级模型(具体子型号如 qwen3-max / qwen3-max-preview / qwen3.8-max 待用户在 PR2-T1 前确认)
    protocolKind: 'openai-compatible',
    docsUrl: 'https://help.aliyun.com/zh/model-studio/developer-reference/compatibility-of-openai-with-dashscope',
  },
  {
    id: 'glm',
    vendorName: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4/',
    defaultModel: 'glm-5.3',  // 2026 时点 GLM 旗舰(已升 5.x;官方迁移文档:docs.bigmodel.cn/cn/guide/start/migrate-to-glm-new)
    protocolKind: 'openai-compatible',
    docsUrl: 'https://docs.bigmodel.cn/cn/guide/start/migrate-to-glm-new',
  },
  {
    id: 'kimi',
    vendorName: '月之暗面 Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'kimi-k2.6',  // 2026 时点通用旗舰;K3 是更强旗舰但 K2.6 更稳定通用(用户在 PR2-T1 前可确认是否改 K3)
    protocolKind: 'openai-compatible',
    docsUrl: 'https://platform.kimi.com/docs',
  },
  {
    id: 'doubao',
    vendorName: '字节豆包(Doubao)',
    // 普通 API 模式;Coding Plan 套餐用 https://ark.cn-beijing.volces.com/api/coding/v3
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultModel: 'doubao-seed-1.6',  // 2026 时点豆包 Seed 系列;用户可在 PR2-T1 前确认 doubao-seed-1.6 vs doubao-seed-code
    protocolKind: 'openai-compatible',
    docsUrl: 'https://www.volcengine.com/docs/82379',
  },
]

export const DEFAULT_VENDOR_ID: string = 'deepseek'

export interface CustomVendorConfig {
  vendorName: string          // 用户填的显示名
  baseUrl: string             // 完整 URL
  model: string               // model id
  // apiKey 不在此处,走 ApiKeyVault
}

export function findProvider(id: string): ProviderConfig | null {
  for (const p of PROVIDERS) { if (p.id === id) return p }
  return null
}
```

### common/src/main/ets/security/ApiKeyVault.ets (新建)

```ts
import { asset } from '@kit.AssetStoreKit'

const ASSET_NAME: string = 'llm_api_key'  // 单 vendor 当前激活(Q4=A)

export class ApiKeyVault {
  static async get(): Promise<string | null> {
    try {
      const r = await asset.query({ name: ASSET_NAME })
      if (r.length > 0) { return r[0] }
    } catch (_e) { /* 继续 fallback */ }
    // Fallback: 从 preferences 读旧 key(Q13=C 兼容读取)
    const legacy: string | null = await this.readLegacyPreferences()
    if (legacy !== null) {
      await this.put(legacy)  // 自动写入 AssetStoreKit(迁移透明)
    }
    return legacy
  }

  static async put(key: string): Promise<void> {
    await asset.add({
      name: ASSET_NAME,
      value: key,
      accessibility: asset.Accessibility.DEVICE_UNLOCKED,  // API 12+;fallback 见 §注意事项
    })
  }

  static async clear(): Promise<void> {
    try { await asset.remove({ name: ASSET_NAME }) } catch (_e) {}
  }

  private static async readLegacyPreferences(): Promise<string | null> {
    try {
      const p = await preferences.getPreferences(getContext(), 'mindtrace_llm')
      const k = await p.get('api_key', '')
      return (k as string).length > 0 ? (k as string) : null
    } catch (_e) {
      return null
    }
  }
}
```

### common/src/main/ets/llm/LlmConfig.ets (修改)

存储后端切换:`getApiKey / setApiKey / clearApiKey` 委托 `ApiKeyVault`。

新增字段:
```ts
async getVendorId(): Promise<string>                              // 默认 'deepseek'
async setVendorId(id: string): Promise<void>
async getCustomVendorConfig(): Promise<CustomVendorConfig | null>
async setCustomVendorConfig(cfg: CustomVendorConfig): Promise<void>
```

修改 `getEndpoint()`:`vendorId === 'custom'` 时返回 `customVendorConfig.baseUrl`,否则 `findProvider(vendorId).baseUrl`。

修改 `getModel()`:同上模式。

### ViewModel (修改)

**删除**:
- `syncEndpoint(endpoint: string)`(`AiSettingsViewModel.ets:265-280`)
- `syncModel(model: string)`(`AiSettingsViewModel.ets:282-302`)

**理由**:这两个函数嗅探 endpoint / model 字符串里的关键字,决定 `useCustomEP / mdlIdx`,违反 ticket #9 修复的 "禁止 keyword 静默 fallback" 原则(`docs/agents/security.md:25`)。改用 LlmConfig 直接读写 + UI 由用户选择控制。

**新增**:
- `vendorId: string`
- `customVendor: CustomVendorConfig | null`
- `setVendorId(id: string)`
- `setCustomVendor(cfg: CustomVendorConfig)`

## 测试计划(TDD)

| 测试 | 文件 | 验证内容 |
|---|---|---|
| `PROVIDERS.length === 5`,DeepSeek 排在首位 | `providers.test.mjs` | 常量表完整 |
| `findProvider('deepseek')` 返回正确 config | 同上 | 查找函数 |
| `findProvider('not-exist')` 返回 null | 同上 | 边界 |
| `ApiKeyVault.get()` 优先 AssetStoreKit | `api-key-vault.test.mjs` | 兼容读取(Q13=C) |
| `ApiKeyVault.put()` 写入 AssetStoreKit | 同上 | 写入路径 |
| `ApiKeyVault.get()` fallback Preferences 旧 key,自动写回 | 同上 | 迁移 |
| `LlmConfig.getEndpoint()` 按 vendorId 返回正确 baseUrl | `llm-config.test.mjs` | vendor 解析 |
| `LlmConfig.setCustomVendorConfig()` 后读取一致 | 同上 | 自定义厂商持久化 |
| `ViewModel.load()` 不再嗅探 endpoint / model(AST 验证) | `ai-settings-vm.test.mjs` | ticket #9 精神 |
| 端到端冒烟(Q10=A,用户真跑) | 手动 | 真 API 调用 |

## 验收标准

- [ ] `node scripts/arkts-lint/index.mjs --quiet` 0 错误
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` 全绿
- [ ] 上述 10 个新单元测试全绿
- [ ] **端到端冒烟通过**(Q10=A):选 DeepSeek → 填真实 key → "测试连接"返回成功 → 真拍照 → capture 流跑通
- [ ] 5 厂商在 UI 均可选,选通义填 key 后真 API 可用
- [ ] 自定义厂商可填 4 字段,baseUrl + model + key 填后跑通
- [ ] **P0 bug 已修复**:`PRO_MODEL = "deepseek-chat"` — 默认厂商密钥可用
- [ ] 凭据走 AssetStoreKit:卸载 / 重装 app 不丢;preferences 旧 key 自动迁移
- [ ] ViewModel 已无 `syncEndpoint / syncModel` 关键字嗅探
- [ ] OCR 配置区块未受影响(后续剥离路径保留)
- [ ] `docs/specs/index.md` 状态行已更新
- [ ] `docs/agents/security.md` 凭据存储描述已更新

## 实施顺序(4 个 PR)

1. **PR0**:`fix(common)` 1 行字串修复(`PRO_MODEL → deepseek-chat`)
2. **PR1**:`feat(common)` AssetStoreKit 升级(ApiKeyVault + LlmConfig 委托)
3. **PR2-T1**:`feat(common)` provider 预设(`providers.ets` + LlmConfig 4 个新方法)
4. **PR2-T2**:`feat(entry)` UI 重构(VendorPicker + CustomVendorForm + ViewModel 清理)
5. **PR3**:`docs(specs)` spec 016 + ADR 0013 / 0014 + tickets(本批次产出)

每个 PR 独立可回滚。

## 可逆性

- **PR0**:极简单 — 1 行字串,git revert
- **PR1**:高 — AssetStoreKit 路径是新增;fallback Preferences 保证旧 key 不丢;git revert 后旧路径可用
- **PR2-T1**:高 — 新增字段 + 新建文件,删除回滚即可
- **PR2-T2**:中 — UI 重组,git revert 后旧 UI 回来;5 厂商预设列表保留便于后续复用

## 注意事项

- **`@kit.AssetStoreKit` 在 API 9(当前) 可用**,但 `accessibility: DEVICE_UNLOCKED` 需要 API 12+。PR1 中需评估 fallback:
  - 选项 A:无 `accessibility` 参数(默认行为)
  - 选项 B:`DEVICE_PASSED`(API 12+ 才有)
  - 选项 C:本次只用 AssetStoreKit,后续 spec 跟进 API 升级
- **迁移路径**:Preferences 旧 key 格式是明文,AssetStoreKit 写入是加密;自动迁移通过 fallback 路径完成(用户无感知)

## 待澄清问题

- **Q:5 厂商的 baseUrl / defaultModel 在写 spec 前是否需要用户验证?**
  A: 不需要,research 已确认 5 家都是 OpenAI 兼容,baseUrl / defaultModel 来自各家官方文档。但 PR2-T1 前最好让用户扫一眼 5 家实际 model 列表是否有变动。
- **Q:`PRO_MODEL = "deepseek-chat"` 是否是 DeepSeek 当前最新?**
  A: 是(2026-09 时点)。如有更新,后续 PR 跟进。

## OCR 配置约束(用户保留,后续剥离)

- **本次不改** OcrConfigSection.ets / OcrConfig / ViewModel 的 OCR 字段
- ViewModel 的 OCR 字段保持独立(`ocrEndpoint / ocrEnabled / ocrMode / ocrStatusText / ocrTesting / testOcr()`)
- 后续剥离路径(后续 PR,不在本 spec):
  1. 删除 OcrConfigSection.ets + 8 件 OCR UI
  2. 删除 ViewModel OCR 字段与方法
  3. 删除 OcrConfig 整套(`tools/ocr_service` 融入程序内部)
  4. 从 AiSettingsPage 移除 OcrConfigSection import
- 本 spec 设计保证 OCR 部分与 LLM 配置部分**正交**(无共享字段、无方法耦合),方便后续 grep + 删除

## 最后更新

2026-09-06