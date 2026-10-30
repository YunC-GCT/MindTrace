# Bot 交接单 · ui（2026-10-30）

> 交接人：Hermes 主线 session · 接收：ui（deepseek-flash）· 状态：待接手
> 基线：`feature/a2a-text-ingest` @ `dac64c3`（未 push）；领域：`entry/src/main/ets/pages/`、`overlays/`、`viewmodels/`、`shared/`。

## 一、现状（先看这三处，别重复造）

1. `entry/src/main/ets/pages/AgentUiCard.ets`（190 行）——本轮新加的半屏卡片页，跑在 **`agentUI` 扩展进程**里（不是主进程页面，拿不到 AppStorage，只能吃 `LocalStorage('session'/'cardQuery')`）。已经用了 `common` 的设计 token：`BG_CARD / BG_DARK / BORDER / MINT / TEXT / TEXT_2 / F_LG / F_MD / F_SM / R_LG / R_MD / S_2..S_5 / W_SEMIBOLD`；布局只有一条 `maxWidth 520` 收窄规则。
2. `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets`——「整理记录」**已经在这个浮窗里**：`正在整理 N 张图片…`(:989)、`整理完成：N 张图 → M 条笔记`(:1126-1129)、`整理失败：…`(:1050)。别再另起一个「整理记录」页面。
3. 全仓 `grep -rln "mediaquery\|matchMediaSync\|breakpoint"` 在 `entry/src/main/ets` **0 命中**——三档断点（手机 / 折叠 / 2in1）目前没有任何统一实现，卡片页尤其缺。

## 二、任务

1. **卡片页三档断点**：手机（竖屏全宽）、折叠/平板（居中收窄，保留 `maxWidth 520` 的意图但别写死）、2in1（卡片高度不被拉伸，按钮横排）。用 `@ohos.mediaquery` 或父容器百分比，**不要**在 `AgentUiCard.ets` 里新引第二套断点常量——如果 `common` 里已有类似 token 就复用，没有就在 `entry/src/main/ets/shared/` 加一处并让卡片复用。
2. **深色模式**：卡片是半屏浮层，根容器现在不铺深色全屏底。要保证深色下卡片正文与按钮对比度够（`TEXT` / `BG_CARD` 在这套 token 里是否随主题变，先去 `shared/` 确认），并检查 `AgentUIExtAbility` 拉起时系统深浅色是否传进扩展进程。
3. **错误态**：`startAbility` 失败时页面目前只有一句「请在 MindTrace 里点『+』选图」。补一个明确的重试 affordance（再点一次按钮），并把失败原因按 `BusinessError.code` 分两类文案（无权限 vs 应用未就绪），别把原始 code 直接甩给用户。
4. **入口视觉一致**：卡片上的「从相册选图 / 拍照整理」两个按钮，要和 `AgentFloatWindow` 里「+」展开的相册/拍照入口用同一套图标与措辞。用户会连着用两个入口，措辞不一致会被当成两个功能。
5. **浮窗失败重试**（小改）：`整理失败：…` 现在只是一段文字，补一个「重试」可点区域，复用已有的重试链路，不要新增 service。

## 三、边界

- 不碰 `workflows/`、`services/`、数据库 schema、`cardservice/`、`hvigorw`/签名/装机。
- 不改 `AgentExtAbility.ets` 的报文逻辑（卡片 part 的契约在 `A2AUiCard.ets`，属 harmony 与 flow 的边界）。
- 卡片页只做展示与意图回传，**不要在页面里做 OCR 或写库**。
- ArkTS：禁正则字面量、禁 `any`/`unknown`、禁无类型对象字面量、`.ets` 禁 BOM、文件头按 `docs/agents/file-header-template.md`。

## 四、验收

- 真机（`3XTYD24C16203663`）三个形态各截一张：手机竖屏、折叠展开或平板、2in1（有就截，没有就写「无设备，未验」）。
- 深色模式截一张卡片。
- 卡片按钮点下去要能看到 `CARD_ACTION received action=pick_from_card`（这是主进程日志，由 harmony 提供），或明确写「跳转失败，原因是 …」。
- `node scripts/agent-gate/index.mjs --all` 必须 `RESULT: PASS`；交付贴 `pass=/fail=` 与改动文件清单。
- 交付说明里写清：断点在哪几个值、深色是跟随系统还是强制、失败文案分了几类。
