# KnowledgeModel 第一阶段行为基线

> #210 / 父项 #209：为行为保持的内部文件提取提供可执行验收，不提前实施 #211–#215。

## Seam 与运行方式

最高行为 Seam 是 `Dispatcher.dispatch`。测试加载真实 Dispatcher、CaptureGraph、节点、KnowledgeModel、GenerationJsonCaller、TruthCheckService 和 common 归一化实现；不注入假的 KnowledgeModel，也不访问 private 字段或方法。

`knowledge-dispatch-runtime.mjs` 复用现有 ETS loader，以真实 common 公共导出建立惰性加载桥。只替换系统边界：LLM 传输、HarmonyOS 平台 IO，以及传入的 DAO / generation repository。每项测试有独立模块缓存，不共享配置单例。禁止真实网络或平台 IO；未预期调用会抛错。

以下兼容性 characterization 暂留在 KnowledgeModel 现有公开 Interface：

- `structureLightDraft`：错误 kind / retriable / cause；DispatchResult 不公开这些完整字段。
- `structureDeepDraft`：用超长合成来源验证 ledger 限制，绕过 Dispatcher 对不自然来源文本的 preflight。正常 deep 多源流程仍在 dispatch 验证。

从仓库根目录运行：

```sh
node --test scripts/arkts-lint/tests/knowledge-dispatch-baseline.test.mjs scripts/arkts-lint/tests/knowledge-ownership.test.mjs
npm --prefix scripts/arkts-lint test
```

两份测试均已加入默认 npm 测试列表。行为测试不绑定内部 Module 的文件名、私有字段、实例身份或协作调用顺序；外部传输重试上限、持久化先后及公开 artifact schema 属于需保持的行为。#213–#215 另增静态架构守卫检查实现归属与 facade 委托；这类守卫随架构决策更新，不替代行为验收。

## 验收矩阵

| #210 验收项 | 可执行基线 |
|---|---|
| Capture 成功、失败与错误分类 | 分类、正文和原文保留；分类器 LLM 失败走 fallback 仍可继续；结构化 JSON 错误带分类上下文返回失败且零写入；DAO 抛错时返回失败，不伪造成功结果 |
| 分析零写入 | analysisOnly 返回分类与识别文本，不结构化、不写 DAO |
| TruthCheck 短路 | hash / checkpoint 合法但空正文的候选被拒绝，不落笔记或 commit receipt |
| 持久化顺序 | preview 不写 DAO；确认先 durable insert 再 receipt；重复确认只写一次且不重新生成 |
| light fallback | 空 section 正文回退真实来源；prepare → compose 的进度结果 |
| standard evidence | 缺失 attribution 由真实来源补齐、pipeline origin 保留、verifier position 映射回 evidence ID |
| verifier 完整性 | 不完整结果重试后可恢复；持续缺失覆盖时 needs-input / VERIFIER_UNAVAILABLE，不变成可用预览 |
| deep 多 section | 两来源映射、公式归一化、独立验证、write_section 与 verify 进度 |
| deep ledger | formula / conclusion value 上限 160、术语上限 24、结论按所属来源记录且无重复 |
| incremental | 用户修改的定义段按字面保留，只替换目标例子段；锁定段越权 patch 被 DOMAIN_VALIDATION_ERROR 拒绝；无 DAO 写入 |
| 取消 | 入口已取消无副作用；传输收到同一 token；途中取消不得生成 checkpoint 或持久化 |
| token / timeout | Capture 分类 8000 / 120 秒；结构化 12000 / 300 秒；light 1200、standard 6000、deep section 4800、verifier 2600、incremental 2400，生成请求均 300 秒 |
| LLM 错误 | NETWORK_ERROR / TIMEOUT / STREAM_FAILED 可重试，API_ERROR 不可重试；传输层不在 JSON guard 内重试 |
| JSON / 截断 | extraction / schema 守门最多三次；截断不可重试且不得成为部分预览 |
| 所有权 | 扫描五个模块的整个 src/main；entry 禁止 CaptureGraph / AgentState 依赖，TruthCheck 方法使用仅限自身和 TruthCheckNode |

## 所有权守卫的灵敏度

