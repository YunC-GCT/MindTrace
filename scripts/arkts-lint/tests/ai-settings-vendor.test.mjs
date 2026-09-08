// scripts/arkts-lint/tests/ai-settings-vendor.test.mjs
//
// PR2-T2 RED 测试套件: VendorPicker 组件 + ViewModel vendorId/activeModels 字段
// 范围: spec 016 PR2-T2 UI 重构(每加一个测试跑一次,确认 RED 有效)
//
// 1 文件 1 测 1 加 — 慢慢推进,每步可见 feedback

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');

// 测试 1(GREEN): VendorPicker.ets 存在
test('VendorPicker.ets exists at entry/src/main/ets/pages/AiSettings/', () => {
  assert.ok(
    existsSync(resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets')),
    'VendorPicker.ets must be created at entry/src/main/ets/pages/AiSettings/'
  );
});

// 测试 2(RED): 5 预设 vendor 名必须在 VendorPicker 出现
// (硬编码字符串 或 通过 ProviderConfig 列表 import 都可,只要 grep 能找到)
test('VendorPicker declares 5 preset vendor names (DeepSeek/通义千问/智谱GLM/Kimi/豆包)', () => {
  const vpContent = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  for (const name of ['DeepSeek', '通义千问', '智谱 GLM', 'Kimi', '豆包']) {
    assert.ok(
      vpContent.includes(name),
      `VendorPicker must reference preset vendor name "${name}" (hardcoded or via ProviderConfig import)`
    );
  }
});

// 测试 3(RED): VendorPicker 应从 common.PROVIDERS 导入,而非硬编码
// 当前实现硬编码 PRESET_VENDORS 常量,后续 Step 7 改为 import 方式
test('VendorPicker should use common.PROVIDERS import (not hardcoded vendor list)', () => {
  const vpContent = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  assert.ok(
    /from\s*['"]common['"]/.test(vpContent) ||
    /from\s*['"]\.\.\/\.\.\/\.\.\/\.\.\/common\/src\/main\/ets\/llm\/providers['"]/.test(vpContent),
    'VendorPicker must import PROVIDERS via module name "common" or relative path'
  );
  assert.doesNotMatch(
    vpContent,
    /const\s+PRESET_VENDORS\s*:\s*PresetVendor\[\]\s*=/,
    'VendorPicker must NOT hardcode PRESET_VENDORS array(should use common.PROVIDERS)'
  );
});

// 测试 4(回归锁定): VendorPicker 是 @Component 装饰的 exported struct + 公共 API
test('VendorPicker is @Component-decorated exported struct with public API', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  assert.match(vp, /@Component\s*\n\s*export\s+struct\s+VendorPicker/,
    'VendorPicker must be @Component-decorated exported struct');
  // 公共 API 字段(回归锁定 — 防后续重构破坏)
  for (const field of [
    /@Prop\s+currentVendorId\s*:\s*string/,
    /onSelect\s*:\s*\(\s*id\s*:\s*string\s*\)\s*=>\s*void/,
    /onEdit\s*:\s*\(\s*id\s*:\s*string\s*\)\s*=>\s*void/,
  ]) {
    assert.match(vp, field, `VendorPicker must declare ${field}`);
  }
});

// 测试 5(RED): VendorPicker 行可点击触发 onSelect(id)
// v6 设计稿: radio + 文字 + 当前 badge + [编辑] 按钮,整行可点
// 当前 build 没有 onClick,RED 预期
test('VendorPicker row is clickable and triggers onSelect(vendorId)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // Row(或内层点击元素) 上有 .onClick(() => this.onSelect(item.id))
  // 容忍花括号嵌套:[\s\S]*? 跨行非贪婪
  assert.match(
    vp,
    /\.onClick\s*\(\s*\(\s*\)\s*:\s*void\s*=>\s*\{\s*this\.onSelect\(\s*item\.id\s*\)\s*\}/s,
    'VendorPicker Row must have .onClick calling this.onSelect(item.id)'
  );
});

// 测试 6(RED): 当前 vendor row 应有 'current' 视觉 class
// v6 设计稿: current row = 绿底(.current) + 绿左边框 + "当前" badge
test('VendorPicker highlights current vendor row (background switch + 当前活跃 badge)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // .backgroundColor(... ? <any color> : "transparent") — refactored to any mint/dark color literal
  assert.match(
    vp,
    /\.backgroundColor\s*\(\s*(?:item\.id\s*===\s*this\.currentVendorId|this\.currentVendorId\s*===\s*item\.id)\s*\?\s*['"][^'"]*['"]\s*:\s*['"]transparent['"]/,
    'current vendor row must have .backgroundColor(... ? <color> : "transparent") when current'
  );
  // 当前活跃 badge(只在 current 状态显示)
  assert.ok(
    vp.includes('当前活跃'),
    'VendorPicker must show 当前活跃 badge for current vendor'
  );
});

// 测试 7(回归锁定): 编辑 button 仍是公开 API 但实际逻辑由 @State editingVendorId 自管
// v6 设计稿: 编辑 button → 点击 → 展开 panel(panel 状态由 VendorPicker 自管)
// 旧架构曾要求 onClick 调 this.onEdit(item.id)(双真理源);新架构单真理源(onClick 仅 toggle @State)
test('VendorPicker row has 编辑 button (state managed by @State editingVendorId only)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // 按钮文字 "编辑" 出现在 source code
  assert.ok(
    vp.includes('编辑'),
    'VendorPicker must contain 编辑 button text'
  );
  // onEdit 字段作为公开 API 仍存在(默认值 noop 兼容)
  assert.match(
    vp,
    /onEdit\s*:\s*\(\s*id\s*:\s*string\s*\)\s*=>\s*void/,
    'VendorPicker must declare onEdit callback field as public API'
  );
  // 验证架构: 编辑 button.onClick 不应再调 this.onEdit(单真理源)
  // 这是 Test 16 的反向形式(allow 模式)— 已经在 Test 16 严格测过,这里只 sanity check
});

// 测试 8(RED): 列表底部有 [+] 添加新供应商 按钮 + 触发 onAddCustom
// v6 设计稿: 预设 5 行结束后 → 添加新供应商 → 展开 modal(Step 16 写 CustomVendorForm)
test('VendorPicker has 添加新供应商 button triggering onAddCustom', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // 按钮文字 "添加新供应商"
  assert.ok(vp.includes('添加新供应商'), 'VendorPicker must contain 添加新供应商 button text');
  // onClick 调 onAddCustom 回调(允许多行 + 大括号)
  assert.match(
    vp,
    /\.onClick\s*\(\s*\(\s*\)\s*:\s*void\s*=>\s*\{[\s\S]*?onAddCustom\(\s*\)/,
    'VendorPicker must have onClick calling onAddCustom()'
  );
});

// 测试 9(RED): VendorPicker 暴露 onAddCustom 回调
test('VendorPicker declares onAddCustom callback field', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  assert.match(
    vp,
    /onAddCustom\s*:\s*\(\s*\)\s*=>\s*void/,
    'VendorPicker must declare onAddCustom: () => void callback'
  );
});

// 测试 10(RED): 每行左侧有 line+circle radio 视觉
// v6 设计稿: 未选 = 虚线 + 空心圆 / 已选 = 实线 + 实心圆
// 实际真机兼容(2026-09-08 验证): Stack(Line+Circle) 透明背景不渲染 + Row.borderTopWidth 不存在
// 改用纯 Circle — 实心绿=已选 / 空心灰=未选(line 视觉简化掉)
test('VendorPicker row has radio visual (Text dot MINT/TEXT_3 or Circle)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // Text 字符 (● / ○) 或 Circle 组件
  assert.ok(
    vp.includes('●') || vp.includes('○') || /\bCircle\s*\(\s*\)/.test(vp),
    'radio visual must contain Text 字符 ● / ○ or Circle()'
  );
  // color 切换 current=MINT / other=TEXT_3
  assert.ok(
    /fontColor\s*\(\s*this\.currentVendorId\s*===\s*item\.id\s*\?\s*MINT\s*:\s*TEXT_3\s*\)/.test(vp) ||
    /fontColor\s*\(\s*item\.id\s*===\s*this\.currentVendorId\s*\?\s*MINT\s*:\s*TEXT_3\s*\)/.test(vp),
    'radio color must switch MINT (current) / TEXT_3 (other)'
  );
});


// 测试 11(RED): AiSettingsPage 应 import VendorPicker + 删 EndpointPicker/ModelPicker
// v6 设计稿: AI 设置页用 VendorPicker 替代 EndpointPicker + ModelPicker
test('AiSettingsPage imports VendorPicker and does NOT import EndpointPicker/ModelPicker', () => {
  const aiPage = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets'),
    'utf8'
  );
  // 必须 import VendorPicker
  assert.match(
    aiPage,
    /import\s+\{\s*VendorPicker\s*\}\s+from\s+['"]\.\/VendorPicker['"]/,
    'AiSettingsPage must import VendorPicker from ./VendorPicker'
  );
  // 不能 import EndpointPicker 或 ModelPicker
  assert.doesNotMatch(
    aiPage,
    /import\s+\{\s*EndpointPicker\s*\}/,
    'AiSettingsPage must NOT import EndpointPicker anymore (replaced by VendorPicker)'
  );
  assert.doesNotMatch(
    aiPage,
    /import\s+\{\s*ModelPicker\s*\}/,
    'AiSettingsPage must NOT import ModelPicker anymore (replaced by VendorPicker)'
  );
});

// 测试 12: AiSettingsViewModel 必须有 vendorId 字段 + selectVendor/openAddCustomVendor 方法(无 toggleEditPanel)
// v6 设计稿: ViewModel 暴露业务状态 vendorId 给 AiSettingsPage
// 架构修正(2026-09-08): panel 展开是纯 UI 状态,不由 ViewModel 管(单真理源)
test('AiSettingsViewModel exposes vendor business state and vendor callbacks (no toggleEditPanel)', () => {
  const vm = readFileSync(
    resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'),
    'utf8'
  );
  // 字段 vendorId
  assert.match(
    vm,
    /vendorId\s*:\s*string\s*=\s*['"]deepseek['"]/,
    'AiSettingsViewModel must declare vendorId field default "deepseek"'
  );
  // 方法 selectVendor(id)
  assert.match(
    vm,
    /selectVendor\s*\(\s*id\s*:\s*string\s*\)\s*:\s*void/,
    'AiSettingsViewModel must declare selectVendor(id: string): void method'
  );
  // 方法 openAddCustomVendor()
  assert.match(
    vm,
    /openAddCustomVendor\s*\(\s*\)\s*:\s*void/,
    'AiSettingsViewModel must declare openAddCustomVendor(): void method'
  );
  // 回归锁定: 不应再有 toggleEditPanel(已挪到 VendorPicker 自管)
  assert.doesNotMatch(
    vm,
    /toggleEditPanel\s*\(\s*id\s*:\s*string\s*\)\s*:\s*void/,
    'AiSettingsViewModel must NOT have toggleEditPanel (architecture single source of truth)'
  );
});

// 测试 13(RED): vm.save() 必须持久化 vendorId 到 LlmConfig
// v6 设计稿: 切换 vendor 后保存,刷新页面不应丢失
test('AiSettingsViewModel.save() persists vendorId to LlmConfig', () => {
  const vm = readFileSync(
    resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'),
    'utf8'
  );
  // save() 方法体内必须有 llm.setVendorId(this.vendorId)
  // 跨行匹配 — 整个 save 函数体内
  const saveMatch = vm.match(/async\s+save\s*\(\s*\)\s*:\s*Promise\s*<\s*boolean\s*>\s*\{([\s\S]*?)\n\s*\}\s*\n/);
  assert.ok(saveMatch !== null, 'save() method must exist');
  const saveBody = saveMatch[1];
  assert.match(
    saveBody,
    /llm\.setVendorId\s*\(\s*this\.vendorId\s*\)/,
    'vm.save() must call LlmConfig.setVendorId(this.vendorId) to persist vendor choice'
  );
});

// 测试 14(RED): VendorPicker 必须有 editingVendorId @State 字段 + 条件渲染 panel
// v6 设计稿: 点击 [编辑] 展开 panel(API Key + 模型目录 + 添加模型)
test('VendorPicker has @State editingVendorId field for edit panel toggle', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // 必须有 @State editingVendorId 字段(默认 null)
  assert.match(
    vp,
    /@State\s+editingVendorId\s*:\s*string\s*\|\s*null\s*=\s*null/,
    'VendorPicker must declare @State editingVendorId: string | null = null'
  );
});

// 测试 15(RED): ViewModel 不应有 toggleEditPanel 方法 / editPanelOpen 字段
// 架构决策: panel 展开是 VendorPicker 内部 UI 状态,不由 ViewModel 管
// (避免双真理源: VendorPicker.@State editingVendorId 与 ViewModel.editPanelOpen 同时存在导致同步问题)
test('AiSettingsViewModel does NOT have toggleEditPanel method or editPanelOpen field (architecture: single source of truth in VendorPicker)', () => {
  const vm = readFileSync(
    resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'),
    'utf8'
  );
  assert.doesNotMatch(
    vm,
    /toggleEditPanel\s*\(\s*id\s*:\s*string\s*\)\s*:\s*void/,
    'AiSettingsViewModel must NOT have toggleEditPanel method (panel state belongs to VendorPicker)'
  );
  assert.doesNotMatch(
    vm,
    /editPanelOpen\s*:/,
    'AiSettingsViewModel must NOT have editPanelOpen field (panel state belongs to VendorPicker)'
  );
});

// 测试 16(RED): VendorPicker 编辑 button 必须自管 editingVendorId,不通知外部
// (双真理源反例:既 toggle @State 又调 onEdit 让外部 toggle)
test('VendorPicker 编辑 button only toggles @State editingVendorId (single source of truth)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // 编辑 text 必须在 source 中
  assert.ok(vp.includes('编辑'), 'VendorPicker must contain 编辑 text');
  // 编辑 text.onClick lambda 内调 this.editingVendorId
  const onClickMatch = vp.match(/Text\(\s*['"]编辑['"]\s*\)[\s\S]*?\.onClick\s*\(\s*\(\s*\)\s*:\s*void\s*=>\s*\{([\s\S]*?)\}/);
  assert.ok(onClickMatch !== null, '编辑 Text.onClick lambda must exist');
  const body = onClickMatch[1];
  assert.match(body, /this\.editingVendorId\s*=/, '编辑 onClick must assign editingVendorId');
  assert.doesNotMatch(body, /this\.onEdit\s*\(/, '编辑 onClick must NOT call onEdit');
});


// 测试 17(RED): 编辑 panel 必须包含 API Key TextInput + 模型目录 + 添加 model
// v6 设计稿: 点 [编辑] 展开 panel 含: API Key field + 模型目录列表 + + 添加 model
test('VendorPicker 编辑 panel contains API Key TextInput + model directory + add model', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // 找到 if (this.editingVendorId === item.id) { ... } 块(panel)
  // 用 if 块起点 + source file 后续剩余内容,取起点后所有内容作为 panel 区域
  const startIdx = vp.search(/if\s*\(\s*this\.editingVendorId\s*===\s*item\.id\s*\)\s*\{/);
  assert.ok(startIdx >= 0, 'VendorPicker edit panel must start with if (this.editingVendorId === item.id)');
  // 从 if 起点到 file 末尾为"panel 后"内容(嵌套 } 让非贪婪提前停 — 用宽度代替)
  const panelRegion = vp.substring(startIdx);

  // 1. API Key TextInput
  assert.match(panelRegion, /TextInput\s*\(/, 'panel must contain TextInput (API Key field)');
  // 2. 模型目录 — 必须有 ForEach 渲染 model list
  assert.match(panelRegion, /ForEach\s*\(\s*this\.models/, 'panel must contain ForEach (this.models) (model directory list)');
  // 3. 添加 model 输入 + 字符串 '添加' 标识
  assert.match(panelRegion, /TextInput/, 'panel must contain TextInput (添加 model input)');
  assert.ok(
    panelRegion.includes('添加') || panelRegion.includes('+'),
    'panel must have 添加 button or + symbol for adding model'
  );
});

// 测试 18(RED): VendorPicker 必须有 models 状态字段(per-vendor model 列表)
// 单真理源: panel 内部 model 状态由 VendorPicker 管(不污染 ViewModel)
test('VendorPicker has @State models field for panel model directory', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  assert.match(
    vp,
    /@State\s+models\s*:\s*string\s*\[\s*\]\s*=/,
    'VendorPicker must declare @State models: string[] = [] (per-vendor model list)'
  );
  assert.match(
    vp,
    /@State\s+activeModel\s*:\s*string\s*=\s*/,
    'VendorPicker must declare @State activeModel: string (currently active model for the editing vendor)'
  );
});

// 测试 19(RED): vm.load() 必须调 llm.getVendorId() 还原 vendorId(关闭 C1 critical)
// C1: save() 持久化 vendorId,但 load() 没读,刷新页面 vendor 选择回到默认值 'deepseek'
test('AiSettingsViewModel.load() restores vendorId from LlmConfig', () => {
  const vm = readFileSync(
    resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'),
    'utf8'
  );
  // 找 load() 函数体 — 鉴于嵌套 try/catch 的 } 干扰,用 width 截取
  const loadStart = vm.search(/async\s+load\s*\(\s*\)\s*:\s*Promise\s*<\s*boolean\s*>\s*\{/);
  assert.ok(loadStart >= 0, 'load() method must exist');
  const fromLoad = vm.substring(loadStart);
  // 取到下一个 "return ok" 之前的 body
  const returnIdx = fromLoad.indexOf('return ok');
  assert.ok(returnIdx >= 0, 'load() must have return ok statement');
  const loadBody = fromLoad.substring(0, returnIdx);
  assert.match(
    loadBody,
    /this\.vendorId\s*=\s*llm\.getVendorId\s*\(\s*\)/,
    'vm.load() must call llm.getVendorId() to restore vendor choice (C1 critical bug fix)'
  );
});

// 测试 20(RED): VendorPicker 文件头必须用 /** */ JSDoc 格式(file-header-template.md 要求)
// hard violation: 当前文件用 // line comments,不是模板要求的 JSDoc
test('VendorPicker.ets file header uses /** */ JSDoc block (file-header-template.md)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // 文件头第一行必须是 /**
  assert.match(
    vp,
    /^\s*\/\*\*\s*$/m,
    'VendorPicker file header must start with /** (JSDoc block per file-header-template.md)'
  );
  // 必须有 */ 结束(至少一处)
  assert.match(
    vp,
    /\*\//,
    'VendorPicker file header must contain */ (JSDoc block end)'
  );
  // 必须有 9 字段关键词
  assert.match(vp, /FileName|文件名/, 'must mention FileName / 文件名');
  assert.match(vp, /路径/, 'must mention 路径');
  assert.match(vp, /职责/, 'must mention 职责');
  assert.match(vp, /依赖/, 'must mention 依赖');
  assert.match(vp, /数据流/, 'must mention 数据流');
  assert.match(vp, /ArkTS 1\.1/, 'must mention ArkTS 1.1 strict');
});

// 测试 21(RED): VendorPicker 不应有未消费的 customName/customBaseUrl/customModel @Prop(Speculative Generality smell)
// 这些 @Prop 已声明但 build() 内从未读取 — 删除直到 custom vendor form 接入
test('VendorPicker does NOT declare unused customName/customBaseUrl/customModel @Props', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  assert.doesNotMatch(
    vp,
    /@Prop\s+customName\s*:/,
    'VendorPicker must NOT declare customName @Prop (Speculative Generality: not consumed)'
  );
  assert.doesNotMatch(
    vp,
    /@Prop\s+customBaseUrl\s*:/,
    'VendorPicker must NOT declare customBaseUrl @Prop (Speculative Generality: not consumed)'
  );
  assert.doesNotMatch(
    vp,
    /@Prop\s+customModel\s*:/,
    'VendorPicker must NOT declare customModel @Prop (Speculative Generality: not consumed)'
  );
});

// 测试 22(RED): AiSettingsViewModel 有 customVendors 字段 + addCustomVendor 方法
// v6 设计稿 PR2-T2 P3: 用户点 [+ 添加新供应商] 弹 modal,填 4 字段(name/baseUrl/apiKey/firstModel),保存
test('AiSettingsViewModel exposes customVendors list and addCustomVendor method', () => {
  const vm = readFileSync(
    resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'),
    'utf8'
  );
  // customVendors: CustomVendorFull[] 字段(ai-settings-vendor 完整结构含 id + apiKey)
  assert.match(
    vm,
    /customVendors\s*:\s*CustomVendor(?:Full)?\s*\[\s*\]\s*=\s*\[\s*\]/,
    'AiSettingsViewModel must declare customVendors: CustomVendorFull[] = [] field'
  );
  // addCustomVendor(name, baseUrl, apiKey, firstModel) 方法
  assert.match(
    vm,
    /addCustomVendor\s*\(\s*name\s*:\s*string\s*,\s*baseUrl\s*:\s*string\s*,\s*apiKey\s*:\s*string\s*,\s*firstModel\s*:\s*string\s*\)\s*:\s*void/,
    'AiSettingsViewModel must declare addCustomVendor(name, baseUrl, apiKey, firstModel): void method'
  );
});

// 测试 23(RED): VendorPicker 有 addCustomModalOpen @State + 4 个 @State newVendorXxx 字段
// modal 状态由 VendorPicker 自管(单真理源 — modal 是纯 UI 状态)
test('VendorPicker has @State addCustomModalOpen + 4 newVendor input fields for modal', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // addCustomModalOpen @State
  assert.match(
    vp,
    /@State\s+addCustomModalOpen\s*:\s*boolean\s*=\s*false/,
    'VendorPicker must declare @State addCustomModalOpen: boolean = false'
  );
  // 4 个 newVendorXxx @State
  assert.match(vp, /@State\s+newVendorName\s*:/, 'newVendorName @State required');
  assert.match(vp, /@State\s+newVendorBaseUrl\s*:/, 'newVendorBaseUrl @State required');
  assert.match(vp, /@State\s+newVendorApiKey\s*:/, 'newVendorApiKey @State required');
  assert.match(vp, /@State\s+newVendorModel\s*:/, 'newVendorModel @State required');
});

// 测试 24(RED): VendorPicker 有 onAddVendorConfirm callback 字段
// VendorPicker 内 modal 完成后通知 ViewModel 接收新 vendor
test('VendorPicker declares onAddVendorConfirm callback for adding custom vendor', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // callback 必须存在(ArkTS 1.1 强制 interface,不 inline object literal)
  assert.match(
    vp,
    /onAddVendorConfirm\s*:\s*\(\s*cfg\s*:\s*AddCustomVendorCfg\s*\)/,
    'VendorPicker must declare onAddVendorConfirm(cfg: AddCustomVendorCfg) callback'
  );
});

// 测试 25(RED): VendorPicker 有 renderAddCustomModal @Builder + 4 TextInput + Stack overlay
// v6 设计稿: modal 含 4 字段 + 确认/取消按钮
test('VendorPicker has @Builder renderAddCustomModal with 4 TextInputs and Stack overlay', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  assert.match(vp, /@Builder\s+renderAddCustomModal\s*\(\s*\)\s*\{/, 'must declare @Builder renderAddCustomModal()');
  // builder body 内必须 Stack
  const buildStart = vp.search(/@Builder\s+renderAddCustomModal\s*\(\s*\)\s*\{/);
  const builderBody = vp.substring(buildStart, buildStart + 5000);
  assert.match(builderBody, /Stack\s*\(\s*\)/, 'modal builder must use Stack() overlay');
});


// 测试 26(RED): AiSettingsPage 必须用 vm.vendorId 直接解析 vendor 摘要(替代旧 modelSummary/endpointSummary)
// 当前 bug: line 114 用 vm.modelSummary() + vm.endpointSummary() 显示"DeepSeek-V4-Pro · DeepSeek 官方"
// 设计稿: "DeepSeek · 当前 deepseek-v4-pro · https://api.deepseek.com"
test('AiSettingsPage uses vm.vendorId + vm.activeModel for AI 服务 summary (not legacy modelSummary/endpointSummary)', () => {
  const aiPage = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets'),
    'utf8'
  );
  // 必须直接引用 vendorId (不是 modelSummary/endpointSummary)
  assert.match(
    aiPage,
    /this\.vm\.vendorId/,
    'AiSettingsPage must use vm.vendorId directly for AI service summary (vendor-aware resolution)'
  );
  assert.doesNotMatch(
    aiPage,
    /this\.vm\.modelSummary\s*\(\s*\)/,
    'AiSettingsPage must NOT call vm.modelSummary() (legacy keyword-sniffing method)'
  );
  assert.doesNotMatch(
    aiPage,
    /this\.vm\.endpointSummary\s*\(\s*\)/,
    'AiSettingsPage must NOT call vm.endpointSummary() (legacy keyword-sniffing method)'
  );
});

// 测试 27(RED): AiSettingsViewModel 必须暴露 getCurrentVendor() / getCurrentModel() 方法
// (替代旧 modelSummary/endpointSummary 的关键字嗅探)
// 设计稿: AI 服务段显示 vendor 名 + 当前 model + baseUrl
test('AiSettingsViewModel exposes getCurrentVendor() and getCurrentModel() for AI service summary', () => {
  const vm = readFileSync(
    resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets'),
    'utf8'
  );
  // getCurrentVendor(): string (返回 vendor 显示名 — provider.vendorName 或 customVendor.vendorName)
  assert.match(
    vm,
    /getCurrentVendor\s*\(\s*\)\s*:\s*string/,
    'AiSettingsViewModel must declare getCurrentVendor(): string method'
  );
  // getCurrentModel(): string (返回当前 model 名)
  assert.match(
    vm,
    /getCurrentModel\s*\(\s*\)\s*:\s*string/,
    'AiSettingsViewModel must declare getCurrentModel(): string method'
  );
  // getCurrentEndpoint(): string (返回当前 endpoint)
  assert.match(
    vm,
    /getCurrentEndpoint\s*\(\s*\)\s*:\s*string/,
    'AiSettingsViewModel must declare getCurrentEndpoint(): string method'
  );
});

// 测试 28(GREEN): "当前" badge 视觉必须真正是 filled pill(背景色 + 白字 + 圆角 3),不是 outline 描边
// v6 设计稿(.pr2-t2-design.html css 123-126): current-badge = success bg + white + border-radius 3
// 修订:PR2-T2 polish ticket #81 task A1,从 outline mint 描边 → filled MINT bg + 白字
test('VendorPicker 当前活跃 badge has filled MINT backgroundColor + #FFFFFF fontColor (v6 design)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  assert.ok(vp.includes('当前活跃'), 'VendorPicker must contain 当前活跃 badge text');
  const idx = vp.indexOf('当前活跃');
  const region = vp.substring(Math.max(0, idx - 250), idx + 500);
  assert.match(region, /backgroundColor\s*\(\s*MINT\s*\)/, '当前活跃 must have backgroundColor(MINT) for filled pill');
  assert.match(region, /fontColor\s*\(\s*['"]#FFFFFF['"]\s*\)/, '当前活跃 must have fontColor(\'#FFFFFF\') for white text on filled bg');
  assert.match(region, /borderRadius\s*\(\s*3\s*\)/, '当前活跃 must have borderRadius(3) per v6 design');
});



// 测试 29(RED): vendor 行左侧必须有 line+circle radio 视觉(real-device renderable)
// ArkUI 真机 Stack(Line+Circle) 透明背景不渲染,换用 Row border + Unicode dot 兜底
test('VendorPicker row has line+circle radio visual (Stack OR Circle OR border)', () => {
  const vp = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/VendorPicker.ets'),
    'utf8'
  );
  // 整段 build 内必须有视觉切换
  assert.ok(
    /\bStack\s*\(\s*\)/.test(vp) ||
    /\bCircle\s*\(\s*\)/.test(vp) ||
    /borderTop/i.test(vp),
    'VendorPicker must have visual switch (Stack/Circle/border)'
  );
});

// 测试 30(GREEN): AI 服务段加圆环 icon(外环 + 内点)
// v6 设计稿(.pr2-t2-design.html line 402-407):<svg><circle r=9/><circle r=3.5/></svg>
// ArkTS 实现:Stack 内 2 Circle,外环 stroke MINT + 内点 fill MINT
// PR2-T2 polish ticket #81 task A2
test('AiSettingsPage AI 服务段 has ring icon (Stack with 2 Circles for outer ring + inner dot)', () => {
  const page = readFileSync(
    resolve(root, 'entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets'),
    'utf8'
  );
  // 找 AI 服务 title 上下文(±600 字符)
  assert.ok(page.includes('AI 服务'), 'AiSettingsPage must contain AI 服务 title');
  const idx = page.indexOf('AI 服务');
  const region = page.substring(Math.max(0, idx - 600), idx + 200);
  // 必须有 Stack + 至少 2 Circle(外环 + 内点)
  assert.match(region, /Stack\s*\(\s*\)/, 'AI 服务 title region must contain Stack() for ring icon');
  const circleCount = (region.match(/\bCircle\s*\(\s*\)/g) || []).length;
  assert.ok(circleCount >= 2, `AI 服务 title region must contain at least 2 Circle() (outer + inner), found ${circleCount}`);
  // 外环 stroke MINT
  assert.match(region, /\.stroke\s*\(\s*MINT\s*\)/, 'Outer ring must have stroke(MINT)');
  // 内点 fill MINT
  assert.match(region, /\.fill\s*\(\s*MINT\s*\)/, 'Inner dot must have fill(MINT)');
});
