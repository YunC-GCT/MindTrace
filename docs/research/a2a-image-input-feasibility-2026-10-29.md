# 小艺 → 端侧 Agent 图片输入协议可行性

> 2026-10-29 · 取证：`devecocli docs`（本机官方文档）+ 本机 SDK `C:/Program Files/Huawei/DevEco Studio/sdk/default`（API 26）+ 真机 hilog。
> 口径：`docs:<documentId>` = 官方文档原文；`文件:行号` = SDK d.ts 原文；`推断` 显式标注。

## 结论

1. **协议支持图片，载体是「文件引用」**：端A2A 的 `Part` 用 `url`（须 `file://`/`https://`/`http://`）+ `mediaType` + `filename`，或内联 `raw`。官方 `Part` **没有** `file`/`fileId`/`kind`/`type` 字段。图片 part 形状 = `{url, filename, mediaType:"image/png"}` 或 `{raw, mediaType:"image/*"}`。`AgentImageParts.ets` 里的 `file`/`kind` 是云A2A 兜底，非端A2A 官方字段。
2. **应用侧唯一可声明的是 inputModes**：`agent_config.json` 的 `defaultInputModes` / `skills[].inputModes`（MIME）是 app 侧唯一开关，文档明示 `["image/png"]` 表示图片输入。`AgentCapabilities`、`AgentHostProxy` 无任何图片相关字段/方法。另有「开放平台→照片设置→支持上传照片」属**平台侧**开关，不是 app 代码声明。
3. **应用侧不能再改代码让小艺把图片填进 parts：不能（推断，依据见证据 3/4/5/9）**。`message.parts` 是小艺客户端组装报文时决定的；扩展只能被动 `onData(proxy, data:string)` 收整包 JSON，SDK 无任何要求客户端附图的 API。实测：image MIME 已声明、四形状解析已兼容、平台照片开关已开，仍只收到 `parts:[{"mediaType":"text/plain"}]` 空 part（整包 475B），而小艺侧 `uploadToObs` 成功 → 图在客户端组装期被丢弃。
4. **Q4「小艺是否支持给端侧 Agent 发图」：本地文档无记载**。6 篇 + 下列关键词均无明确表述（见证据 8）。

## 证据

| # | 结论 | 证据 |
|---|---|---|
| 1 | Part 仅 7 字段；url 指文件、mediaType 含 image/png、filename | `docs:API参考/Agent_Framework_Kit_智能体框架服务/ArkTS_API/A2A_A2A协议/hmaf-a2a-protocol`（Part 表）；SDK `@hms.ai.A2A.d.ts:131-189`（url:148-156 / data:157-164 / mediaType:165-172 / filename:173-180），无 file/kind/type |
| 2 | Part 可承载「文件引用（URL 或内联字节）」 | `docs:开发指南/Agent_Framework_Kit_智能体框架服务/通过AgentAbilityExtension实现智能体间A2A协议通信/hmaf-a2a-dev-guide`（基本概念·Part） |
| 3 | 唯一 app 侧图片声明 = inputModes，文档举例 `["image/png"]` 图片输入 | `docs:.../端侧A2A框架开发指导/开发端侧智能体/AgentExtensionAbility配置文件说明/agent-extension-configuration`（defaultInputModes 行）；SDK `application/AgentCard.d.ts:111-121,334-343` |
| 4 | 无其它图片能力/开关 | SDK `application/AgentCard.d.ts:222-273`（AgentCapabilities 仅 streaming/push/stateHistory/extendedCard/extension）；`application/AgentHostProxy.d.ts:29-52`（仅 sendData/authorize）；`docs:.../agent-extension-configuration`（capabilities 表同） |
| 5 | 扩展只能被动收整包字符串 | SDK `@ohos.app.agent.AgentExtensionAbility.d.ts:63-74`（`onData(proxy, data:string)`）；`docs:.../使用AgentExtensionAbility组件实现智能体服务/agent-extension-ability`（onData 收发示例、type:"agent" 注册） |
| 6 | AgentUIExtensionAbility：服务端用它展示 UI，须与 Agent 同进程，最多 5 实例/禁子窗口 | `docs:.../端侧A2A框架概述/agent-overview`（结果渲染）；`docs:.../ohos_app_ability_AgentUIExtensionAbility_带界面的智能体扩展组件_/js-apis-agent-agentuiextensionability`；SDK `@ohos.app.agent.AgentUIExtensionAbility.d.ts:19-31` |
| 7 | `uiExtensionCard` / `ability.want.params.payload`：**本地文档无记载** | `devecocli docs search "uiExtensionCard"` → 0 命中；6 篇均未提拉起 want/payload 契约 |
| 8 | Q4 无明确表述（搜过关键词） | `端侧A2A` `A2A Part` `A2A 文件 file` `发送图片` `图片 image 上传` `端侧A2A 图片` `小艺 图片` `多模态 智能体 图片` `支持上传照片 照片设置` `Agent 图片 输入 inputModes` → 无「小艺→端侧 Agent 发图」明示 |
| 9 | 旁证：小艺对「只给引用不给实际图」会拒处理 | `docs:FAQ/UI框架/组件使用/应用内的图片拖拽进小艺后提示没有收到图片数据/faqs-arkui-1045`（统一拖拽场景，非 A2A，仅旁证） |