`knowledge-ownership-guard.mjs` 用 TypeScript AST / symbol resolution 检查所有生产源码，不按未来 Composer 名称建白名单，也不靠固定 owner 文件路径判定 `AgentState` / `CaptureGraph` / `TruthCheckService`。守卫先从当前源码里的导出声明发现 owner 符号，再检查引用是否越过边界；路径只用于定位允许调用 TruthCheck 的 `TruthCheckNode`。

自测包含命名别名、type import、barrel、namespace、字符串属性访问、方法引用，以及未来新增文件的越权调用。反例允许 Dispatcher 构造服务、节点调用、同名无关方法和注释。字符串属性访问反例先出现失败，再补守卫逻辑转绿；不是只证明当前仓库无违规。

这不是完整 ArkTS 编译器或动态污点分析：ArkUI 特有语法的 TS 诊断不作为编译结果；动态计算属性名、反射等不在守卫能力内。

## 必须保持的现状与验证边界

- 第一阶段不统一错误外观：入口取消抛 `CONVERSATION_CANCELLED`；light 途中取消返回失败、issue code 为 `NODE_ERROR`；incremental 越权 patch 的领域错误直接向外抛出。
- standard / deep 当前是只读独立验证，无自动修复循环。历史 Hypium 深度诊断用例中的 `repeated_issue_fingerprint` 不代表当前生产行为，本票不恢复该循环。
- 业务基线是 characterization，直接通过如实记录；不修改生产代码制造红灯。
- Node 执行的是转译后的真实业务代码，不是 ArkTS 静态类型检查。HAP 构建与 Hypium / 真机验收必须分别报告。
- 超时断言锁定传输请求参数及 TIMEOUT 错误分类，不模拟真实网络等待 300 秒。
- 此处只验证文字 Capture；相机、OCR 平台 API、真实 LLM、RDB 原子性、签名安装与 UI 冒烟仍需要各自的集成 / 真机验证。agents/common 当前 build-profile 仅有 default target。

## 本票本地验证记录

- 基准提交：`2302b35c114ef09d62aa6feb05351610c21fb980`；未改生产代码。
- 聚焦测试：34 / 34 通过（24 项行为基线，10 项守卫 / 守卫自测）。
- 完整默认 `npm --prefix scripts/arkts-lint test`：312 / 312 通过，无跳过。
- 四份新增 `.mjs` 的 `node --check`、ArkTS lint、naming-lint 与 `git diff --check` 通过。
- hvigor `--no-daemon --mode module -p product=default assembleHap`：BUILD SUCCESSFUL；存在现有 API 弃用等警告；未配置 signingConfigs，跳过签名。
- 未执行 Hypium 设备测试、真实网络 / OCR / RDB 集成或 UI 冒烟；不把 Node 或 HAP 构建结果记作这些验收通过。
- 实现验证后停在仓库规定的 code-review 确认点；未 staging、commit 或 push。

## #215 第一阶段集成证据（2026-10-13）

**状态：三模块已注册 Hypium 415/415、Node 318/318、补充检查 7/7、静态检查及完整构建通过。联网 light/standard/deep 预览、standard/deep 保存和取消已实测；增量 UI 被既有公式一致性误报阻塞（见末节）。整票尚未验收，不应关闭 #215。**

检查对象为 `e07e7fe0ee63c0770d0d1bde6ae7152d6114f608` 加当前 #213–#215 工作区改动，包含四个新增内部文件；未提交。该参照点已包含 #210–#212，不能把它当作整个第一阶段之前的版本。#210 原始基准见上节。

### 唯一生产路径与所有权

| 兼容 Interface | 内部 Implementation 的唯一所有者 |
|---|---|
| `structure` / `structureWithClassification` | `CaptureStructurer`：hint、classic JSON、归一化、KnowledgeUnit 投影 |
| `structureLightDraft` / `structureStandardDraft` | `DraftComposer`：light/standard 草稿与 artifact 组合 |
| `structureDeepDraft` | `DeepDraftComposer`：分段、outline、顺序 section、ledger、pipeline evidence |
| `repairIncrementalSections` | `IncrementalPatchComposer`：计划目标/source 筛选、JSON 调用与 patch 校验 |
| `draftToKnowledgeUnit` | `CaptureStructurer`：草稿字段映射复用既有 KnowledgeUnit 投影 |
| standard/deep 只读验证 | `NoteDraftVerifier`；不持久化、不生成替换草稿 |

