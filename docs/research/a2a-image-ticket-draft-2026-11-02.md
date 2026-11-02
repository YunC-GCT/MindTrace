# 小艺端A2A 图片输入提单草稿（2026-11-02）

> 用途：向华为确认「小艺 → 端A2A Agent 图片 part 未下发」是否能力未开放 / 配置缺失 / 客户端 bug。
> 依据调研：[`a2a-image-input-feasibility-2026-10-29.md`](./a2a-image-input-feasibility-2026-10-29.md) §2026-11-02 第二轮核查。

## 提交渠道（任选其一，建议 1 + 2）

1. **华为开发者联盟 · 在线提单**（推荐，可跟踪工单号）
   - https://developer.huawei.com/consumer/cn/support/feedback/
   - 登录后按「开发」/「开放能力」类别提交；提交后右上角头像 →「我的工单」查看进展。
2. **华为开发者社区 · 小艺开放平台版块发帖**（响应更快，适合要口径）
   - https://developer.huawei.com/consumer/cn/forum/ （选小艺开放平台分类）
3. 小艺 App 内「帮助与客服 → 问题与建议」（适合反馈客户端行为，可勾选共享日志）。
4. 若已有华为侧对接人/企业联络人：按《服务保障条款》的联络方式直接反馈并附工单号。

## 提单标题

端A2A（AgentExtensionAbility）未下发图片 part，仅下发 text part；inputModes 已声明 image/*、平台照片开关已开

## 提单正文（可直接粘贴）

**环境**
- 设备：MRO-W00（HarmonyOS 7.0.0 / API 26）
- 小艺 App 版本：11.7.8.339
- Agent 模式：端A2A（AgentExtensionAbility），已关联应用并发布真机测试
- 测试时间：2026-11-02 11:46（可提供完整 hilog）

**配置**
- AgentCard：`defaultInputModes` 与 `skills[].inputModes` 均包含 `text/plain`、`image/*`、`image/jpeg`、`image/png`、`image/webp`、`image/bmp`、`image/gif`
- `appInfo.bundleName/moduleName/abilityName` 与 `module.json5` 一致
- 小艺开放平台「编排 → 输入文件 → 支持上传照片」已开启；两种发送方式（直接发送 / 进待发送区发送）均试过
- Agent 已实现图片 part 解析与端侧 OCR（`Part<url>`、`raw`、云形状 `file` 均兼容），但实际收不到图片

**复现步骤**
1. 小艺中进入该端A2A智能体会话；
2. 点击输入框「+」→「照片」，选择一张本地图片；
3. 输入文字「整理成笔记」，点击发送；
4. 在 AgentExtensionAbility 的 `onData` 打印原始报文与逐 part 字段。

**实际结果**
- 图文同发：`params.message.parts` 只有 `[{"mediaType":"text/plain","text":"整理成笔记"}]`，无任何图片/文件 part；
- 只发图不附文字：收到 `parts:[{"mediaType":"text/plain","text":""}]`（空 text part）；
- 小艺自身完成了对图片的识别与回答，但识别结果与图片均未下发到端A2A Agent；
- 我方 `onData` 已打印 `part[i] media=… text=… raw=… data=… url=… file=…`，可证明不是解析问题。

**期望结果**
按《端A2A Part结构定义》（更新 2026-10-15）「在线文件通过 url、filename、mediaType 描述，支持双向传递」，`parts` 中应出现：
```json
{ "url": "file://… 或 https://…", "filename": "xxx.jpg", "mediaType": "image/jpeg" }
```
或图片识别结果以 `text/plain` 文本形式下发（任一即可）。

**请确认**
1. 端A2A 当前是否已支持「小艺 → Agent」方向的图片/文件 part 下发？有无最低小艺版本 / 系统 API 版本 / 灰度要求？
2. 除控制台「输入文件设置」和 AgentCard `inputModes` 外，是否还有其它开关、白名单或权限（如端插件权限/图库权限）需要开启？
3. 端A2A 入站图片只支持 `url` 型还是也支持 `raw`/base64？`url` 的有效期与鉴权要求是什么？
4. 是否存在「图片识别结果以 text 转发给 Agent」的配置项？若无，后续是否有计划？
5. 若当前版本不支持，官方推荐的替代路径是什么（应用内入口 / 小艺识图后转文字 / 其它）？

**附件建议**
- `hilog.txt`：筛 `MindTraceA2A` / `A2A` 关键行，含 `raw=` 与 `part[i]` 行（保留时间点）；
- `agent_config.json`（脱敏 iconUrl 等）；
- 平台「输入文件设置」截图（照片开关、发送方式）；
- 小艺会话截图（图片 + 文字 + Agent 回复）；
- 可选：请求 JSON 全文（含 `messageId`、`traceId`，便于平台查链路）。

## 跟进

- 提交后记录**工单号**；若 48h 无回复，在论坛帖 @ 版主并附工单号；
- 平台回复后回填本文件「平台结论」小节，并据此决定：
  - 支持入站 `url`：我方补 https 下载/本地 file:// OCR 分支并真机验证；
  - 只支持文字转发：维持当前文本整理链路；
  - 不支持：保留 App 内图片入口 + 小艺识图转文字兜底。

## 平台反馈（2026-11-02）与我们的处理

平台（工单/运营助手）给出 5 条排查方向，逐条对照：

| # | 平台原因 | 我们的处理 |
|---|---|---|
| 1 | `defaultInputModes` 用 `image/*` 通配符可能不被识别，要求具体 MIME、单元素 ≤32 字节 | ✅ 已改为 `["text/plain","image/jpeg","image/png","image/webp","image/bmp","image/gif"]`（不再含 `image/*`） |
| 2 | skill 级 `inputModes` 会覆盖 `defaultInputModes`，若只含 text/plain 则不下发图片 | ✅ 已删除 skill 内 `inputModes`，统一继承 Agent 级默认值 |
| 3 | 改 AgentCard 后未重装应用/未重启小艺，客户端仍用旧卡 | ⏳ 需按平台三件事：重新导入 AgentCard → 重发真机测试 → 重启小艺；我方 HAP/HSP 已重装 |
| 4 | 照片开关只是权限前提，只有用户在对话里主动附加图片才会带 part | ✅ 受控测试已主动「+ → 照片」附加图片 + 文字发送 |
| 5 | 解析方式可能漏掉图片 part（`getUserInput` 只返回文本；图片在 `url`+`mediaType`） | ✅ 我方是手写 JSON-RPC：`onData` 打印完整 `raw` 与逐 part 字段 `media=… text=… raw=… url=… file=…`；图片在 `url`/`file.uri`/`raw` 时会进 `AgentImageParts`，不存在只读 text 的漏解析 |

- AgentCard 版本升至 **1.0.3**；
- 平台在反馈末尾建议「打印出的 parts 确实只有 text/plain 且配置无误时提工单/由平台定位路由策略」——与当前现象一致；
- 下一步：用户重新导入 AgentCard + 重启小艺后，我方再跑一次受控图片测试并复查 `parts`。