## 备选方案对比

| 方案 | 做法 | 可行性 | 依据 |
|---|---|---|---|
| A 等客户端修 | Agent 侧维持 image MIME + url/raw 解析，等小艺在 parts 填 `url/raw` | ✅ 唯一符合协议 | 结论1/3 + 证据1/2/5 |
| B 再声明/加元数据 | 加 inputModes/capabilities/extension/新 type | ❌ 无效（无此开关） | 证据3/4（capabilities 无 image；extension 仅自由 JSON） |
| C AgentUI 卡让用户回应用选图 | 回复发 UI 卡→按钮 startAbility(EntryAbility)→App 内 Picker | ⚠️ 协议允许但真机卡 `start_ability_fail(1011)`；`uiExtensionCard` 无文档 | 证据6/7；spec 031 §4.9 |
| D 应用内入口兜底 | 小艺只回文字引导，选图走 App `+ → 批量` | ✅ 已验证可用 | phase-tracker P1/P2 |

## 补充：小艺开放平台文档取证（2026-10-29 23:58，Hermes 直连 developer.huawei.com）

本地 `devecocli docs` 只覆盖 HarmonyOS 应用开发文档，**不含小艺开放平台的协议规范**。补齐两份原文：

| 文档 | 关键原文 |
|---|---|
| 《端A2A协议消息指令定义 / 扩展数据结构定义》`doccenter-celia/agent2agent-exp-part-0000002735605000` | `uiExtensionCard` 字段：`cardId`(必填)、`bundleName`(必填)、`moduleName`、`abilityName`、`payload`(**字符串**)、`dimension`、`encrypted`、`summary`；`uiSession` 生命周期指令；`readyReceive` 等。**并明确「在线文件通过 url/filename/mediaType 描述，支持双向传递」** |
| 《其他结构定义》`doccenter-celia/agent2agent-exp-other-0000002765284431` | `jump` 结构：`executeIntent{bundleName,intentName,executeMode,intentParam}` / `deepLink{url,appName,appPackage,minVersion}` / `overlayMode`；两种跳转共存，**先 executeIntent 再 deepLink**；`data.jump` **只在 state 帧可用** |

结论修正两条：

1. **「协议支持图片」由官方明示**：不是「协议没写」，而是「小艺客户端这次没填」。这一条把「等客户端」从推断变成了有原文支撑的事实。
2. **spec 031 §4.9 的 `1011 start_ability_fail` 有了可解释的成因**：那一轮只发了 `{"uiExtensionCard":{"payload":{...}}}`，缺 `cardId` 与 `bundleName` 两个必填字段，`payload` 还写成了对象而非字符串。按官方契约补齐后有重试价值（已交 DSH 实施，带 `UI_CARD_ENABLED` 开关防重试风暴）。

## 待核实