`KnowledgeModel` 的七个既有方法现在仅返回协作者结果；草稿投影迁移前后锁定相同正文、summary、分类、来源、时间及初始复习计划。将投影置于已有 `toKnowledgeUnit` 所有者旁，避免新增另一套投影规则；这是第一阶段内部 Locality 收口，不是生成业务外部 Interface 分离。

四个业务 Module 未向 `agents/Index.ets` 导出，entry 没有直接调用它们。生产引用保持 `Dispatcher / StructureNode → KnowledgeModel → 内部 Module` 的单向关系；entry 的 Order 仍进入 `Dispatcher.dispatch`，TruthCheck 调用继续只由 `TruthCheckNode` 所有。旧 deep/incremental/verifier 主体已从 `DraftComposer` 删除。Capture 中遗留的未使用 deep ledger/生成提示常量和导入已清理，实际生成数学提示仍由 `GenerationDraftSupport` 承载。

### 本轮可复现验证

- 默认 Node 全套：`npm --prefix scripts/arkts-lint test`，**318/318**，0 fail、0 skip。其中行为基线 28 项、架构守卫 12 项。
- 补充静态检查：`node --test scripts/arkts-lint/tests/deep-note-generation.test.mjs scripts/arkts-lint/tests/incremental-regeneration.test.mjs`，**7/7**。
- `node scripts/arkts-lint/index.mjs --quiet`、`node scripts/naming-lint/index.mjs`、`git diff --check` 通过。
- DevEco 自带 hvigor：`--no-daemon --mode module -p product=default assembleHap`，**BUILD SUCCESSFUL**，含 ArkTS 编译。工具来自本机 DevEco 安装，设置 `DEVECO_SDK_HOME`、`JAVA_HOME` 后调用其自带 Node/hvigor；不修改仓库 SDK 配置。存在编译警告，未配置签名，产物为 `entry/build/default/outputs/default/entry-default-unsigned.hap`。
- 新增投影 characterization 在移动前先通过；“七个兼容方法仅委托”的静态守卫先失败于 `draftToKnowledgeUnit`，移动后通过。
- light/standard/deep 均经真实 `Dispatcher.dispatch` 验证 preview 零 DAO 写入、checkpoint 保存、确认先 durable insert 后 commit receipt、重复确认不再生成/写入。此处 DAO 是传输外侧的内存 Adapter，不证明真实 RDB 原子性。
- 原基线中的 Capture、light fallback、standard verifier、deep 顺序/source/ledger、增量锁定段、错误分类、取消与预算检查继续通过。没有改变 prompt、重试、JSON 契约、取消语义或恢复 deep 自动修复。

### 首轮尚未通过的验收门（设备启动前的记录）

1. **Hypium 未运行**。`hdc list targets` 返回 `[Empty]`。`agents/src/test/List.test.ets`、`common/src/test/List.test.ets` 与 `entry/src/test/List.test.ets` 是相关套件入口；生产 `assembleHap` 不等于这些测试执行。entry 的 `ohosTest` 入口目前只接 Ability 与 ChatPersistenceCapabilityDevice，不能只运行它就宣称上述业务套件全绿。
2. **已有 Hypium 漂移需核实**：`entry/src/test/DispatcherNoteGeneration.test.ets` 的 `exposes complete deep diagnostics without truncating issue details` 仍断言 `repeated_issue_fingerprint`；当前 Dispatcher 的只读结束分支不返回该值。此项早于本次提取，尚未通过 Hypium 实际运行核实其它断言；不得为了让旧测试通过恢复生产自动修复。
3. **目标设备重点路径未执行**。没有联网模型、OCR、真实 RDB、签名安装或 UI 验收证据，不能以 Node 测试代替。

设备可用后需补齐：记录设备型号/系统、被测代码版本、测试报告与失败用例；使用相同输入和配置对照 #210 前基准与当前版本。重点检查文字/照片 Capture（分析与保存）、light/standard/deep 预览与确认、增量改写保留用户锁定段、生成途中取消、验证失败零保存、重复确认不重复落库。LLM 文本有随机性，比较的是协议、source/provenance、错误/进度、用户编辑保留和写入时序，不要求自然语言逐字一致。另按 `docs/agents/smoke-test.md` 执行 UI 冒烟。

### 第二阶段 Interface 建议（非批准的后续实施）

