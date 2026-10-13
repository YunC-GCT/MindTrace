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

两份测试均已加入默认 npm 测试列表。内部 Module 的文件名、私有字段、实例身份和协作调用顺序不属于断言；外部传输重试上限、持久化先后及公开 artifact schema 属于需保持的行为。

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
