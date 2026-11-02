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

---

## 2026-11-02 第二轮核查（用户补充：SDK API 全文 + 第六节）

来源：用户调研合集 `Documents/MindTrace-a2a-docs-2026-11-02/`（新增第六节与 `raw/sdk-agent-framework-kit-a2a-api.txt`，Agent Framework Kit 26.0.0 A2A API 全文）。

### 新增确认

| # | 事实 | 依据 |
|---|---|---|
| 16 | SDK `Part` 字段 = `text / raw / url / data / mediaType / filename / metadata`；`url` 注释要求标准 URL（`file://`/`https://`/`http://`）；`Message.parts: Part[]`；`RequestContext.getMessage()` 可整条取 | `raw/sdk-agent-framework-kit-a2a-api.txt` |
| 17 | 平台「配置 → 端插件权限」支持图库/文件等端侧能力；文档把「开了文件/位置能力仍不可用」指向 APP 权限声明、运行时授权、平台端插件权限、A2A 消息是否真的处理对应输入类型 | 第六节 / 官方 FAQ |
| 18 | 「进待发送区」不是图片+文字同帧投递的必要条件；两种发送方式都可用 | 第六节 |
| 19 | 官方没有任何「图片识别结果转 text 转发」配置项或 AgentCard 字段；官方口径是传媒体本体 | 第六节 |

### 更新后的判断

1. **协议/SDK/文档三层都允许入站图片**；但端A2A 客户端（小艺 11.7.8.339）在组包阶段只放 `text/plain`，因此应用侧仍无法拿到图片；
2. **「端插件权限」不是图片输入开关（2026-11-02 修正）**：官方文档《端插件权限管控》说明它只在「智能体/工作流添加了需要系统权限的端插件工具」时出现，用于声明位置/文件/图库等权限用途（且端侧插件能力需单独申请）；端A2A 纯聊天 Agent 的控制台没有该菜单属正常现象。真正与图片输入相关的开关只有「编排 → 输入文件 → 支持上传照片/拍摄 + 发送方式」，这些已开启并实测仍不下发 image part；
3. 应用侧无需改结构：`AgentImageParts` 已兼容 `url` / `raw` / `file.uri` 三大形状；若未来下发的是 `https://` URL，还需要补“下载到临时文件再 OCR”的分支（当前未实现，待确认平台载体）；
4. 结论回到客户端/平台能力：需提单确认（草稿见本文件第五节），或等待小艺版本更新；应用侧没有其它配置可开。
4. 若平台最终只给文字识别结果，文本整理链路已就绪（真机 A2A 冒烟 `ok=true`，不打开 App、无卡片入口）。

## 2026-11-02 卡片选图实测（端A2A + AgentUIExtension）

实现并真机验证了平台建议的路径二（卡片选图）：

1. **卡片可渲染**：A2A 回复携带 `uiExtensionCard`（`cardId/bundleName/moduleName/abilityName/payload` 齐全）后，小艺能打开 `AgentUIExtAbility` 半屏卡片（hilog `A0A2A1` 有 `onCreate/onSessionCreate`，无 1011）；
2. **半屏卡片内无法渲染系统相册**：
   - 卡片里调用 `photoAccessHelper.PhotoViewPicker.select()` → 弹出相册壳但**图片网格空白**；
   - 改为内嵌系统 `PhotoPickerComponent`（`PickerOptions/PickerController`）→ 卡片区域**空白**；
   - 判断为 UIExtension（卡片）内再嵌套/内嵌系统相册组件不可用，属系统限制；
3. **可行兜底**：卡片按钮 `startAbility(EntryAbility, mtAction=pick_from_card)` 可正常打开 MindTrace + 系统照片选择器（实拍已验证，图片网格正常），后续由 App 完成 OCR/整理/写本地库。
4. 结论：**「不打开 App 的图片整理」在 UIExtension 卡片内无法实现**；图片链路只能二选一：
   - 卡片/回复按钮 → 短暂打开 App 相册（当前实现，最后写入本地笔记库）；
   - 云A2A 接收 file part（图片上云，用户留在小艺）。
   文本整理仍可在小艺内联完成、无需打开 App（已真机冒烟通过）。