**当前不值得立即拆掉 KnowledgeModel 的生成外部 Interface。** 内部 Implementation 已按业务形成 Locality，而实际生产消费集中在 Dispatcher / StructureNode；尚无独立生成调用方需要新的公开 Seam，设备稳定性门也未完成。仅为减少 facade 转发而迁移调用方，现阶段新增成本大于已证明的 Leverage。

值得另立 spec 评估的触发条件是：出现真正独立的生成消费者，或 Dispatcher 的构造/测试注入必须依赖继承 KnowledgeModel、持续导致测试维护成本。届时可比较更窄的 composition Interface 与构造注入；先补齐本票 Hypium/设备证据，再按 #209 要求形成新决策或获批准 spec。本票不改 Dispatcher、公开导出、路由 registry 或现有测试替身协议。

### 设备启动后的复测（2026-10-13）

- 目标：`127.0.0.1:5555`；`const.product.model=emulator`，系统 `OpenHarmony-6.1.1.125`。这是模拟器，不记作物理真机验收。
- 将已有 `DispatcherNoteGeneration.test.ets`、`IncrementalRegeneration.test.ets` 接入 `entry/src/ohosTest/ets/test/List.test.ets`，未改用例断言或生产代码。
- hvigor `--no-daemon --mode module -p product=default -p module=entry@ohosTest assembleHap`：BUILD SUCCESSFUL（未签名，有警告）。随后用 `hdc install -r` 更新本次构建的 entry ohosTest HAP、common HSP、agents HSP；三包安装成功，未卸载或清除应用数据。
- 实际设备命令：`hdc -t 127.0.0.1:5555 shell aa test -b com.example.mathmind -m entry_test -s unittest OpenHarmonyTestRunner -s class 'Dispatcher.note_generation,IncrementalRegeneration.issue104_incremental_regeneration' -s timeout 15000 -w 60`。
- Hypium 报告：`Tests run: 23, Failure: 2, Error: 0, Pass: 21, Ignore: 0`。以报告为准；工具进程 exit code / `TestFinished-ResultCode: 0` 不表示断言全部通过。
- `IncrementalRegeneration.issue104_incremental_regeneration`：7/7 通过。
- `Dispatcher.note_generation`：14/16 通过，失败如下：
  - `passes requested section titles from instruction into deep generation`：`entry/src/test/DispatcherNoteGeneration.test.ets:996`，`result.success` 实际为 false，期望 true；未进一步裁定是 fixture 漂移还是产品问题，不将它自动归因于本次重构。
  - `exposes complete deep diagnostics without truncating issue details`：同文件第 1100 行，实际 `artifact_validation_failed`，期望 `repeated_issue_fingerprint`，确认此前记录的旧停止原因断言漂移。
- 本轮只运行以上两个套件，Dispatcher 用例包含 KnowledgeModel 测试替身；不能据此宣称真实 Composer 的全套 Hypium、真实 LLM/OCR/RDB、UI 冒烟或基准版本对照已经通过。`agents/src/test/KnowledgeModelNoteGeneration.test.ets` 等剩余套件仍需单独执行。#215 保持未验收；未改生产逻辑来迎合失败断言，未提交或 push。

### 扩展设备回归与失败定位（2026-10-13）

本节接续上面的历史失败记录，不覆盖原始观测。目标仍为 OpenHarmony 6.1.1.125 模拟器；本轮只修改测试与测试打包入口，没有为失败断言改变生产行为。

#### 已修复的测试问题

- 指定 deep 章节用例：标题传递正确，但 fake 草稿未满足用户指令中的公式、例子要求，实际触发两条 `DEEP_MUST_INCLUDE_MISSING`。修正 `RequestedSectionsDeepKnowledgeModel` 的四节内容，保留标题断言与真实 artifact 校验。
- 完整 deep diagnostics 用例：旧 `repeated_issue_fingerprint` 预期属于已废弃修复循环。改为当前只读契约 `artifact_validation_failed`，增加 round 为 0、生成仅调用一次的断言；保留完整 issue diagnostics 检查，不恢复自动修复。
- `ContentProtocol` 连续显示公式用例：向 `assertTrue()` 传入 `indexOf` 数值（实际为 9），不是布尔值。修正为公式存在且顺序不变的布尔断言，未改公式归一化实现。

#### 可复现的设备测试入口

