# Spec 017 — LLM 设置页 cleanup(PR2-T2 后续 L4 + L5 + L6)

> **Status**: draft (2026-09-08)
> **Source ADR**: implicit(spec 016 后续;承接 ticket #9 "LlmConfig 静默覆盖修复未完")
> **前序 spec**: [`016-llm-settings-redesign.md`](./016-llm-settings-redesign.md) §6.4 公共接口变更 + §8 验收标准
> **审计依据**: [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` §7 finding #9](../legacy/mindtrace/architecture/audit-full-2026-09-01.md)
> **handoff**: [`docs/agents/handoffs/pr2-t2-vendorpicker-handoff-2026-09-08.md` §8 已知限制](../agents/handoffs/pr2-t2-vendorpicker-handoff-2026-09-08.md) (L1-L5 列表)
> **作者**: 主线程(grill-with-docs → to-spec)
> **最后更新**: 2026-09-08

## Why this ticket

PR2-T2(commit `6b5c572`)完成了 `VendorPicker` UI 重构 + `LlmConfig.vendorId` 持久化,但 spec [`016`](./016-llm-settings-redesign.md) §公共接口变更 + §验收标准里**反 keyword 嗅探**与**简化 LlmConfig 路径**两个核心目标**未完整达成**。handoff §8 已显式列出 L1-L5 已知限制:

- **L4**:`AiSettingsViewModel` 旧字段(`useCustomEP / customEP / mdlIdx / useCustomMD / customMD / temp / maxT / to`)与 `syncEndpoint / syncModel` 关键字嗅探函数未删 — ticket #9 "禁止 keyword 静默 fallback" 修复目标只完成 UI 删 2 状态,**VM 与 page 调用层未清理**
- **L5**:`EndpointPicker.ets` / `ModelPicker.ets` 文件未 `git rm` — 死代码,build 仍包含
- **L6**(本 spec 新发现,**不在原 L1-L5 范围**):`AiSettingsPage.endpointSummary()` (lines 79-84) 仍在嗅探 `useCustomEP` + `customEP`,反 spec 016 §修改 line 53;**这是 page 层 keyword 嗅探,不是 VM 层,L4 没覆盖**

同时 spec 016 §验收标准 line 241 "ViewModel 已无 `syncEndpoint / syncModel` 关键字嗅探" + line 244 "凭据走 AssetStoreKit" 后者已 PR2-T1 完成,前者**未完成**。

**问题**(用户视角):
1. **安全**:`syncEndpoint / syncModel` 嗅探 `api.deepseek.com` 关键字决定 `useCustomEP` 状态,是 ticket #9 "keyword 静默 fallback" 反模式的同构重复,违反 `docs/agents/security.md:25`
2. **死代码**:`EndpointPicker.ets` / `ModelPicker.ets` 文件 + `useCustomEP / customEP` 等 8 个 VM 字段 + `syncEndpoint / syncModel` 函数 + `getModelSummary / getEndpointSummary` 等 12 个 set/toggle/resolve 方法,**已无 UI 引用**,但因 VM + page 互相 import,无法 `git rm`
3. **page 层漏洞**:`endpointSummary()` 仍按 `useCustomEP` 分支决定显示文案,与 spec §修改 line 53 "改用 LlmConfig 直接读写 + UI 由用户选择控制" 不一致

## What we will build

3 个 sub-task,1 张 PR:

### Sub-task 1(L4):删 `AiSettingsViewModel` keyword 嗅探

**删除**:
- `syncEndpoint(endpoint: string): void` (当前 line 76 + 264-280)
- `syncModel(model: string): void` (当前 line 77 + 282-302)
- 字段:`useCustomEP: boolean` / `customEP: string` / `mdlIdx: number` / `useCustomMD: boolean` / `customMD: string` / `temp: number` / `maxT: number` / `to: number`
- 12 个 set/toggle/resolve 方法(setCustomEndpoint / setUseCustomEP / toggleEndpoint / resolveEndpoint / setCustomModel / setUseCustomModel / setModelIndex / toggleModel / resolveModel / setTemp / setMaxTokens / setTimeout 等)

**保留**:
- `endpointSummary(): string` / `modelSummary(): string` 方法名(改实现,见 Sub-task 3)
- `save()` / `load()` 入口
- 新增 vendor 相关字段:`vendorId / customVendors / selectVendor / addCustomVendor / getCurrentVendor / getCurrentModel / getCurrentEndpoint`

**公开 API 变化**:
- 删除 `endpointSummary(): string` 反向(由 `useCustomEP` 决定文案)实现 → 改用 `getCurrentEndpoint()` 直接读 LlmConfig
- 删除 `modelSummary(): string` 反向(由 `mdlIdx` 决定文案)实现 → 改用 `getCurrentModel()` 直接读 LlmConfig

### Sub-task 2(L5):`git rm` 旧 Picker 文件

- `entry/src/main/ets/pages/AiSettings/EndpointPicker.ets` — `git rm`
- `entry/src/main/ets/pages/AiSettings/ModelPicker.ets` — `git rm`
- 验证:`scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs` 第 4 个测试读 `ModelPicker.ets` 文件路径,需更新为读 `common/src/main/ets/llm/providers.ets` 的 `findProvider('deepseek').defaultModel`(等价 PRO_MODEL)
- 验证:`AiSettingsViewModel.ets` 不再有 `import { DS_ENDPOINT } from "../pages/AiSettings/EndpointPicker"` 与 `import { PRO_MODEL } from "../pages/AiSettings/ModelPicker"`

### Sub-task 3(L6):重写 `AiSettingsPage.endpointSummary()`

**现状**(AiSettingsPage.ets:79-84):
```ts
endpointSummary(): string {
  // 嗅探 useCustomEP + customEP
  return vm.useCustomEP ? (vm.customEP || '自定义端点') : vm.getCurrentEndpoint()
}
```

**改后**(伪码):
```ts
endpointSummary(): string {
  // 直接读 vm.getCurrentEndpoint()(已在 PR2-T2 引入,读 LlmConfig.vendorId)
  return vm.getCurrentEndpoint()
}
```

同时改 `modelSummary()`:
- 删除旧版(嗅探 `mdlIdx` + `customMD`)
- 新版:返回 `vm.getCurrentModel()`(注意:handoff §8 L2 已知 `activeModel` 不持久化,本 spec 接受 preset defaultModel 显示在 summary,**L2 不在本 spec scope**)

## Public surface change

| 元素 | 变化 | 影响面 |
|---|---|---|
| `AiSettingsViewModel` 8 字段 | 删除 | 调用方需迁移(实测:无调用方,`grep` 验证) |
| `AiSettingsViewModel.syncEndpoint / syncModel` | 删除 | 调用方:`load()` 内部 → 改在 `load()` 内**不调**这两个函数,直接 `setVendorId(...)` 即可 |
| `AiSettingsViewModel.12 个 set/toggle/resolve` | 删除 | UI 不再使用(PR2-T2 已切到 VendorPicker) |
| `endpointSummary()` / `modelSummary()` | 改实现 | 返回 `vm.getCurrentEndpoint() / getCurrentModel()` |
| `EndpointPicker.ets` / `ModelPicker.ets` | 文件删除 | `AiSettingsViewModel` 去掉 import |
| `tests/llm-config-allow-default-model.test.mjs` 测试 4 | 改源 | 改读 `providers.ets` 而非 `ModelPicker.ets` |

**不破坏**:
- LlmConfig / VendorPicker / AiSettingsPage 主结构
- PR2-T2 测试 29/29 GREEN
- `docs/agents/security.md` (无变更)

## Migration

### 分支策略

- 基线分支:`develop`
- 新分支:`feat/llm-settings-cleanup`(从 `develop` 拉,基于 `bugfix/llm-config-audit-2026-09-06` 是 PR2-T2 前的旧基线,选 `develop` 是因为已含 PR2-T1 + PR2-T2 提交)

### 提交顺序(原子回滚)

```
0be51a7 chore(viewmodel): 删 useCustomEP 等 8 字段 + 12 个 set/toggle/resolve 方法 (Sub-task 1 上半)
3a8f2c1 fix(viewmodel): 删 syncEndpoint/syncModel + load() 内调用移除 (Sub-task 1 下半)
1d4e9b8 fix(page): endpointSummary/modelSummary 改用 getCurrent* (Sub-task 3)
f7c0a23 refactor(entry): git rm EndpointPicker.ets ModelPicker.ets + VM import 清理 (Sub-task 2)
b2d6f8a test(common): llm-config-allow-default-model test 4 改读 providers.ets
e8a4d12 docs: spec 017 status 行更新(index.md)
```

7 个 commit,每个原子可回滚。Sub-task 3 放在 Sub-task 2 之前,因为 Sub-task 2 后 VM 不再有 `useCustomEP`,如果 page 还引用,build 立即挂;所以 Sub-task 3 先清 page,再 Sub-task 2 清文件。

### Worktree 隔离

本 spec 在新 worktree 操作:`git worktree add D:\HMgent\MindTrace\mt-llm-settings-cleanup -b feat/llm-settings-cleanup develop`。原 `feature/pr2-t2-ui-vendorpicker` worktree 保留不动(等 PR2-T2 push 决策)。

## Test plan (TDD)

| 测试 | 文件 | 验证内容 |
|---|---|---|
| **T1** | `ai-settings-vendor.test.mjs` 新增 | `AiSettingsViewModel.ets` 不再含 `syncEndpoint` / `syncModel` 字符串(AST 校验) |
| **T2** | 同上 | `AiSettingsViewModel.ets` 不再含 `useCustomEP` / `customEP` / `mdlIdx` / `useCustomMD` / `customMD` 字段(AST) |
| **T3** | 同上 | `AiSettingsPage.endpointSummary()` 不再含 `useCustomEP` 字符串 |
| **T4** | 同上 | `AiSettingsPage.modelSummary()` 不再含 `mdlIdx` 字符串 |
| **T5** | 同上 | `EndpointPicker.ets` / `ModelPicker.ets` 文件不存在(`fs.existsSync` 返回 false) |
| **T6** | `llm-config-allow-default-model.test.mjs` 第 4 测试改 | 改读 `providers.ets` 的 `findProvider('deepseek').defaultModel`,断言仍等于 `LlmConfig.DEFAULT_MODEL` |
| **T7** | `ai-settings-vendor.test.mjs` 新增 | `endpointSummary()` 返回 `getCurrentEndpoint()`(`mock vm.getCurrentEndpoint = 'https://x.com/v1'`,断言返回 `'https://x.com/v1'`) |
| **T8** | 同上 | `load()` 不再嗅探 endpoint/model(grep `load()` 函数体内不出现 `syncEndpoint / syncModel` 字符串) |

PR2-T2 已有的 29 测试**全部仍 GREEN** + 新增 8 测试全 GREEN = 37/37。

## Reversibility

每 commit 单独 `git revert` 可回滚:
- Sub-task 1 字段删除:`git revert 0be51a7` 恢复字段(注意:`syncEndpoint` 在 3a8f2c1 单独 revert 即可恢复函数)
- Sub-task 3 改动:`git revert 1d4e9b8` 恢复 page 旧实现
- Sub-task 2 文件删除:`git revert f7c0a23` 恢复文件 + VM import(但 import 已被 Sub-task 1 删除的 `useCustomEP` 用过,可能冲突,需手动合并)

**总体可逆性**:中。3 个 sub-task 互相耦合(VendorPicker 假设 page 不再嗅探,VM 假设 page 不再读 `useCustomEP`),完全 revert 需 3 commit 顺序 revert。

## Acceptance criteria

- [ ] `node --test scripts/arkts-lint/tests/ai-settings-vendor.test.mjs` 37/37 GREEN(原 29 + 新 8)
- [ ] `node --test scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs` 全 GREEN(含 T6 改后)
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` 全 GREEN(全 suite)
- [ ] `hvigorw assembleHap` BUILD SUCCESSFUL
- [ ] `git grep -n 'useCustomEP\|customEP\|mdlIdx\|useCustomMD\|customMD\|syncEndpoint\|syncModel' -- '*.ets'` 0 命中
- [ ] `git grep -n 'EndpointPicker\|ModelPicker' -- '*.ets' '*.mjs'` 仅命中 `tests/` 文件(说明完全删干净,测试已迁移)
- [ ] `ls entry/src/main/ets/pages/AiSettings/EndpointPicker.ets ModelPicker.ets` "No such file or directory"
- [ ] 真实机:`VendorPicker` 选中 DeepSeek → AI 服务 summary 仍显示 `https://api.deepseek.com`(由 `getCurrentEndpoint()` 走 PROVIDERS)
- [ ] 真实机:切到通义 → summary 显示 `https://dashscope.aliyuncs.com/compatible-mode/v1`
- [ ] `docs/specs/index.md` 状态行更新(spec 017 → in progress → implemented)
- [ ] handoff §8 L4/L5/L6 标记 ✅ 完成(L2 仍 pending)

## Sequence

```
1. (前置)PR2-T2(commit 6b5c572)未 push 时,本 spec 在新 worktree 操作
2. git worktree add ../mt-llm-settings-cleanup -b feat/llm-settings-cleanup develop
3. 在新 worktree 内:
   a. RED: 写 T1-T5 + T7-T8 测试 → 跑 → 期望 8 FAIL
   b. RED: 改 T6 测试 → 跑 → 期望 1 FAIL
   c. GREEN: 按 7 个 commit 顺序实现
   d. 跑全 suite → 37/37 GREEN
   e. hvigorw assembleHap → BUILD SUCCESSFUL
   f. git log --oneline 验证 7 个原子 commit
4. 推到 origin:git push -u origin feat/llm-settings-cleanup(需 user 明确 "push")
5. gh pr create --base develop --title "feat(entry): LLM 设置页 cleanup(L4+L5+L6)" --body "..."
6. 更新 docs/specs/index.md 状态行
7. 更新 handoff §8 L4/L5 标记 ✅
```

## Out of scope

- **L1+L2+L3 (per-vendor persistence)**:见下方 §"In scope (this PR — 2026-09-08 amend)" — 原 Out of scope,user 2026-09-08 决定纳入本次 implement。
- **UI vs design 5 个偏差**(#20-#24):**反向走** — 用户裁定修复不放本 spec,改走 spec `019-pr2-t2-ui-deviations-fix`(PR1 工作),与 PR2 cleanup 并行
- **B2 4 个 smell 重构**(#9 AddCustomVendorCfg dedup / #10 Repeated Switches / #11-#13 Speculative Generality):独立 spec `020-ai-settings-refactor`,走 PR3(`feat/ai-settings-refactor` 分支)
- **`openAddCustomVendor()` no-op 删除**:与 PR3 B2 重构一起处理
- **`docs/agents/handoffs/` 子目录命名**(`naming-conventions.md` §3.1 登记):meta 任务,不影响功能,可在 B1 命名修正 commit 处理

## In scope (this PR — 2026-09-08 amend)

user 在 PR #87 merge 后,2026-09-08 决定将原 Out-of-scope 的 L1+L2+L3 一并在本 worktree 实现,以"保证整个后端的大模型链路不断":

### L1: per-vendor customVendors 持久化

**问题**:PR2-T2 polish (commit `9ce5195`) 引入 `VendorPicker` add custom vendor modal,`AiSettingsViewModel.addCustomVendor()` 把新 vendor 推到 in-memory `customVendors: CustomVendorFull[]`,**重启 app 即丢失**。

**修复**:
- `LlmConfig.cachedCustomVendors: CustomVendorConfig[]`(扩展自现有 `cachedCustomVendor: CustomVendorConfig | null`,保留单数 legacy 字段向后兼容)
- `KEY_CUSTOM_VENDORS: string` preferences key,JSON 数组
- 新 API:
  - `getCustomVendors(): CustomVendorConfig[]`
  - `setCustomVendors(arr: CustomVendorConfig[]): Promise<void>`
  - `addCustomVendor(cfg: CustomVendorConfig): Promise<void>`
  - `removeCustomVendor(id: string): Promise<void>`
- `getEndpoint() / getModel()` 仍按 vendorId 解析:`vendorId === 'custom'` 时找 customVendors[] 第一个匹配(若多 vendor 都 id='custom',取第一个)
- VM 替换 in-memory `customVendors[]` 为 LlmConfig-backed;`save()` 持久化

### L2: per-vendor models 持久化

**问题**:`VendorPicker.@State models: string[]` 编辑 panel 加 model 是 in-memory,刷新即丢。

**修复**:
- `LlmConfig.cachedVendorModels: Record<string, string[]>`(vendorId → models[])
- `KEY_VENDOR_MODELS: string` preferences key,JSON record
- 新 API:
  - `getVendorModels(vendorId: string): string[]`
  - `addVendorModel(vendorId: string, model: string): Promise<void>`
  - `removeVendorModel(vendorId: string, model: string): Promise<void>`
- 预设 vendor 初始化:首次 load 时如 `cachedVendorModels[vendorId]` 空,seed 1 个 default model(`findProvider(vendorId).defaultModel`)
- VM/VendorPicker:`activeModel` 同步 LlmConfig(从 `getVendorModels(vendorId)` 读)

### L3: per-vendor API Key

**问题**:`LlmConfig.getApiKey()` 单全局 key(via AssetStoreKit alias 'llm_api_key')。Per-vendor key 不支持,用户切换 vendor 时只能复用同一 key。

**修复**(采用单 AssetStoreKit entry + JSON map,简化 vs 多 alias):
- 新增 `KEY_VENDOR_API_KEYS: string` preferences key,JSON record `{ vendorId: key }`
- `LlmConfig.cachedVendorApiKeys: Record<string, string>`
- 新 API:
  - `getApiKey(vendorId?: string): Promise<string | null>` — vendorId 给定且有 key,返回 per-vendor;否则 fallback 全局 key
  - `setApiKey(key: string, vendorId?: string): Promise<void>` — vendorId 给定,写 per-vendor map;否则写全局 AssetStoreKit
  - `clearApiKey(vendorId?: string): Promise<void>` — vendorId 给定,从 map 删;否则清全局
- `LlmClient.callJsonInternal()` 已用 `this.config.getApiKey()`(无 vendorId),改为 `this.config.getApiKey(<current vendor>)` — 需 LlmClient 接 vendorId(新参数)或 LlmConfig 内部 cache 当前 vendorId
- 选择:在 `LlmConfig.getApiKey(vendorId?: string)` 处,若 vendorId 未给,默认用 `cachedVendorId`

### 跨切关注:测试策略

- 全部用 **mock key**(`sk-test-mock-...`),不进任何 commit(也不进 `.env`)
- 真实 API 烟雾测试(用户真机):用 `DEEPSEEK_API_KEY` 环境变量或 DevEco 真机输入(用户后续手动)
- 见 §Acceptance criteria
- **UI vs design 5 个偏差**(#20-#24):**反向走** — 用户裁定修复不放本 spec,改走 spec `019-pr2-t2-ui-deviations-fix`(PR1 工作),与 PR2 cleanup 并行
- **B2 4 个 smell 重构**(#9 AddCustomVendorCfg dedup / #10 Repeated Switches / #11-#13 Speculative Generality):独立 spec `020-ai-settings-refactor`,走 PR3(`feat/ai-settings-refactor` 分支)
- **`openAddCustomVendor()` no-op 删除**:与 PR3 B2 重构一起处理
- **`docs/agents/handoffs/` 子目录命名**(`naming-conventions.md` §3.1 登记):meta 任务,不影响功能,可在 B1 命名修正 commit 处理

## Further notes

### 与 spec 016 的关系

本 spec 是 spec 016 §6.4 公共接口变更 + §8 验收标准 line 241 的**补完**,不是新功能。`docs/specs/index.md` 表格建议加一行:

| Spec | Status |
|---|---|
| **017 / cleanup** | [`017-llm-settings-cleanup.md`](./017-llm-settings-cleanup.md) | (implicit, spec 016 后续) | in progress |

### 与 ticket #9 的关系

Ticket #9 (`009-llm-config-throw-on-silent-override.md`) 已 implemented (2026-09-06, TDD),**只完成了 LlmConfig.normalizeModel / normalizeEndpoint 层的 throw**。本 spec 完成**调用层清理**(VM + page 不再嗅探)。完整 ticket #9 故事 = 本 spec 实现 + spec 016 vendorId 引入 + spec 016 §验收 line 244 "凭据走 AssetStoreKit"(PR2-T1 已完成)。

### ADR 是否需要

domain-modeling 三条件评估:
1. **Hard to reverse**:中等(7 commit 顺序 revert 可恢复)
2. **Surprising without context**:不特别(直接对应 spec 016 验收 line 241)
3. **Real trade-off**:无重大权衡(纯 cleanup)

**结论:不写新 ADR**。如有疑问,引用 spec 016 + ticket #9 spec 即可。

### 真机验收 checklist(本 spec 无新 UI 改动)

复用 handoff §10:
- [ ] 5 vendor 卡片(未改动)
- [ ] AI 服务 summary 文案:`endpointSummary()` 返回当前 vendor 的 baseUrl(由 `getCurrentEndpoint()` 提供)
- [ ] 切 vendor → summary 跟着变(由 `getCurrentEndpoint()` 走 PROVIDERS 解析)
- [ ] API Key 段(全局)仍工作

### 风险评估

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| `syncEndpoint / syncModel` 还有未发现的 caller | 低 | 中 | grep 全仓 + 测试 T1/T2 AST 校验 |
| `endpointSummary()` 旧实现被外部测试依赖 | 低 | 低 | T7 mock 验证新实现 |
| `llm-config-allow-default-model.test.mjs` T6 改源后假绿 | 低 | 中 | 双重断言:`providers.deepseek.defaultModel === LlmConfig.DEFAULT_MODEL` |
| VM 删除 12 个 set 方法后 AiSettingsPage 还有引用 | 低 | 高 | grep `vm\.(set\|toggle\|resolve)` 全仓 |
| git rm 旧文件后 build 报 import 错误 | 中 | 低 | Sub-task 3 先清 page,再 Sub-task 2 清文件;build 跑两遍验证 |

---

**最后更新**: 2026-09-08(grill-with-docs → to-spec Round 1-3 完成)
**作者**: MiniMax-M3(本 session agent)
**给**: implement agent(后续 /implement)
