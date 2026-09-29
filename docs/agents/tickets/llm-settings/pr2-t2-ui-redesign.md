# PR2-T2 — feat(entry): AiSettings 页 UI 重构,引入 VendorPicker + CustomVendorForm

> **分支**:`bugfix/llm-config-audit-2026-09-06`
> **Spec**:[016](../specs/016-llm-settings-redesign.md)
> **源 ADR**:[0013](../adr/0013-llm-provider-presets.md)
> **依赖**:PR2-T1(provider 预设必须先有)
> **工作量**:2 新建 + 5 修改 + ViewModel 改造 + OCR 完全不动
> **风险**:中(UI 重组,需仔细保留 OCR)
> **顺序**:第 4 个 PR

## 为什么

详见 spec 016 §背景 + §目标。

## 改动

### 新建

- `entry/src/main/ets/pages/AiSettings/VendorPicker.ets` — 5 厂商 Radio + "自定义" 选项
- `entry/src/main/ets/pages/AiSettings/CustomVendorForm.ets` — vendor name / baseUrl / model / apiKey 输入

### 修改

- `entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets` — 重组:
  - 移除 `EndpointPicker`(被 `VendorPicker` 包含)
  - 调整 `ModelPicker` 位置(在 `VendorPicker` 之下)
  - 新增 `VendorPicker`(在 endpoint 区块位置)
  - 新增 `CustomVendorForm`(条件渲染,`vendorId === 'custom'` 时显示)
  - **OCR 区块完全不动**,import 保留
- `entry/src/main/ets/pages/AiSettings/ModelPicker.ets` — `PRO_MODEL = "deepseek-chat"`(PR0 已改,这里仅确认)
- `entry/src/main/ets/viewmodels/AiSettingsViewModel.ets`:
  - **删除** `syncEndpoint / syncModel`(违反 ticket #9 精神)
  - 新增 `vendorId / customVendor` 字段
  - 新增 `setVendorId / setCustomVendor` 方法
  - **OCR 字段完全不动**(`ocrEndpoint / ocrEnabled / ocrMode / ocrStatusText / ocrTesting / testOcr / resetOcrEndpoint`)

### 不动(用户保留 / OCR / 其他展示组件)

- `entry/src/main/ets/pages/AiSettings/OcrConfigSection.ets` — 用户后续剥离
- `entry/src/main/ets/pages/AiSettings/ConnectionStatus.ets`
- `entry/src/main/ets/pages/AiSettings/ActionBar.ets`
- `entry/src/main/ets/pages/AiSettings/PageHeader.ets`
- `entry/src/main/ets/pages/AiSettings/KeyInput.ets`

## 测试计划(TDD + 端到端)

单元测试:
1. `ai-settings-vm.test.mjs`:`vm.load()` 后 `vendorId === 'deepseek'`(默认)
2. `ai-settings-vm.test.mjs`:`vm.setVendorId('tongyi')` 后 `endpointLabel()` 显示通义
3. `ai-settings-vm.test.mjs`:`vendorId === 'custom'` 时 `customVendor` 字段生效
4. `ai-settings-vm.test.mjs`:**无** `syncEndpoint / syncModel` 方法(AST 验证,符合 ticket #9 精神)

端到端(Q10=A,用户真跑):
1. 选 DeepSeek → 填真实 key → "测试连接" → 返回 "已配置 / 连接正常"
2. 选通义 → 填通义 key → "测试连接" → 通
3. 选 "自定义" → 填 4 字段(自定义 baseUrl / model / key)→ 测试连接 → 通

## 验收

- [ ] 4 个 ViewModel 单元测试通过
- [ ] 现有所有 arkts-lint 测试通过
- [ ] **端到端冒烟通过(Q10=A)**:DeepSeek + 通义 + 自定义 三场景真跑通
- [ ] 视觉风格:沿用 dark + MINT(Q9=A);无 rgba 字面量绕过 ColorTokens
- [ ] 文件头 9 字段注释(spec 012 + `docs/agents/file-header-template.md`):新增 2 组件 + 修改的 5 文件全部补齐
- [ ] **OCR 区块完全不动**:import + UI 位置 + ViewModel OCR 字段不变

## 回滚

`git revert` 后旧 UI 回来(EndpointPicker + 旧 ModelPicker);ViewModel 旧字段回到;vendor 字段是 PR2-T1 的,revert PR2-T2 不影响 T1。

## 最后更新

2026-09-06