直接从测试 HAP 导入 HSP 的 `src/test/List.test` 会在设备运行时找不到 record；编译成功不能证明可执行。新增 `scripts/prepare-knowledge-hypium.mjs` 将 agents/common 测试复制到 entry 的 ohosTest 专属生成目录，并将生产导入改为对应 HSP 完整路径。源测试仍为唯一维护源，生成目录被忽略，生产 HSP 不打包测试代码。

执行顺序（工具路径通过本机环境配置）：

1. `node scripts/prepare-knowledge-hypium.mjs`（当前生成 22 个文件）。每次修改 agents/common 测试后重新运行；干净 checkout 构建 ohosTest 前也必须运行。
2. hvigor `--no-daemon --mode module -p product=default -p module=entry@ohosTest assembleHap`，本轮两次扩展构建均 BUILD SUCCESSFUL。
3. `hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap`；依赖 HSP 使用同一工作区此前构建并安装的产物。未卸载、未清应用数据。
4. `hdc -t 127.0.0.1:5555 shell aa test -b com.example.mathmind -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 15000 -w 60`。

先接 Dispatcher/Incremental、agents/common 已注册套件及原设备入口，报告 **191/191**，0 failure/error/ignore。再接完整 `entry/src/test/List.test.ets`（替换两个单独入口，避免重复注册），报告 **415 项，413 pass、2 failure、0 error、0 ignore**。这里的完整指三个 List 已注册的用例，不包括未注册文件，也不代表所有平台集成均成功；部分旧能力探针允许显式环境 blocker。

#### 扩展套件仍有两项失败

用同一设备命令追加 `-s class 'ChatPersistenceCapability.test_only_atomic_file,ConversationWorkflow.issue174_failure_timeline'` 独立复跑：8 项，6 pass、2 failure；不是必须依赖其它套件才出现的污染。

1. `should call failWrite and preserve the formal file when the write stage fails`：旧 local 测试发布 `build/chat-persistence-capability-test` 相对路径，设备不能保证该位置可写。能力探针在 rollback 前返回 WRITE blocker，而测试强制要求 `rollbackCalled=true`。同轮使用真实 app-private filesDir 的 `ChatPersistenceCapability.issue122_device_gate` 三项均通过，包含严格 commit/rollback 与正式文件保留断言。不能把旧用例改为无条件成功，需修正其平台 fixture 或明确 blocker 契约。
2. `should emit a typed error for note generation failure`：fake `getContext()` 主动抛 `WORKFLOW_PORTS_MUST_BE_INJECTED`；真实 `ConversationMemoryProjection.structuredContextForNote` 捕获后返回 undefined，workflow 走“当前会话还没有可整理的内容”，未到达 fake Capture 的 `NOTE_FAILED`。现有注入覆盖 intent/reply/capture/noteRoute，不覆盖材料上下文依赖。需补正确上下文 fixture 或另行确定可测试 Seam，不能修改生产失败语义或把该测试改成期望无错误来掩盖缺失覆盖。本轮保留红灯与定位，不扩展生产 Interface。

#### UI 观测与未完成项

- 通过 HDC uitest 操作并读取布局树：五个 Tab 可进入、首页 Hero/进度环文本可见、笔记空态为 0 条、复习计划页面可打开、AI 浮窗可开关且可输入、模式菜单含轻量/标准/深度。布局树不证明帧率或呼吸动画流畅。
- 标准模式发送合成数学材料“请将以下材料整理成笔记：函数y=x在实数上连续且可导，导数为1。”后，UI 明确显示失败与“请先在「我的 → 设置」中配置 API Key”。没有读取或输出密钥；未用 fake 替代联网成功路径。该合成请求及失败回复留在当前测试会话，未清除会话数据。
- 知识星系从加载态进入图谱，但笔记为 0 时仍显示“数学分析 6 条 · 87%”“线性代数 4 条 · 85%”；当前源码 `KnowledgeGalaxyViewModel` 含 preview 数据。只能记为已有预览现象，不能宣称图谱真实数据或无假数据验收通过，也没有据此改动 UI。
- 未完成：可用模型下的 light/standard/deep 预览与确认、真实保存与重复确认、增量用户锁定段保留、生成中取消、SSE 逐字呈现、照片/OCR、真实笔记详情浮层，以及同配置下重构前后的设备行为对照。需要用户在设备配置可用模型，照片路径还需要 OCR/图片输入条件。

