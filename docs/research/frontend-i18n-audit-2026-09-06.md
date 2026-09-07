# 前端国际化 (i18n) 与文案一致性摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 全 UI 文案硬编码程度 / 中英文一致性 / 本地化框架存在性 / 错误提示风格统一性
> **方法**: grep 中文字面量 + showToast 文案 + resources/ 目录 + i18n 框架引用, 全机提取
> **配套**: [`frontend-error-handling-2026-09-06.md`](./frontend-error-handling-2026-09-06.md) (本档是其 i18n/文案子面) · [`frontend-interaction-states-2026-09-06.md`](./frontend-interaction-states-2026-09-06.md)

---

**TL;DR:** **i18n 框架零使用**, 文案 100% 硬编码在 .ets 文件中 (Text("…") 70 处 + promptAction.showToast message 25+ 处); 中英文**直接混杂**在同一处出现 — 失败提示 25 条里有 5 条英文 ("Failed" / "Delete failed" / "Note deleted" / "Failed to load notes" / "搜索功能开发中"), 其余中文; resources/string.json 仅 5 条权限文案, 没分 en/ 等多语言子目录, dark/ 目录是深色模式而非 i18n; **错误提示风格不一** (10-12 字随机长度 / "失败" 与 "Failed" 混用 / 中英混杂无规则), 评委走查会撞上。

---

## 1. i18n 现状硬数据

| 指标 | 数值 | 备注 |
|---|---|---|
| `Text("…")` 含中文字面量 | 70+ | entry 模块 |
| `promptAction.showToast({ message })` 文案 | 25+ | 风格混乱 (见 §4) |
| `resources/base/element/string.json` 条目 | 5 | 仅权限文案 (module_desc, EntryAbility_*, camera_reason, internet_reason) |
| 多语言目录 (`en/` / `zh-rCN/` / `zh-rTW/`) | **0** | 未建立 |
| `@ohos.i18n` 引用 | **0** | 框架未使用 |
| `Intl.NumberFormat` / `Intl.DateTimeFormat` | **0** | 数字/日期本地化未做 |
| `Date.now()` 在 UI 展示 | 多处 | 散落 hard-coded, 未走本地化 |
| `dark/` 目录 | 存在 | ⚠ 不是 i18n, 是深色资源 (color.json / float.json) |

**结论**: 项目当前**无任何 i18n 机制**, 不支持多语言, 评委若用英文 demo 或现场看中文 + 英文混杂的 Toast, 会有明显粗糙感。

---

## 2. 文案硬编码分类

### 2.1 文本展示 (Text() 70 处) — 影响可见
- 页面标题、Tab 名、按钮文案、空态提示、Tab 名称
- 全部中文, 散落 pages/ / overlays/ 96 文件中
- 改文案需 grep 全仓, **无中心注册**

### 2.2 提示消息 (showToast 25+ 处) — 影响最大
- 错误提示、加载成功、保存成功、操作成功
- 中英文混杂 (见 §3)
- 风格长度不一 (见 §4)

### 2.3 长篇文案 (Comments / DocStrings)
- 文件头、@Builder 内说明、// 注释
- 这些不展示给用户, 不影响 i18n

### 2.4 AI 提示词 (PromptBuilder.ets)
- 这是发给 LLM 的, 不是用户文案, 单独评估

---

## 3. 中英文混杂分析 (25 条 showToast)

| 文案 | 语言 | 长度 | 风格评 |
|---|---|---|---|
| "Failed to load notes" | 英 | 20 字 | ✗ 与其他不统一 |
| "Note deleted" | 英 | 12 字 | ✗ |
| "Delete failed" | 英 | 13 字 | ✗ |
| "搜索功能开发中" | 中 | 8 字 | ⚠ 与 "Failed" 同位置 |
| "笔记加载失败" | 中 | 6 字 | ✓ 简短 |
| "复习数据加载失败" | 中 | 8 字 | ✓ |
| "知识星系加载失败" | 中 | 8 字 | ✓ |
| "删除笔记失败" | 中 | 6 字 | ✓ |
| "已删除笔记" | 中 | 5 字 | ✓ |
| "已删除计划" | 中 | 5 字 | ✓ |
| "已加入实时队列" | 中 | 7 字 | ✓ |
| "已移回复习队列" | 中 | 7 字 | ✓ |
| "已移至实时队列顶部" | 中 | 9 字 | ✓ |
| "请先输入 API Key" | 中 | 8 字 (中英混) | △ |
| "请输入复习计划" | 中 | 7 字 | ✓ |
| "请输入标题" | 中 | 5 字 | ✓ |
| "配置加载失败" | 中 | 6 字 | ✓ |
| "重置失败" | 中 | 4 字 | ✓ |
| "AI 正在回复中..." | 中英 | 8 字 | △ |
| "保存失败：" | 中 | 5 字 (含冒号) | △ 风格不一致 |
| "分享功能暂未开放" | 中 | 9 字 | ✓ |
| "摘要和正文至少填写一项" | 中 | 11 字 | ✓ |
| "笔记仍在加载" | 中 | 6 字 | ✓ |
| "将返回登录页, 随后可选择其他账号。" | 中 | 18 字 | ✓ 长 |
| "退出后可再次使用华为账号登录。" | 中 | 16 字 | ✓ 长 |

