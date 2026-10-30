# Bot 交接单 · ship（2026-10-30）

> 交接人：Hermes 主线 session · 接收：ship（deepseek-flash）· 状态：待接手
> 基线：`feature/a2a-text-ingest` @ `dac64c3`（未 push）
> 你的活全部是**口径与对外产出**，不写代码。凡是没测过的数字，一律写「未测」。

## 一、本轮新增的事实（可直接引用，都有落点）

1. **端A2A 图片通道：协议支持，客户端不下发。**
   - 协议侧：`@hms.ai.A2A.d.ts` 的 `Part` 只有 `text/raw/url/data/mediaType/filename/metadata` 七个字段，官方文档明示「在线文件通过 url、filename、mediaType 描述，支持双向传递」。
   - 客户端侧：真机小艺已完成 `uploadImageToCloud` → `uploadToObs`（bucket `nsp-hivoice-cgsgy-drcn`，`result code is 0`），待发送区也有缩略图，但最终报文 `parts` 只有 `[{"mediaType":"text/plain"}]`，整包 475 字节；整机 366 MB 日志里 `"mediaType":"image` **0 命中**。
   - 落点：[`docs/research/a2a-image-input-feasibility-2026-10-29.md`](../../research/a2a-image-input-feasibility-2026-10-29.md) + `docs/agents/phase-tracker.md`「已知阻塞」。
2. **对话内引导通道已实现未验收**：小艺里发「我要拍题」，回执会带一张官方 `uiExtensionCard`（半屏卡片，两个按钮：从相册选图 / 拍照整理），受 `UI_CARD_ENABLED` 开关约束。真机是否渲染**未验**，验收由 harmony 做。
3. **权限现状**（`entry/src/main/module.json5`）：只声明 `ohos.permission.CAMERA`、`ohos.permission.INTERNET`、`ohos.permission.PUBLISH_AGENT_REMINDER`。**没有相册读权限**——相册走系统 Picker，免权限。上架材料里不要写「申请了相册权限」。
4. **阶段状态**：P4 结果回执 ⬜（回复里还没有「本次整理 N 条」）、P5 合规落地 ⬜（AI 标识 + 导出元数据未做）、P6 🟡（已提交审核）。

## 二、任务

1. **指标定义（每项五栏：定义 / 口径 / 采集点 / 当前值 / 是否已测）**：
   - 端A2A 图片通道成功率 —— 采集点：`MindTraceA2A: raw=` 报文里 `parts` 是否含 `image/*`；当前值 **未测**（单次样本 0/1，不能当成功率）。
   - 卡片触达率 —— 采集点：`A2A_UI_CARD sent` 与 `AGENT_UI onCreate` 的配对比例；当前值 **未测**。
   - 整理回执延迟 —— 采集点：`A2A_REPLY_SENT elapsedMs`；当前有单次样本（149 ms 文字回执），**不能当均值**。
   - 小艺侧整理成功率 —— 采集点：`INGEST_DIRECT done` / `INGEST_DIRECT failed`；当前值 **未测**（只有单次成功样本）。
2. **验收清单更新**：P1 的图片通道从「阻塞」改成「协议支持、客户端不下发，已降级为应用内选图 + 对话内卡片引导（待真机验收）」；P4 回执、P5 合规保持 ⬜ 并写明缺口。
3. **上架合规逐条对应代码**：相机权限 → 拍照入口文件；`INTERNET` → `LlmClient` 调用；`PUBLISH_AGENT_REMINDER` → 提醒能力；隐私政策里「图片只在端侧 OCR、不上传云端」要与 `CoreVisionOcrRecognizer` 的实际行为一致（OCR 在设备内，LLM 只收文本）。这条如果对不上，先报给 architect，不要自己改代码。
4. **对外材料统一表述**（答辩稿、BP、简历段落都只用一个说法）：
   > 小艺端A2A 支持图片输入，但当前客户端版本未把图片写入 A2A 报文的 `parts`（实测 475 字节仅含 text part）；应用侧已实现四种 part 形状兼容与官方 `uiExtensionCard` 引导，用户点卡片即可回到应用选图完成整理。
   不要写「小艺不能发图」这种绝对句，也不要写已完成。
5. **答辩稿补一段**：为什么选择端侧 OCR + 文本入链路（隐私、时延、端侧模型限制），用已有的 `PROBE available=true init=true`、`OCR done lines=4 chars=48` 作为端侧能力证据，注明是单次样本。

## 三、边界

- 不改代码、不改架构、不写 ADR（发现文档与代码不一致 → 报给 architect）。
- 不 push、不合并 PR。
- 没跑过的验收不要写成「已验收」；没测过的数字一律「未测」。

## 四、交付

- 一份指标表（五栏齐全，空值写「未测」）、一份更新后的验收清单 diff、一段 ≤300 字的对外统一表述、一段答辩稿补充（口语、能直接念）。
- 交付时标清每条结论的证据来源（文件路径或日志锚点），没有来源的结论删掉。