最后再次执行默认 Node：**318/318**；deep/incremental 补充检查：**7/7**；生成脚本 `node --check`、ArkTS lint、naming-lint、diff check 均通过。生产完整 build 的通过证据见前节，本轮新增测试入口的 ohosTest build 也通过，但不把任何构建结果替代未通过的设备验收。未 staging、commit、push 或关闭 #215。

### 配置模型后的续验（2026-10-14）

用户已在设备配置模型，并同意继续修正剩余 fixture。仍以同一模拟器和未提交工作区为对象；界面显示模型为 DeepSeek-V4-Pro。本轮不读取模型凭据、不清除应用数据、不修改生产 Interface 或校验策略。

#### Hypium 收口

- `ChatPersistenceCapability.test.ets` 改为从 TestKit 获取真实 ability 的 filesDir，在其 `chat-persistence-capability-test` 子目录运行，保留 rollback / 正式文件内容的原断言；为 atomic 套件补 afterAll 清理，清理仅针对测试文件与空的测试子目录。
- `ConversationWorkflowFailure.test.ets` 仅在 note 用例提供真实 ability context；使用独立测试 session ID 和明确求导材料。`commitHistory=false` 阻止 fixture 消息投影到真实聊天历史；保留 typed failure 断言并增加 `NOTE_FAILED` 检查，确保确实进入 fake Capture 的失败分支，而非其它前置错误。未新增生产依赖注入 Interface。
- 首次增量构建未更新测试 HAP（时间戳仍旧），安装后仍执行旧用例。禁用增量构建后定向复跑 **8/8**。今后修改外部 `src/test` 时，设备验收使用 `--no-incremental`，并核对产物已更新，不单凭 BUILD SUCCESSFUL 判断测试代码已打包。
- 扩展全套曾得到 414/415：note fixture 初始化 RDB 后，common 的 cold-store 用例不再处于未初始化状态。测试注册顺序明确为原设备入口 → common → agents → entry，先执行 cold-store gate，再运行真实 RDB fixture；不删除冷启动断言或改生产数据库状态。
- 去掉所有 `[DEBUG-215]` 临时日志，再次构建、安装并执行无 class 过滤的完整入口：**Tests run: 415, Failure: 0, Error: 0, Pass: 415, Ignore: 0**。
- 构建命令：hvigor `--no-daemon --no-incremental --mode module -p product=default -p module=entry@ohosTest assembleHap`；安装与 aa test 命令同上。完整生产构建也用 `--no-daemon --no-incremental --mode module -p product=default assembleHap`，BUILD SUCCESSFUL。
- 最后 Node **318/318**、补充 **7/7**；ArkTS lint、naming-lint、脚本语法检查、diff check 通过。

#### 联网 UI 证据

| 路径 | 输入 / 操作 | 观测 |
|---|---|---|
| 主题澄清 | 整理 y=x 连续且可导的材料 | 展示“微积分/求导”“极限与连续”两个主题；不是缺配置错误 |
| standard | 整理幂函数求导法则及平方求导例子 | 出现草稿编辑预览、来源 2、soft issues 2；预览时笔记为 0；确认后 toast“笔记已保存”，笔记为 1 |
| 真实详情 | 打开新保存的幂函数笔记 | 正文与公式渲染，打开/返回可操作；进程重启后笔记仍存在 |
| light | 常数函数 y=5 的导数为 0 | 草稿预览、来源 1、soft issues 0；点击取消后提示材料仍可用，笔记仍为 1 |
| deep | 同一常数函数材料 | 第 1/1 节撰写 → 检查已完成 → 草稿预览；来源 1、soft issues 0；确认后笔记为 2 |
| 生成中取消 | deep 常数函数 y=7，撰写第 1/1 节时点击停止 | 标记“已取消”，没有出现草稿或新增笔记，仍为 2 |
| 对话 | 三句话解释常数函数导数为零，不生成笔记 | 观察到处理中/思考态与随后完成的公式正文；未新增笔记。采样未捕获正文逐 token 变化，不能据此声称完整 SSE 帧率/逐字验收通过 |
| 用户编辑 | 在幂函数法则段加入“验收保留标记215：此段由用户补充，限定n为正整数。” | 通过 UI 保存；测试笔记版本变为 2，正文保留标记 |
| 增量失败零保存 | 给该笔记的示例追加三次方例子；再试只追加文字且保留公式 | 两次进入真实修订，随后 `FORMULA_INCONSISTENT:section-x`；没有可确认预览，版本仍为 2、编辑标记保留 |

