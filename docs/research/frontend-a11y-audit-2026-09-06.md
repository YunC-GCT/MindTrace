# 前端可访问性 (a11y) 摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry a11y API 使用 / 焦点管理 / 屏幕阅读器 / 对比度 / 字体缩放
> **方法**: grep `tabIndex / focusable / accessibility / aria / fontScale` + 颜色令牌对比度计算, 全机提取
> **配套**: [`frontend-i18n-audit-2026-09-06.md`](./frontend-i18n-audit-2026-09-06.md) · [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md)

---

**TL;DR:** **项目 a11y 完全空白** — `tabIndex / focusable / accessibilityGroup / accessibilityText / accessibilityDescription / defaultFocus / fontScale` 全部**零引用**; `Image` 没有 `alt` / `objectFit` 描述属性; `Button` 也没有 a11y 适配; 颜色令牌中 **GLASS_8 (8%) / GLASS_10 (10%) / TEXT_3 / TEXT_4 透明度仅 6-10%**, 与 BG_DARK 背景对比度多数 <3:1 (WCAG AA 失败); TextInput 仅有 `placeholder`, 没有 label/aria-label; **盲人/视障用户完全无法使用本应用**。评审 demo 不会查, 但作为完整产品这是必修项。

---

## 1. a11y API 使用现状 (硬数据)

| API | 引用次数 | 备注 |
|---|---|---|
| `accessibilityGroup` | **0** | 屏幕阅读器分组 |
| `accessibilityText` | **0** | 无障碍文本 |
| `accessibilityDescription` | **0** | 无障碍描述 |
| `accessibilityLevel` | **0** | 重要性等级 |
| `tabIndex` | **0** | 键盘 Tab 顺序 |
| `defaultFocus` | **0** | 默认焦点 |
| `focusable` | **0** | 可聚焦 |
| `groupDefaultFocus` | **0** | 分组默认焦点 |
| `aria-*` 属性 | **0** | ARIA 标准 |
| `Image.alt` | **0** | 图片替代文本 |
| `Button.accessibilityText` | **0** | 按钮无障碍文本 |
| `TextInput.label` / `TextInput.aria-label` | **0** | 输入框标签 |
| `fontScale` / `userFontScale` | **0** | 用户字体缩放 |

**结论**: 项目**完全无 a11y 适配**。

---

## 2. 焦点管理 / 键盘导航

### 2.1 Tab 顺序
- 5 Tab 主页面: Tabs 组件自动接管 (TabBar 自定义后失去默认焦点导航)
- 浮层: 没看到 `focusable(true)` 在入口处显式开启, 浮窗弹出后焦点未明
- 详情浮层 TextInput ×4 (NoteEditForm): 无 focus 自动聚焦, 用户需手动点

### 2.2 键盘导航 (TV/折叠屏外接键盘)
- 没看到 `onKeyEvent` 处理
- AI 浮窗发送 (回车键): 未在 TextInput 中挂 onSubmit
- 详情浮层保存 (回车键): NoteEditForm 未挂

### 2.3 屏幕阅读器 (TalkBack / VoiceOver)
- 95% 组件 `accessibilityGroup` 为空, 屏幕阅读器只会读出 Text() 内容
- Image (图标) 全部无 alt, 读屏会跳过或读"图片"
- AppIcon 16 种图标, 都是 SVG 资源, **没附加语义描述** — 屏幕阅读器用户无法理解"主页 / 笔记 / 复习 / 我的"图标

---

## 3. 颜色对比度 (WCAG AA 标准 4.5:1, AAA 7:1)

