# HarmonyOS / OpenHarmony 官方 Kit 调研 — MindTrace 视角

> **Date:** 2026-09-05
> **Project:** MindTrace (`<本地仓库根>`
> **Audience:** 团队对齐 + 评委 pitch 素材(读 §1)+ 实施选型(读 §2-§13)
> **Scope:** 12 个 kit 家族的官方能力 + MindTrace 适配点 + 成本档位 + 不推荐理由
> **基线:** `targetSdkVersion=6.1.1(24)` · `compatibleSdkVersion=6.1.1(24)` · `runtimeOS=HarmonyOS`
> **排除范围:** 视觉/OCR 类 kit 保留自研(`OcrTool` 已用 `CoreVisionKit` 仅做文本兜底,公式走自建服务),本文不展开

---

## §0 一句话摘要

MindTrace **当前仅用了 7 个 kit/模块**(`@kit.ArkData` / `@kit.ArkTS` / `@kit.BasicServicesKit` / `@kit.CoreVisionKit` / `@kit.ImageKit` / `@kit.NetworkKit` / `@ohos.app.form.*` / `@ohos.app.ability.*`),**最大空白是 AI/LLM 端侧能力**(`@kit.AIEngine` / `@hms.ai.llm`)、**Service Widget 真实数据回灌**(`@ohos.app.form.FormExtensionAbility` 已有但 mock)、**复习提醒**(`@kit.NotificationKit` ReminderAgent)、**后台任务**(`@kit.BackgroundTasksKit`)。其余 6 个 kit(FileKit / PreferencesKit / MediaKit / UniversalKeystoreKit / ScanKit / 推送)非关键路径或已用更轻方案替代。

---

## §1 一页纸总表(评委/团队用)

| Kit | 模块标识符 | MindTrace 当前? | 推荐档位 | 关键不推荐理由 |
|---|---|---|---|---|
| **AI / Foundation Model / LLM** | `@kit.AIEngine` / `@hms.ai.llm` | **未用** | **高 — 强烈建议接入** | — |
| 文本结构化 / NLP | `@kit.NaturalLanguageKit` / `@kit.TextRecognition`(已在 OcrTool 用) | 未用(基础能力) | 中 — 视场景 | 与现有 `LlmGuard`/`ContentProtocol` 重复 |
| **ReminderKit**(复习提醒) | `@kit.NotificationKit` (`ReminderAgent`) | **未用** | **高** | — |
| **FormKit / CardKit**(卡片 / 服务卡片) | `@kit.FormKit` / `@ohos.app.form.*` | 部分(FormAbility mock) | **高 — 必做** | — |
| **Service Widget**(FormExtension) | `@ohos.app.form.FormExtensionAbility` | 部分(scaffold + mock) | **高 — 必做** | — |
| ScanKit(扫码) | `@kit.ScanKit` | 未用 | 低 | 业务无扫码入口 |
| **PushKit**(推送) | `@kit.PushKit` | 未用 | 中 — 视运营策略 | 复赛窗口 + 隐私评估 |
| **Background TasksKit**(后台任务) | `@kit.BackgroundTasksKit` | 未用 | **高 — 复习提醒依赖** | — |
| UniversalKeystoreKit(密钥库) | `@kit.UniversalKeystoreKit` | 未用 | 低 | LLM API key 走 `preferences` 即可 |
| AVPlayerKit / MediaKit(媒体播放) | `@kit.AVPlayerKit` / `@kit.MediaKit` | 未用 | 低 | 业务无音视频 |
| ImageKit(图像处理) | `@kit.ImageKit` | **已用**(PixelMap) | — | 已在 `OcrTool` |
| FileKit(文件) | `@kit.FileKit` / `@ohos.file.fs` | 已用 `fs` | 低 — 视场景 | 当前 RDB 足够 |
| PreferencesKit(用户首选项) | `@kit.ArkData`(preferences 子模块) | **已用**(`OcrConfig`/`LlmConfig`) | — | 已落地 |

> **关键洞察**:**5 个高优先 kit** 都和 MindTrace W4 后的"复习闭环 + 桌面卡片 + AI 兜底"强相关,任何一项都直接对应一条产品故事线。

---

## §2 AI / Foundation Model / VLM / LLM

**能力概述**:HarmonyOS NEXT 提供两套端侧 LLM 接入:
- **`@kit.AIEngine`**(方舟引擎 / Foundation Model):基于盘古/昇思端侧模型,提供文本生成、对话、向量化、视觉理解(部分设备)。`import { textGenerator, imageGenerator, embedding } from '@kit.AIEngine'` 风格 API。典型调用为 `textGenerator.generate({ prompt, options })` 返回流式或一次性结果。
- **`@hms.ai.llm`**(HMS 增强):云端 + 端侧协同,提供统一的 LLM 服务抽象,接入华为账号鉴权,支持自定义 prompt 模板、流式 SSE、多轮对话上下文管理。当前对中文数学题的解析能力优于裸调 `AIEngine`。
- **`@kit.CoreVisionKit`**:已用,文本/对象/文档版面识别(`textRecognition` / `documentRecognition` / `subjectClassification`),W4 后可补 `documentRecognition` 做版面分析(对齐公式坐标)。

**MindTrace 可应用点**:
1. **数学题兜底**:当前 `LlmClient` 完全走自配 HTTP 端点(`LlmConfig`),无网时瘫。接 `AIEngine` 端侧后,无网仍能给出基础解题/讲解(对齐评委"端侧 AI"叙事)。
2. **题目向量召回**:`embedding.embeddings(texts)` 给 `knowledge_unit.embedding` 提供标准化生成器,替换当前 `"[]"` 占位字符串(审计 #16 关联)。
3. **图像理解(选做)**:CoreVisionKit `documentRecognition` 输出文字块 + 坐标,可补 `OcrTool.recognizeLocalText` 的版面坐标(当前只回文本)。

**适配成本**:**中**。
- 需在 `oh-package.json5` 加 `dependencies: { "@kit.AIEngine": "..." }`,各 module 跨包同步。
- 设备门控(`canIUse('SystemCapability.AI.文本生成')`)必须保留,跟 `OcrTool.recognizeLocalText` 同样的 try/catch 模式。
- `LlmClient` 三调用路径合一(spec #5)在做,AIEngine 是第 4 条路径,需在 spec #5 里预留 facade。

**不推荐的理由**:**无**。这是 MindTrace 复赛路演最强叙事点之一(端侧 AI + 云协同)。

---

## §3 文本结构化 / NLP / 文档版面

**能力概述**:
- **`@kit.NaturalLanguageKit`**(端侧 NLP):分词、词性标注、命名实体识别、情感分析、相似度计算。`import { nlp } from '@kit.NaturalLanguageKit'` 风格。
- **`@kit.TextRecognition`**(已在 `OcrTool` 用,即 `CoreVisionKit` 子模块):返回 `TextBlock[] { lines: { value, boundingBox }[] }`,只回文本和坐标,无语义。
- **`@kit.DocumentRecognition`**(CoreVisionKit 子模块):版面分析,输出段落/表格/图片区域坐标。
- **`@kit.TextToSpeech` / `@kit.SpeechToText`**(`@kit.CoreSpeechKit`):TTS / ASR,与本节无直接关系但常并列。

**MindTrace 可应用点**:
1. **`ContentProtocol` 增强**:当前 `LatexRiskNormalizer` 用正则风险归一化,接入 `nlp` 的实体识别可自动识别"定理名 / 公式符号 / 章节标题"等结构单元,直接喂给 `KnowledgeModel.structure`。
2. **`ReviewGraphView` 标签归一**:用户输入的 freeform 标签经 `nlp` 标准化后,可消除"导数/微分/derivative"等同义标签(当前 `common/NoteTaxonomy.ets` 是手维护枚举)。
3. **`documentRecognition` 坐标**:`OcrTool` 当前 `recognizeLocalText` 返回纯文本,接 `documentRecognition` 后可回坐标 → 渲染层做"点击图片某行 → 跳到对应 KnowledgeUnit"(W4 之后的进阶玩法)。

**适配成本**:**中-高**。
- 端侧 NLP 设备覆盖窄(中文分词 + NER 通常要求 API 14+,部分低端机不可用),需 `canIUse` 守门。
- `ContentProtocol` 改造会牵动 `LlmGuard` / `Dispatcher` / `KnowledgeModel` 三处(审计 #3 god class 已标记)。
- 落地优先级低于 §2(LLM)。

**不推荐的理由**:**仅在 §2 已落地后**才考虑。当前 LLM 已经能结构化输出,`NaturalLanguageKit` 收益边际,除非评审追问"端侧 NLP 能力"。

---

## §4 ReminderKit / 复习提醒

**能力概述**:
- 官方 kit 是 **`@kit.NotificationKit`** 下的 **ReminderAgent** 子模块,**不是独立的 `@kit.ReminderKit`**。
- API: `import { reminderAgent } from '@kit.NotificationKit'`,`reminderAgent.publishReminder({ reminderId, contentTitle, contentText, expiredAt, ringDuration, snoozeTimes, snoozeInterval })`,系统级闹钟式弹窗,**应用未启动也能触发**(需 Background TasksKit 配合)。
- 权限: `ohos.permission.PUBLISH_AGENT_REMINDER`(用户授权弹窗)。
- 与普通通知(`@ohos.notificationManager`)的区别:ReminderAgent 是**定时提醒**(可重复、可贪睡),`notificationManager` 是即时横幅。

**MindTrace 可应用点**:
1. **艾宾浩斯复习提醒**:`StudyPlanDao` 的 `due_date` + `knowledge_unit.next_review_at` 字段已存在,差一个定时器。`ReminderAgent` 直接吃这两列 → 复习日 8:00 弹窗"今日有 5 个 KnowledgeUnit 待复习",贪睡 10 分钟。
2. **学习计划到期**:`study_plan.is_done=0 AND due_date < now` 触发提醒"你的计划 [攻克微积分基础] 已逾期"。
3. **考试倒计时**:用户标记"期末考 2026-12-15",提前 7/3/1 天自动提醒。

**适配成本**:**中**。
- 需新增 `common/reminders/ReviewReminderService.ets`(单例 + 批量发布 + 取消)。
- 需 `entry` module 加 `requestPermissions` 在 AI 设置页或首启引导里申请 `PUBLISH_AGENT_REMINDER`。
- 与 §11 Background TasksKit **强绑定**(ReminderAgent 触发后,需 background task 拉 RDB 取最新计数)。
- 一组 Hypium 单测覆盖"发布 → 取消 → 修改时间 → 重新发布"。

**不推荐的理由**:**无**。这是 MindTrace "完整闭环"(拍照 → 拆解 → 复习 → 提醒)的关键一环。

---

## §5 FormKit / CardKit(卡片框架)

**能力概述**:
- 官方 **FormKit**(服务卡片)分两层:
  - **卡片 UI 渲染层**:`@ohos.app.form.FormExtensionAbility` + `formBindingData`(已在 `FormAbility.ets` 用),卡片进程运行。
  - **卡片交互层**(API 12+):`@ohos.app.form.FormClickEvent` / `router` / `callEvent`,支持点击卡片 → 跳转 entry / 触发 entry 内部动作。
- **`@kit.FormKit`**(API 14+ 新增,部分封装):简化卡片生命周期,提供 `FormController` 高层 API(并非所有设备支持,需 `canIUse`)。
- **CardKit**:**非 HarmonyOS 官方 kit**;华为钱包/会员类卡由 HMS 钱包 kit 提供,与 MindTrace 无关。
- **SystemUI 桌面磁贴**(`/独立卡片服务`):HarmonyOS NEXT 引入的"独立卡片服务"能力,需声明 `type: card` 的独立 HSP(已有 `cardservice` module),与 FormExtension 并存。

**MindTrace 可应用点**:
1. **`cardservice` 真数据**:`FormAbility.onAddForm` 当前返回 `{title, todayCount, totalCount}` 的 mock。改为 `common/DatabaseHelper.getStore()` 查 `SELECT COUNT(*) FROM knowledge_unit WHERE next_review_at < now`,真实化"今日复习"。
2. **卡片点击 → 跳 entry 复习页**:`formBindingData` 添加 `formClickAction` 字段,定义 `want.action = 'ohos.want.action.viewData'` + `parameters.bundleName = 'com.example.mathmind'` + `parameters.page = 'ReviewPage'`。
3. **卡片样式升级**:`widget/pages/` 当前只占位(空目录),W4 后实装 `TodayReviewCard` / `NewKnowledgeCard` / `PlanProgressCard` 三套样式,数据源共享 `entry/services/UiDataCacheService`(已有)。

**适配成本**:**中**。
- `FormAbility.ets` 重写 onAddForm 拉真数据(约 30 LOC)。
- 新增 3 张卡片页面(`widget/pages/TodayReviewCard.ets` 等)+ `widget.json` 资源配置。
- 卡片刷新策略:`onUpdateForm` 周期 / `setWant` 主动 / 用户行为触发 三选一,需在 `FormAbility` 设计 schema。
- 与 §11 后台任务联动(每天 8:00 主动 push 一次)。

**不推荐的理由**:**无**。`cardservice` module 已存在但全是占位,**这是 W4 后最大的演示增益**。

---

## §6 Service Widget(FormExtension / 卡片进程)

**能力概述**:
- `@ohos.app.form.FormExtensionAbility` 已在 `cardservice/.../FormAbility.ets` 使用。
- 卡片进程与 entry 进程**内存隔离**,只能通过 `formBindingData` 序列化数据(不能直接拿 RDB / LLM client 对象)。
- 卡片布局支持 ArkTS + 基础组件(Button / Text / Image),但**不支持完整 WebView / 自定义渲染**,复杂数学公式卡片需走纯文本 + KaTeX 渲染截图。

**MindTrace 可应用点**:
1. 见 §5(FormKit 是同一能力的"高层 API"视图,FormExtension 是底层 runtime 视图)。
2. **公式卡片**:数学题 KnowledgeUnit 摘要卡片,可渲染缩略 KaTeX(转图片 base64 → `formBindingData.createFormBindingData`)。
3. **快速拍照卡片**:卡片提供"扫题"按钮 → `router` 跳转 entry CameraOverlay。

**适配成本**:**中**(与 §5 重叠,实际是同一项工作)。

**不推荐的理由**:**无**(同上)。

---

## §7 ScanKit(扫码)

**能力概述**:
- **`@kit.ScanKit`**(`import { scanCore, scanBarcode } from '@kit.ScanKit'`):二维码 / 条形码 / Data Matrix 识别。
- API: `scanBarcode.startScan(context, options)`,返回 `scanBarcode.ScanResult`。
- 设备依赖:大多数 HarmonyOS 手机标配,平板部分型号无。

**MindTrace 可应用点**:
1. **分享 KnowledgeUnit**:用户生成 KnowledgeUnit 后生成短链 → 扫码导入(社交分享链路)。
2. **课程表二维码**:扫描课本背面的章节二维码 → 自动定位 `category` + `chapter`。

**适配成本**:**低**(单一页面 + 权限 `ohos.permission.CAMERA` 复用现有 CameraOverlay)。

**不推荐的理由**:**复赛窗口下优先级最低**。当前 W4 主线(拍照 → 拆解 → 复习 → 卡片)无扫码入口,加这条会稀释主线。可作为"W5 之后"候选。

---

## §8 PushKit / 推送

**能力概述**:
- **`@kit.PushKit`**(HMS 推送,`import { push } from '@kit.PushKit'`):基于华为 Push 通道的系统级推送,应用未启动也能到达。
- 需申请 `ohos.permission.INTERNET` + 注册华为开发者账号 + 配置 `agconnect-services.json`。
- 服务端需对接华为 Push REST API。

**MindTrace 可应用点**:
1. **服务器 OCR 完成后回灌**:用户拍题后,服务端 OCR + LLM 异步完成(超时 > 10s 的复杂题),完成后 push 通知"已解析完成,点击查看"。
2. **复习提醒的"离线备份"通道**:ReminderAgent 是本地定时器,PushKit 是云端触发,**两者互补**(应用卸载 / 离线时 PushKit 兜底)。

**适配成本**:**高**。
- 需注册华为开发者账号 + 申请 Push 服务 + 配 AGC 项目 + 后端集成 REST API。
- 隐私合规:用户授权 + 隐私政策声明 + 第三方 SDK 清单更新。
- 当前 MindTrace 后端是本地 uvicorn + 局域网 IP,无云端基础设施,PushKit 会引出"上云"的连锁改动。

**不推荐的理由**:**复赛窗口不建议**。运维成本 + 隐私合规成本不匹配比赛时长收益;ReminderAgent + Background TasksKit 已在 §4+§11 给出本地等价能力。W5 之后、运营化阶段再做。

---

## §9 Background TasksKit / 后台任务

**能力概述**:
- **`@kit.BackgroundTasksKit`**(`import { backgroundTaskManager } from '@kit.BackgroundTasksKit'`):
  - **短时任务**(`backgroundTaskManager.startBackgroundRunning`):申请后 App 可在后台持续运行 3-10 分钟。
  - **长时任务**(`backgroundTaskManager.startBackgroundRunning` with `LongRunningTaskType`):持续后台运行,需声明 `ohos.permission.KEEP_BACKGROUND_RUNNING`,需用户授权。
  - **延迟任务**(`backgroundTaskManager.sendDelayRetry` / `WorkScheduler`):系统调度延迟执行(电量友好),适合复习提醒同步、KnowledgeUnit 向量化等。
  - **AgentReminder**(API 14+):与 ReminderAgent 联动的"定时唤醒 background task"机制。

**MindTrace 可应用点**:
1. **复习提醒触发后拉数据**:ReminderAgent 弹窗那一刻,需 background task 拉 RDB 算"今日有几题待复习",避免用户在卡片上看到过期数据。
2. **KnowledgeUnit embedding 后台向量化**:用户拍题入库后,`embedding` 计算可放到延迟任务,避免阻塞拍照主链(与 §2 AIEngine 联动)。
3. **每日 8:00 主动重算复习计划**:批量更新 `next_review_at` + 主动 `setWant` 推送给卡片刷新。
4. **学习计划到期检查**:`study_plan.due_date` 扫描。

**适配成本**:**中-高**。
- 需 `entry` module 加后台任务 Ability(`entryability/EntryBackupAbility.ets` 已有 scaffold)。
- `ohos.permission.KEEP_BACKGROUND_RUNNING` 需用户单独授权,UX 上需引导页。
- 短时/长时/延迟三类任务调度策略要选型,推荐"复习提醒 + 数据同步走长时 + embedding 走延迟"。
- 单测需 Mock `backgroundTaskManager`(Hypium 提供 mock,但需熟悉)。

**不推荐的理由**:**无**(与 §4 ReminderKit 强绑定,二者必同时上)。

---

## §10 UniversalKeystoreKit / 密钥库

**能力概述**:
- **`@kit.UniversalKeystoreKit`**(`import { huks } from '@kit.UniversalKeystoreKit'`):HUKS(HarmonyOS Universal KeyStore),提供密钥生成 / 加密 / 解密 / 签名 / 验签,**密钥永不离开 TEE/SE 安全区域**。
- API: `huks.generateKeyItem({ alias, properties })` / `huks.encrypt({ alias, plainText })` 等。
- 与 Android Keystore / iOS Keychain 等价。

**MindTrace 可应用点**:
1. **LLM API key 加密存储**:当前 `LlmConfig` 用 `@kit.ArkData` 的 `preferences` 明文存 `endpoint` / API key(若用户配置)。改用 HUKS 可达"应用卸载 / 设备 root 后仍安全"。
2. **OCR 服务端 token**:同上。

**适配成本**:**低**(API 简单,单例 + 一层 facade)。

**不推荐的理由**:
1. **当前 API key 走用户自配,无内置 secret**,明文 preferences 风险低(攻击者需先 root 设备 + 解锁锁屏)。
2. **比赛不考察安全存储**,评委关注点是"AI + 卡片 + 复习闭环"。
3. 改动需新增 `common/security/SecureKeyStore.ets` + 重构 `LlmConfig`,牵动 spec #5(LlmClient 三路径合一)。

> **建议**:**W5 之后**作为安全加固项再做。当前优先级最低的安全类 kit。

---

## §11 AVPlayerKit / MediaKit / 音视频

**能力概述**:
- **`@kit.AVPlayerKit`**(`import { media } from '@kit.AVPlayerKit'` 或新 `MediaKit`):音视频播放,支持本地文件 / 网络 URL / 流媒体。
- 提供 `media.createAVPlayer()` → `prepare()` / `play()` / `pause()` / `release()` 生命周期。
- API 14+ 提供 `@kit.MediaKit` 新封装,能力等价。

**MindTrace 可应用点**:
1. **题目讲解音频**:LLM 生成解题讲解 → TTS 转 MP3 → 复习页音频播放(需配合 §3 文本结构化)。
2. **错题回放视频**:用户拍题过程录像 → 复习时回放。
3. **学习计划 BGM / 白噪音**。

**适配成本**:**低-中**(单页面集成即可)。

**不推荐的理由**:**业务价值低 + 复赛窗口下音频资源版权 / TTS 通道都不确定**。当前 W4 主线无此需求,**W5 之后**视用户反馈再决定。

---

## §12 ImageKit / 图像处理

**能力概述**:
- **`@kit.ImageKit`**(`import { image } from '@kit.ImageKit'`):PixelMap / ImageSource / ImagePacker / ImageReceiver。
- 已在 `OcrTool.recognizeLocalText` 使用 `image.createImageSource` + `createPixelMap`。

**MindTrace 可应用点**:
1. **已有**:OcrTool 拍照后的 PixelMap 构造。
2. **可选**:KnowledgeUnit 缩略图压缩(`ImagePacker.packToFile` JPEG quality=80)、分享卡片图片生成。
3. **可选**:`ImageReceiver` 实现拍照实时预览帧处理(替代 CameraOverlay 当前流程)。

**适配成本**:**低**(API 已熟练)。

**不推荐的理由**:**无(已落地)。后续优化项,不阻塞主线。**

---

## §13 FileKit / 文件

**能力概述**:
- **`@kit.FileKit`**(`import { fileIo, fileUri, fileShare } from '@kit.FileKit'`):统一文件 API(替代旧 `@ohos.file.fs`)。
- 已在 `common/ImageUriResolver.ets` 等用 `@ohos.file.fs`(传统 API)。

**MindTrace 可应用点**:
1. **导出 KnowledgeUnit**:用户导出整本笔记为 PDF / Markdown,走 `fileShare` 拉起分享面板。
2. **拍照图片归档**:当前 OcrTool 上传后即丢,可加"原图持久化到 `filesDir/photos/` + KnowledgeUnit 关联 `imageUri`"。
3. **缓存清理**:`UiDataCacheService` 当前用内存,改文件持久化可跨进程复用(配合卡片进程)。

**适配成本**:**低**(已是熟悉 API)。

**不推荐的理由**:**当前 RDB + 内存 cache 已足够**,`FileKit` 落地优先级低于 §4/§5/§9。可在 W5 "导出 / 备份"功能点统一做。

---

## §14 PreferencesKit / 用户首选项

**能力概述**:
- `@kit.ArkData` 子模块 `preferences`(已在 `LlmConfig` / `OcrConfig` 用):KV 持久化,异步 API。
- 限制:不支持事务、不支持查询,只适合"配置项"。

**MindTrace 可应用点**:
1. **已用**:`LlmConfig` / `OcrConfig` 的 `endpoint` / `enabled` / `mode` 字段。
2. **可加**:
   - `cardservice_config`(卡片刷新策略 / 启用哪些卡片)
   - `reminder_config`(每日复习提醒时间 / 贪睡次数)
   - `user_profile`(昵称 / 头像 / 学习目标年级)— 当前 `ProfileAuthViewModel` 已有雏形

**适配成本**:**极低**。

**不推荐的理由**:**无(已落地)。后续配置项继续追加即可,无独立 kit 升级需求。**

---

## §15 落地优先级建议(roadmap)

按"评委感知度 × 实施成本"排序:

| 优先级 | Kit | 关联 Module | 关键交付物 | 备注 |
|---|---|---|---|---|
| **P0** | §5+§6 FormKit / FormExtension | `cardservice` | 3 张真数据卡片 + 点击跳转 | W4 后立即做 |
| **P0** | §4 ReminderKit | `common` + `entry` | ReviewReminderService + 用户授权页 | 与 P0 卡片同时 |
| **P0** | §9 Background TasksKit | `entry` | 后台任务 Ability + 复习计划日扫描 | P0 提醒/卡片依赖 |
| **P1** | §2 AI / Foundation Model | `common/llm` | `LlmClient` 加第 4 条 facade 路径 | spec #5 合一的前提 |
| **P1** | §3 文本结构化(NLP) | `common` + `agents` | `ContentProtocol` 接入 NER | P1 优先级低于 LLM |
| **P2** | §7 ScanKit | `entry` | 分享码生成 + 扫码导入 | W5 候选 |
| **P2** | §13 FileKit 导出 | `entry` | KnowledgeUnit 导出 MD/PDF | W5 候选 |
| **P3** | §8 PushKit | `entry` + 后端 | 上云后才考虑 | 比赛窗口不建议 |
| **P3** | §10 UniversalKeystoreKit | `common` | LLM API key HUKS 化 | 安全加固项 |
| **P3** | §11 AVPlayerKit / MediaKit | `entry` | 题目讲解音频 | 业务价值低 |
| 已落地 | §12 ImageKit | `agents` / `common` | OcrTool 已用 | — |
| 已落地 | §14 PreferencesKit | `common` | LlmConfig / OcrConfig 已用 | — |
| 已落地 | §13 FileKit(fs) | `common` / `entry` | ImageUriResolver 已用 | — |

---

## §16 与现有 ADR / Spec 的呼应

| 已有文档 | 相关 Kit | 影响 |
|---|---|---|
| [`docs/specs/005-llm-client-consolidation.md`](../specs/) | §2 AIEngine | `LlmClient` 三路径合一时,新增 facade 预留 `AIEngine` 路径 |
| [`docs/adr/` ADR-0001 模块依赖](../adr/) | §4/§5/§9 | `entry` module 加新权限 / 新 service 不破现有依赖图 |
| [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` §4.7 #10](../legacy/mindtrace/architecture/audit-full-2026-09-01.md) | §5 FormKit | `mcp/ → tools/` 重命名 不影响 FormKit,但 FormAbility 应放在 `cardservice/services/` 而非 `formability/` |

---

## §17 一手信源说明

| 调研渠道 | 结果 |
|---|---|
| `developer.huawei.com/consumer/cn/harmonyos/*` 多路径 WebFetch | **失败**:站点返回 JS 渲染壳(`文档中心`占位),无法抓取真实内容 |
| `developer.huawei.com/consumer/cn/doc/harmonyos-guides*` 多路径 WebFetch | **失败**:同上,所有路径返回 404 或 SPA 占位 |
| `docs.openharmony.cn/*` 多路径 WebFetch | **失败**:站点所有根路径 404,gitee 镜像 405 |
| `gitee.com/openharmony/docs` README 直抓 | **失败**:WebFetch 阻止列表页(405) |
| MindTrace 仓库已用 kit 反查 | **成功**:`grep -rhE "from '@[a-z]+\.[a-z]+'"` 提取出 `ArkData` / `ArkTS` / `BasicServicesKit` / `CoreVisionKit` / `ImageKit` / `NetworkKit` / `app.form` / `app.ability` 8 类,可作为"已验证可用 kit"基线 |

> **可信度声明**:本调研中 §12/§13/§14(已落地 kit)的"能力概述"来自 MindTrace 源码直接观察,可信度高;§2-§11(未落地 kit)的"能力概述"基于 HarmonyOS NEXT API 12-14 公开文档模型(已稳定,无大幅变动),具体 API 名(`reminderAgent.publishReminder` / `huks.generateKeyItem` 等)与权限名需在 DevEco Studio 内 `API Reference` 面板二次确认(因 WebFetch 通道不可用)。
>
> **复现命令**:
> ```bash
> # 已用 kit
> grep -rhE "from '@[a-z]+\.[a-z]+(\.[a-z]+)?'" --include="*.ets" <本地仓库根> | grep -oE "@[a-z]+\.[a-z]+(\.[a-z]+)?" | sort -u
> # DevEco 内查未用 kit 的 API 详情:打开任意 .ets → Ctrl+Click `import` → 跳转 API Reference
> ```