真实数据验证只对本轮生成的测试笔记进行定向只读 SQLite 查询，不直接写数据库。UI 新建了“幂函数求导公式”和“常数函数的导数”两条测试笔记及测试会话；幂函数笔记含上述人工编辑标记，保留给用户检查，没有删除。

#### 当前阻塞：既有增量公式校验误报

实际 standard 生成的笔记同时含通用公式 `f'(x) = n x^{n-1}` 与平方例子 `f'(x) = 2 x^{2-1} = 2x`。`common/src/main/ets/models/NoteGenerationModels.ets` 的 `validateIncrementalConsistency` 以等号左侧的整行前缀作为全篇唯一符号键，不区分通用规则与局部例子，因而把同名 `f'(x)` 的合法不同上下文判为冲突。

最小复现已运行：用现有 `createRuntime` 加载真实 common 实现，对 UI 生成且尚未人工修改的原始正文调用 `parseIncrementalSections`，再传给 `mergeIncrementalPatches(sections, 空目标计划, [])`。即使 **零 patch**，返回仍是 `["FORMULA_INCONSISTENT:section-x"]`。因此失败并不依赖新模型 patch 或本次用户编辑。该模型文件对固定参照 `e07e7fe0ee63c0770d0d1bde6ae7152d6114f608` 的 diff 为空；本轮未修改它。

另外，deep 的“包含公式与例子”请求曾在 preflight 以 `sources=1 issues=1 tokens=0` 被拦截，UI 只展示泛化失败原因；随后简单单主题请求可成功。保留此现象，不声称所有 deep 指令都通过。

当前不能宣布整票验收：增量成功预览/确认仍被上述既有规则阻塞；需要用户决定将其单独修复（改变既有行为，不能混为纯提取），或明确作为第一阶段已知限制。照片/OCR、真实重复确认竞争、完整 SSE 逐字观测和重构前后同配置设备对照也没有新增通过证据。尚未进行本轮最终双轴 review，未 staging、commit、push 或关闭 #215。

### 经用户授权的增量公式误报修复与复测

本节更新上一节的阻塞状态，保留历史失败记录。用户批准修复既有误报，并愿意手动执行联网 UI 验收。此项是独立的行为修复，不计为 #213/#214 的纯文件提取。

- 根因与修改：`validateIncrementalConsistency` 原本把等号左侧文本当作全篇唯一符号。现在公式映射按章节建立，允许通用规则与另一个章节的具体例子复用 `f'(x)`；同章节不同等式仍拒绝。全篇术语一致性、引用检查、目标与用户锁定段保护不变。
- 边界：这仍是文本启发式，不是数学等价判定；不再据同名公式的文本差异判断跨章节冲突，同章节的不同局部例子仍可能受到该规则限制。未新增 deep 自动修复，未改 KnowledgeModel 外部 Interface。
- Node 新增三项回归：零 patch 的规则/例子误报、同章节冲突仍拒绝、patch 保留锁定段及术语/引用校验。已观察原实现红灯，再以修复转绿；完整 Node **321/321**，deep/incremental 补充 **7/7**。
- Hypium 新增两项：跨章节导数与锁定段保留、同章节不同等式拒绝。生产和 ohosTest 均以 `--no-incremental` 构建成功，使用 `install -r` 更新，未卸载或清数据。ArkTS lint、naming-lint、diff check 通过。
- 安装后的首次全套曾出现新用例失败与 `App died`，没有完整报告，不记为通过。force-stop 后定向复跑 **9/9**；随后无 class 过滤的完整入口报告 **Tests run: 417, Failure: 0, Error: 0, Pass: 417, Ignore: 0**。首次异常未复现，尚不足以裁定为旧进程或旧产物。
- 下一步由用户对现有“幂函数求导公式”执行真实增量预览、确认与重新打开，确认人工标记逐字保留且只更新原笔记。自动化通过不替代该联网 UI 结果；#215 仍未最终验收，未提交、push 或关闭票据。

### 增量预览后的保存归属修复