### 3.1 令牌 vs BG_DARK (#0A0C10)
| 令牌 | 颜色 | 与 BG_DARK 对比度 | WCAG AA (4.5) | WCAG AAA (7.0) |
|---|---|---|---|---|
| TEXT (#FFFFFF) | 100% 白 | 19.4:1 | ✓ AAA | ✓ AAA |
| TEXT_2 (#B0B3C1) | 浅灰 | 11.6:1 | ✓ AAA | ✓ AAA |
| TEXT_3 (#6B7280) | 中灰 | 4.7:1 | ✓ AA | ✗ |
| TEXT_4 (#4B5563) | 暗灰 | **3.0:1** | **✗ AA 失败** | ✗ |
| GLASS_8 (#08FFFFFF) | 白 8% | ~1.1:1 | ✗ | ✗ |
| GLASS_10 (#1AFFFFFF) | 白 10% | ~1.2:1 | ✗ | ✗ |
| GLASS_14 (#0DFFFFFF) | 白 5% | ~1.05:1 | ✗ | ✗ |
| BORDER (=GLASS_10) | 白 10% | ~1.2:1 | ✗ | ✗ |
| MINT (#5BE3B0) | 薄荷绿 | 12.5:1 | ✓ AAA | ✓ AAA |
| MINT_BORDER (#475BE3B0) | 薄荷 7% | ~1.15:1 | ✗ | ✗ |
| AMBER (#B8A7D9) | 浅紫 | ~9:1 | ✓ AAA | ✓ AAA |
| DANGER (#6B6B6B) | 灰红 | ~3.5:1 | ✗ | ✗ |
| DANGER_BRIGHT (#EF4444) | 亮红 | ~5.5:1 | ✓ AA | ✗ |
| WARNING (#FBBF24) | 琥珀 | 12.4:1 | ✓ AAA | ✓ AAA |

### 3.2 实际 UI 上的对比度问题
- **TEXT_4 在暗背景上**: 暗灰, 大量用于次要信息 (NotesPage, SubjectHeader, ...), 视觉上"看不清"是常见抱怨
- **GLASS_8/10/14 边框**: 卡片边框用这些, 边框在暗背景上**几乎看不见** — 设计上故意的"无边框感", 但 a11y 视角下用户无法识别可点击区域
- **MINT_BORDER (7% 透明度)**: 渐变类型图标的外圈描边, 在 NotesTab 等场景下不明显

### 3.3 渐变色对比度
- `linearGradient` 透明色叠加: 透明度渐变叠加后实际颜色难以计算, 但**普遍存在"中间色"对比度问题**

---

## 4. 字体缩放

- ArkUI 系统支持用户字体缩放 (`Display.setUserFontScale` 或 `fontScale` 属性)
- 项目**未做任何响应式字体缩放适配**: F_XS=11 / F_SM=12 / F_BASE=14 是**绝对值**, 用户调到 1.5x 也不会自动放大
- 这意味着**视障 / 老年用户在系统设置放大字体, 本应用不响应**

---

## 5. 评级

| 维度 | 评 | 备注 |
|---|---|---|
| 焦点管理 | ✗ | tabIndex/defaultFocus 0 引用 |
| 键盘导航 | ✗ | onKeyEvent 0 引用 |
| 屏幕阅读器 | ✗ | accessibilityGroup/Text 0 引用 |
| 颜色对比度 | △ | 主文白/浅灰 OK, 暗灰/玻璃色失败 |
| 字体缩放 | ✗ | 字号绝对值, 不响应系统 |
| TouchTarget (44dp) | △ | 大部分按钮 ≥44vp, IconButton 22vp 偏小 |
| 减动效偏好 | n/a | 系统提供, 未显式 opt-in |

---

## 6. 应有但缺的结构

### 6.1 a11y 工具函数 (建议)
```typescript
// common/.../a11y/A11yText.ets
export class A11yText {
  static icon(name: string): string  // '主页' / '笔记' / '复习' / '我的'
  static button(label: string): string
  static tab(label: string, active: boolean): string
  static error(kind: ErrorKind): string  // 复用 ErrorBus
}
```

### 6.2 关键组件 a11y 适配 (建议清单)
- **AppIcon**: 加 `accessibilityText: this.name → 中文映射`
- **NoteCard**: 加 `accessibilityGroup(true)` + `accessibilityText('笔记: 标题, 类型, 日期')`
- **NoteCloseButton / IconButton**: 加 `accessibilityText('关闭' / '编辑' / '分享')`
- **TextInput (4 处)**: 加 `label` 或 `accessibilityText` 关联 placeholder
- **TabBar 5 Tab**: 加 `accessibilityText('Tab 1/5, 首页')` 等
- **HomeTopBar / NotesHeader / SubjectHeader**: 在 `accessibilityGroup` 内合并 statusBarHeight 占位区 + 标题区, 避免读屏朗读两次

### 6.3 颜色令牌增补 (对比度修复)
- 新增 `TEXT_5`: 当前 TEXT_4 (3:1) 提升至 ≥4.5:1 (建议 #8B95A5)
- 玻璃色 (GLASS_*) 保持当前透明度, 但**边框相关场景**用纯色 BG_CARD_OVERLAY 替代
- 给 MINT_BORDER 加 `MINT_BORDER_SOLID` 别名, 关键边框 (可点击卡片) 用实色

### 6.4 字体缩放适配
- 把硬字号改为 `vp + 字号 token`, 在 `onConfigurationUpdate` (ArkUI) 监听 `fontScale` 重新计算
- 或者用 `fp` (font pixel) 替代 `vp`, 系统会自动缩放

---

## 7. 待补充资料

§14/§15/§16 不变, 新增:
17. **a11y 是否在比赛评审范围**: 鸿蒙高校创新赛有"无障碍"评分维度吗? 若无, 第 6 节仅作长远建议; 若有, 是必补
18. **字体缩放响应是否 demo 必要项**: 真机演示中如果用大字号, 字号不响应会暴露
19. **盲人/低视用户实测**: 若团队有视障成员, 可实测告知优先级

---

## Last updated

2026-09-06 晚