**问题分级**:
- ✗ **3-4 条英文**: Failed to load notes / Note deleted / Delete failed — 明显是早期提交后未统一
- △ **冒号 / 省略号**: "保存失败：" / "AI 正在回复中..." — 标点不统一
- △ **混合专有名词**: "请先输入 API Key" / "AI" — 专有名词中英混排可接受但应规则化

---

## 4. 文案风格规范缺口

缺一份**文案 style guide**, 应规定:

### 4.1 长度规范
- 短消息 (Toast): 4-10 字为佳, 最长不超过 14 字 (含标点)
- 中消息 (空态): 12-20 字
- 长消息 (说明文案): 不限, 但需分段落

### 4.2 语气规范
- 第二人称 ("请输入..." / "你可以...") vs 被动 ("请先输入")
- 当前混合: "请输入标题" / "摘要和正文至少填写一项" / "笔记仍在加载" — 应统一第二人称

### 4.3 标点规范
- 句号: 全句末尾是否需要 (短 Toast 通常不带, 长说明需要)
- 冒号: "保存失败：" (带冒号) vs "保存失败" (不带) — 不统一
- 省略号: "AI 正在回复中..." (Toast) vs 用户进度 (loading spinner) — 二选一

### 4.4 失败/成功语义
- 失败模板: `[动作]失败` / `[动作]失败:[原因]` / `Failed to [动作]`
- 成功模板: `已[动作]` / `[动作]成功`
- 当前 "已删除笔记" / "笔记加载失败" — 动词在前/后不统一

---

## 5. 本地化框架存在性

### 5.1 resources 目录
```
resources/
├── base/
│   ├── element/        ← string.json (5 条)
│   ├── media/          ← 图标
│   └── profile/        ← main_pages.json
├── dark/               ← 深色资源 (color.json / float.json)
└── rawfile/katex/      ← KaTeX 离线渲染资源
```

**关键缺口**:
- 无 `en/element/string.json` (英语)
- 无 `zh-rCN/`, `zh-rTW/`, `ja/`, etc.
- 即使要 i18n, 也只是把 base/ 的 string.json 复制到 en/, zh-rCN/ 后翻译

### 5.2 ArkUI i18n 能力 (HK API 24)
- `@ohos.i18n` 模块存在 (Locale, DateTimeFormat, NumberFormat)
- `ResourceManager.getStringSync(context, $r('app.string.xxx').id)` API 可用
- 项目零引用

### 5.3 当前 string.json 用法 (5 条)
```json
{ "name": "module_desc", "value": "module description" },
{ "name": "EntryAbility_desc", "value": "description" },
{ "name": "EntryAbility_label", "value": "MindTrace" },
{ "name": "camera_reason", "value": "用于拍照识别数学题目" },
{ "name": "internet_reason", "value": "用于访问AI服务进行题目分析" }
```
仅用于 module.json5 权限声明, 未在 UI 中通过 `$r('app.string.xxx')` 调用。

---

## 6. 评级

| 维度 | 评 | 备注 |
|---|---|---|
| i18n 框架 | ✗ | 完全无 |
| 多语言支持 | ✗ | 单语言 (中文) |
| 文案风格统一 | ✗ | 中英混杂, 长度不一 |
| 文案集中管理 | ✗ | 散落 96 文件 |
| 错误提示规范 | ✗ | 见 frontend-error-handling |
| 日期/数字本地化 | ✗ | Date.now() 直接用 |
| 占位符 (i18n 兼容性) | ✗ | 硬编码字符串无法插值 |

---

## 7. 应有但缺的结构

### 7.1 I18nStrings 中心 (建议)
```typescript
// common/.../i18n/Strings.ets
export class Strings {
  static loadFailedNotes(): string  // 集中管理
  static noteDeleted(): string
  static searchComing(): string
  static apiKeyRequired(): string
  // ...
}
// 后续加 getString() wrapper 走 ResourceManager
```

### 7.2 Toast 文案模板 (建议)
```
[动作]+[状态]: 动作=加载笔记/删除笔记/保存/..., 状态=成功/失败/进行中
成功: 已[动作] (例: 已删除笔记)
失败: [动作]+失败 (例: 笔记加载失败)  // 不带冒号
进行中: [动作]+中... (例: AI 正在回复中...)
```

### 7.3 错误提示分级 (与 ErrorBus 配合, 见 frontend-error-handling)
- info: 蓝色, 短提示 (1.5s)
- warn: 琥珀色, 含操作建议 (3s)
- error: 红色, 含"重试"按钮 (不自动消失)

### 7.4 评审前最低修复 (建议做)
1. **统一 3-4 条英文 Toast → 中文** (5 分钟)
2. **去掉 "保存失败：" 末尾冒号** (5 分钟)
3. **抽出最常用的 10 条 toast 到 I18nStrings** (半小时)
4. **错误提示改成 ErrorBus + ErrorBanner** (参考 frontend-error-handling §6)

---

## 8. 待补充资料

§5/§6/§7/§8/§9/§10/§11 不变, 新增:
12. **真机演示是否需要英文版**: 若评委来自海外或现场要求英文, i18n 是必修; 若仅中文 demo, 第 7.4 节"评审前最低修复"足够
13. **是否计划长期 i18n**: 若只是中文 demo, 抽出 I18nStrings 即可; 若计划双语, 必须先建 en/ 目录骨架

---

## Last updated

2026-09-06 晚