- 小艺客户端丢弃图片 part 的根因（平台开关已开 vs 客户端 bug）：需平台/小艺侧日志，应用侧无法验证。
- `uiExtensionCard` 的 Want 组装规则（abilityName 来源）：无文档，需提工单。
- `type:"agentUI"` 取值未在本次 6 篇出现（属工具链 schema 枚举，见 spec 031 §4.5），需查 `modulecheck` 确认。

---

## 2026-11-02 更新：小艺开放平台官方文档合集 + 受控复测

来源：用户调研的 [`a2a-image-input-docs-2026-11-02.md`]（本机 `Documents/MindTrace-a2a-docs-2026-11-02/`，采集自 developer.huawei.com 小艺开放平台文档中心，页面更新时间 2026-10-15 19:40）。

### 新增确认

| # | 事实 | 依据 |
|---|---|---|
| 10 | 官方明示 `Part<url>` 文件引用「支持双向传递」，字段 `url / filename / mediaType`；mediaType 白名单含 image/jpeg、png、gif、webp、bmp、pdf、csv、octet-stream；该页**无 raw/base64** | 《端A2A Part结构定义》agent2agent-exp-part-0000002735605000 |
| 11 | 《对话交互》只给出 **Agent→小艺** 的文件示例；**入站（小艺→Agent）无图片示例** | agent2agent-chat-0000002735604996 |
| 12 | 平台控制台「编排 → 输入文件」只有：照片开关（支持上传照片/拍摄）、发送方式（直接发送 / 进待发送区发送）、快捷指令；**没有「识别结果转 text」开关** | input-file-settings-0000002775710043 |
| 13 | 该页示例报文是 **云A2A 形状**：`parts:[{kind:"text",text:...},{kind:"file",file:{name,fileId,uri,mimeType}}]`，与端A2A 手写 proto-JSON（`parts:[{mediaType,text}]`）不是同一形状 | 同上 |
| 14 | 官方接入要求：「只有 Agent 真正处理图片或文件类型时，才开启输入文件能力，并同步适配 A2A 消息中的媒体内容」；AgentCard 只有 `defaultInputModes` / `skills[].inputModes`，无视觉/识图字段 | device-a2a-quickstart-0000002733266338；agentcard-0000002765284425 |
| 15 | 受控复测（MRO-W00，小艺 11.7.8.339，2026-11-02 11:46）：在小艺聊天里**从「+ → 照片」选图 + 输入「整理成笔记」→ 发送**，A2A 实际只收到 `parts=1 / part[0] media=text/plain text=5`；图片未出现在任何 part。图片那轮若单独发，则是 `text=""` 空 text part | 真机 hilog `MindTraceA2A` |

### 结论（更新后）

1. **协议层仍支持图片**（Part<url> 双向），应用侧解析已就绪（`AgentImageParts` 兼容 `{url,filename,mediaType}` / `{raw}` / 云形状 `{kind:file,file:{uri,mimeType}}`），但 **客户端组包阶段没有把图放进 parts**——这是当前版本小艺客户端/平台能力缺口，应用侧无法通过代码补齐。
2. **平台开关不负责转发图片**：照片开关只决定用户能否选图、以及「直接发送/待发送区」交互；它不会把图片识别结果或 image part 自动补进 A2A 报文。
3. **可行路径**：
   - A（体验最好，等平台）：小艺把图片以 `Part<url>`（或识别后的文字）转发给 Agent；我们代码无需改结构，只补 OCR/整理即可（已有 `image_qa` 与 OCR 整理分流）；
   - B（当前可用）：用户先让小艺识别/转写图片文字，再把文字发给 Agent，说「整理成笔记」——已在真机 A2A 冒烟通过（`ok=true`，回复“已整理入库…”），且不打开 App、不再发卡片入口；
   - C：App 内发图（完整 OCR/整理）。
4. 需向平台确认的问题（已整理给用户）：
   - 端A2A 是否计划支持入站 `Part<url>` 图片，或把图片识别结果作为 text 转发？
   - 平台「支持上传照片」已开启、AgentCard 已声明 image/*，为何客户端组包仍只有 text？（附请求报文/时间点/设备版本）
   - 「发送方式=进待发送区发送」是否为图片+文字同帧发送的必要条件？当前受控测试在待发送区附文字后仍无 image part。