用户真实 UI 复验已进入草稿，但保存报 `DETACHED_DRAFT_REQUIRES_RECOVERY_ENTRY`，随后明确授权修复。无联网复现确认：`Dispatcher.dispatch` 的增量分支第一次保存 running run 带有会话归属，第二次保存 ready-preview run 却遗漏 `originSessionId` 与 `parentConversationRunId`。Repository 更新时将缺省值写为空；确认入口重新恢复草稿后被归属保护拒绝。设备定向只读查询确认最新增量草稿两字段长度均为 0，原测试笔记仍为版本 2 且人工标记保留。

- 生产修改仅为增量 ready-preview run 补传上述两个字段。没有放宽无归属/跨会话校验，没有直接修补数据库，也没有为已有无归属草稿猜测所属会话；旧草稿需通过既有恢复入口处理，联网验收重新生成新预览。
- 沿用 Dispatcher/Repository 公开 Seam 扩展行为基线：先看到归属断言实际 undefined 的红灯，再补字段转绿；Hypium 增量用例增加恢复后的两个字段断言。ConversationDraftWorkflow 新增恢复后确认成功、预览后落盘归属丢失仍拒绝确认两项测试。后两项使用已有 gateway 替身，不等同于真实 RDB 到确认写入的端到端通过。
- Node **321/321**，deep/incremental 补充 **7/7**，ArkTS lint、naming-lint、diff check 通过。生产 HAP 与 ohosTest 构建成功，但初次设备测试仍执行旧 agents HSP；核对发现 HSP 时间戳早于源码修改。额外执行 hvigor `--no-daemon --no-incremental --mode module -p product=default assembleHsp`，明确完成 common/agents PackageHsp 后重新安装。
- 新 HSP 安装并 force-stop 后，设备定向 `IncrementalRegeneration.issue104_incremental_regeneration,ConversationDraftOwnership.issue173_behavior` 报告 **14/14**，0 failure/error/ignore。
- 本轮无 class 过滤的全套出现 `should commit a snapshot with AtomicFile or record an AtomicFile blocker` 断言失败，随后 `App died`，没有完整结果；此异常尚未定位，不能沿用上一轮 417/417 宣称当前全套通过。新增两项后理论注册总数为 419，尚无 419 全绿证据。
- 等待用户重新生成并确认新草稿的 UI 结果；#215 仍未最终验收，未 staging、commit 或 push。

### 本地提交汇总（对照远端 develop）

提交前已 fetch `origin/develop`，参照为 `2302b35c114ef09d62aa6feb05351610c21fb980`；当前分支已有本地提交 `e07e7fe`，本次保留其历史并追加提交，不 rebase、不 push。

- 行为基线：通过真实 Dispatcher/CaptureGraph/KnowledgeModel 与受控 LLM/存储边界覆盖生成、失败、取消、锁定段、确认等行为；新增全生产树所有权守卫，并接入默认 Node 测试。
- 内部拆分：CaptureStructurer 承载 Capture 与 KnowledgeUnit 投影；DraftComposer 承载 light/standard；DeepDraftComposer 和 IncrementalPatchComposer 真正承载各自算法。NoteDraftVerifier 为 standard/deep 共享的只读 verifier，GenerationDraftSupport 承载共享辅助逻辑。KnowledgeModel 保留七个外部方法，仅组装与委托；不新增 deep 自动修复。
- 集成测试：新增仅用于 ohosTest 的 agents/common 测试准备脚本，接入完整注册入口，生成副本不进版本库或生产包；修正漂移的 deep fixture/停止原因、ContentProtocol 布尔断言、设备 filesDir 与会话上下文 fixture。
- 独立行为修复：公式文本冲突检测收窄到章节作用域；增量 ready-preview 保存保留会话及父运行归属。这两项不冒充纯文件提取。
- 用户最新反馈“成功保存了”，记录为新版真实增量生成 → 预览 → 确认保存通过；重新打开后的人工标记与无重复笔记尚未收到单独确认。
- 已有验证：Node 321/321、补充 7/7、设备定向 14/14、HAP/HSP/ohosTest 构建通过，静态检查通过，提交前 link-check 0 broken links。最新完整 Hypium 仍有 AtomicFile 失败与 App died；历史 417/417 不替代当前全套结果。其它未完成设备路径见前文，#215 不关闭、不宣称全体验收通过。
