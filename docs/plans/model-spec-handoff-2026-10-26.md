# 模型适配（ModelSpec）交接 — 2026-10-26

工作区：`D:\HMgent\MindTrace-latency`，分支 `feat/xiaoyi-latency-tuning`，HEAD `9d08ab1`，工作区干净。
主检出 `D:\HMgent\MindTrace`（`bugfix/galaxy-web-temporary`）全程未被改动，**尚未合并 develop**。

提交链（自下而上）：

| 提交 | 内容 |
|---|---|
| `d7dfbd4` | 模型适配分层：catalog / resolver / discovery + `schema_version=2` 迁移 |
| `61a1de4` | 设置页接清单：先提供商，再该提供商的模型 |
| `d9e1ded` | A2A 35s 单一 deadline：25s 单次 / 0 重试 / 4096 输出 |
| `3fdbafe` | 候选模型元信息持久化 + 可用性上 chip |
| `a06fd01` | **ModelSpec 驱动请求字段**（本阶段主线） |
| `9d08ab1` | 补 `kimi-k3.1-pro` / `-highspeed` 规格 |

## 这一阶段做了什么

模型适配从「按 vendor 特判」变成「按型号读规格」：

- `ModelListing`（能发现什么）与 `ModelSpec`（能构造什么请求）分离
- `thinking.control` 四态：`toggle` / `always_on`（关不掉，`off[]` 为空）/ `unsupported` / `unverified`
- 写入统一走 `FieldWrite` 路径：`["thinking","type"]` 与 `["enable_thinking"]` 同一套机制
- 偏好按 `vendorId/modelId` 存（`model_prefs`），同家不同型号互不干扰
- 请求体由 `planModelRequest(spec, selection)` 生成，`vendorId === 'deepseek'` 之类分支已删
- 非法 effort 本地收敛，不静默取 `levels[0]`；`max_tokens` 按 `maxOutputTokens` 夹取

## 已核实的字段事实（官方文档，2026-10-26）

| 厂商 | 开关 | 默认 | 关闭 | 强度 | 固定参数 |
|---|---|---|---|---|---|
| DeepSeek | `thinking.type` | 开 | `disabled` 或 `reasoning_effort:"none"` | `reasoning_effort`: low/high/max，默认 high | 思考时 temperature 失效 |
| 百炼通义 | `enable_thinking`（扁平布尔） | 视型号 | `false` | 百炼的 `reasoning_effort` 只对 DeepSeek-V4 有效 | — |
| 智谱 GLM-5.x | `thinking.type` | 开 | `disabled`；**5.3 / 5.3-Flash 强制思考** | 无 | — |
| Kimi k2.6 | `thinking.type` | 开 | 能 | 无 | temperature 1.0/0.6、top_p 0.95 固定 |
| Kimi k2.7-code | 只接受 `{enabled,keep:all}`，可省略 | 开 | **传 disabled 报错** | 无 | temperature 1.0 固定 |
| Kimi k3 / k3.1-pro | **不传 thinking** | 常开 | 不能 | `reasoning_effort`: low/high/max，默认 max | temperature 1.0、top_p 0.95 固定 |
| 豆包 seed-1.6 | `thinking.type` | 未证实（`partial`） | `disabled` | 无 | — |

## 验证状态

- `assembleHsp` + `assembleHap` 均 SUCCESS（构建必须这个顺序，见 `harmonyos-build-and-deps` 技能）
- agent-gate **PASS**，arkts-lint `errors=0`
- `npm test` 352 / 345 通过 / 7 失败 —— 7 个是既有基线（`kg_edge`、`note context`、`note-review ×4`、`dispatcher`），与主检出逐条一致
- 真机（`3XTYD24C16203663`）：App 正常启动；Kimi 编辑面板可打开

## 未完成 / 已知问题（下一段优先）

1. **Kimi / GLM / 豆包 没有 catalog listing**（`model-catalog.ets:341-363` 的 `models: []`），所以面板显示「未提供内置清单」、手动输入的 `kimi-k2.6` 挂「能力未确认」chip —— 但同一个面板又出现了按 spec 渲染的「思考模式」开关。两个信号自相矛盾：chip 该读 spec 的 `evidence.status`（`verified`/`partial` → 「字段已核实（默认值未证实）」），而不是只看 listing 是否存在。**（已处理，见文末「接手后进展」）**
2. **百炼 `thinking_budget` 未建模** —— 第三类控制（思维链限长），和 effort 不是一回事，要不要加待定。
3. **GLM 只加了 6 个精确 ID**（5.3 / 5.3-flash / 5 / 5.1 / 5.2 / 4.7），`GLM-5.3-FlashX`、`GLM-5-Turbo`、`GLM-4.7-Flash` 等未加，避免编 ID；加之前先核官方 model id 大小写。**（部分处理：已按官方示例补 `glm-4.7-flash`，见文末「接手后进展」）**
4. **A2A 延迟样本只有 1 条**：`canonicalModel=deepseek-flash / attempts=1 / elapsedMs=1696`。要拍「默认模型切不切 flash」需攒 20 条算 P50/P95。抓取：`hdc hilog | grep --line-buffered -E "A2A_(REPLY_SENT|DEADLINE_EXCEEDED|LLM_TIMEOUT|LLM_FAILED)"`。**（已攒够 20 条，见文末「A2A 延迟样本」）**
5. **用户体感「重连之后才出回复」未定性** —— 我们的链路 1.7s，慢在小艺 ASR/调度或连接断链；需要给 Agent 加 `onConnect/onDisconnect` 日志才能分辨。
6. `ReplyService` 两条链路显式 `enableThinking: false`（聊天与小艺都按不思考的时延预算）；如果以后要「聊天也思考」，得开一个按链路区分的开关，别再依赖默认值。
7. `build-hsp-hap.mjs` 在本机仍会在非 tty 下挂（`stdin is not a tty`），只能走两步手动构建；P0 032「构建顺序断言」没加。**（已澄清，见文末「接手后进展」——脚本没问题，是我的调用管道有问题）**
8. 六个提交都还在 worktree，**合并回 develop 后必须在主检出重建验收**（worktree 过不代表合并树能编过）。

## 常用命令

```bash
cd /d/HMgent/MindTrace-latency
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
"/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleHsp --no-daemon
"/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleHap --no-daemon
node scripts/agent-gate/index.mjs
cd scripts/arkts-lint && npm test
# 装包（HSP 和 HAP 都要装）
MSYS2_ARG_CONV_EXCL="*" hdc install -r common/build/default/outputs/default/common-default-signed.hsp
MSYS2_ARG_CONV_EXCL="*" hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

## 接手后进展（2026-10-26 17:5x，同一 worktree）

**问题 1 已修：能力状态只读 ModelSpec 证据。**

- `common` 新增 `capabilitySignal(spec)` 三态：`verified` / `partial` / `unconfirmed`（无 spec 与 spec 标 `unverified` 归一为 unconfirmed）。清单是否存在不再参与判断。
- `entry/services/ModelSelector.ets`：chip hint 与保存判定改读 `capabilitySignal`；`partial` 提示「字段已核实（默认值未证实）」；`resolveModel` 已带 spec，`specFor` 不再二次查表。
- `VendorPicker.ets`：横幅改成「未提供内置清单 · <能力状态>」，不再与思考开关并存自相矛盾。
- 测试：`model-resolution.test.mjs` 补三态断言；把已存在但未收编的 `model-request-spec` / `model-capabilities` / `llm-model-preference` 三个文件挂进 `npm test`（+27 项）。

**验证（本 worktree，HEAD = `2b32f4a`）**

| 项 | 结果 |
|---|---|
| `assembleHsp` / `assembleHap` | 均 BUILD SUCCESSFUL（18s / 41s；随后 `build-hsp-hap.mjs` 走完整三步一次跑通，HAP 阶段 31s，退出码 0） |
| `hsp-freshness` | 退出码 0，产物晚于 `common/src`，`OnDeviceLlm` 命中 5 处 |
| agent-gate | **PASS**（7 文件 / 4 .ets；arkts-lint errors=0） |
| `npm test` | **379 项 / 372 通过 / 7 失败**；7 个与 HEAD 前逐条相同（`kg_edge`、`note context`、`note-review ×4`、`dispatcher`），新增 27 项全绿 |

**合并口径（未执行，等 review）**：`develop` 与 `origin/develop` 都是当前 HEAD 的**严格祖先**（`git merge-base --is-ancestor` 成立，ahead/behind = `0 102`），所以合入 develop 是 **fast-forward**，合并树与本 worktree 完全相同 —— 上面这份构建/测试结果直接适用，不存在"合并树编不过"的额外风险。剩下的仍是问题 4（A2A 只 1 条样本）与问题 2/3/5/6/7。

**问题 7 改判：脚本没坏，是调用管道坏了。** 前面两次 `node scripts/build-hsp-hap.mjs` 都只吐 `stdin is not a tty` 且一行构建日志都没有，原因是命令写成了 `... 2>&1 | tail -30`：**后台 + 管道**会命中非 tty 中止，而且管道把退出码换成了 `tail` 的 0，看起来像"脚本静默成功"。用 `node -e "console.log('ok')" 2>&1 | tail -3` 能复现同一行输出，证明与脚本无关。前台直接跑（不接管道）实测正常：

- `[1/3] assembleHsp` → `[2/3] hsp-freshness` → `[3/3] assembleHap`，`BUILD SUCCESSFUL in 31 s 757 ms`，`完成：HSP 与 HAP 均已构建`，退出码 0
- 后台 + `> log 2>&1`（不接管道）同样可行，前面 18s/41s 那次就是这么跑出来的

所以「只能两步手动构建」不成立，`build-hsp-hap.mjs` 可以当唯一构建入口用；P0 032「构建顺序断言」也就没有额外的阻塞理由。剩下要补的只是别在这个 host 上给构建输出接管道。

顺带一条诚实的记录：本轮先在后台管道里跑了两次脚本都没真正构建，我是靠手动两步拿到构建结果的；后来为了定位原因才做了上面的对照实验。构建结论本身（HSP/HAP SUCCESSFUL）来自真实 hvigor 输出，不受影响。

**问题 3 部分收口：GLM ID 按官方文档核过一轮。**

官方文档 `docs.bigmodel.cn`（模型概览 + 各模型页的调用示例）能给到的 model 字符串只有这些：

| 官方显示名 | 官方示例里的 `"model"` | 处理 |
|---|---|---|
| GLM-4.7 / GLM-4.7-FlashX（同页） | `glm-4.7` | 本来就有 |
| GLM-4.7-Flash | `glm-4.7-flash` | **本轮新增**：默认开 thinking、`thinking.type=disabled` 可关、200K/128K |
| GLM-5-Turbo | `glm-5-turbo` | **不建 spec**：`thinking.type` 已被示例证实，但「默认思考行为」文档只列了 5.3/5.3-FLASH/5.2/5.1/5/4.7 系列，turbo 的默认值无出处 → `defaultEnabled` 只能猜，宁可不建（面板按新逻辑显示「能力未确认」，这正是该信号的用途） |
| GLM-5.3-FlashX / FlashX-Legal | 文档只有显示名 | 不建，ID 无出处 |
| GLM-4.6 / GLM-4.5-AirX / GLM-4-Long 等 | 页码里没有 model 字符串 | 不建 |

测试里把这条口径写成断言：`getModelSpec('glm','glm-4.7-flash')` 有 spec 且 `verified`、`control=toggle`、`off=[{path:['thinking','type'],value:'disabled'}]`；`glm-5-turbo`、`glm-4.7-flashx` 必须为 `null`——防止后来的人"顺手补全"成猜出来的 ID。

**问题 3 之后的验证（含本轮 glm-4.7-flash）**：`npm test` **380 项 / 373 通过 / 7 失败**（仍是那 7 个基线失败）；agent-gate **PASS**；`build-hsp-hap.mjs` 三步跑通，HSP `BUILD SUCCESSFUL in 1 min 53 s`、HAP `46 s 303 ms`，退出码 0。新增的 GLM spec 在 `common` 里，HSP 已按新源码重建（不是旧产物）。

## 真机验收（2026-10-27 10:4x，设备 3XTYD24C16203663）

**先发现的一次装错**：设备上原本跑的不是本分支产物 —— 面板有 chip、却完全没有「获取模型清单」「未提供内置清单」「暂无模型」。核对后确认设备装的是主检出 `D:\HMgent\MindTrace`（当前在 `bugfix/galaxy-web-temporary`，VendorPicker 还是 10-13 版），不是这个 worktree。按 `common.hsp → agents.hsp → skill → cardservice → entry.hap` 顺序重装本分支产物后，新文案才出现。**这提醒一件事：DevEco 里打开的是哪个 checkout，装上去的就是哪份代码；worktree 验收必须自己 `hdc install`。**

**真机抓到的第二个 bug（比交接文档里的第 1 条更隐蔽）**：重装后 Kimi 面板一边显示横幅「未提供内置清单 · **请求字段已核实**」，一边在 chip 下面挂「**能力未确认**」——同一份证据两个结论。根因在 `ModelSelector.availabilityOf`：无权威清单的 vendor 会走到 `byCapability(capabilitySignal(resolved.spec))`，而 `byCapability` 原来只会产"降级"结果，**连 `verified` 也被映射成 `CAPABILITY_UNCONFIRMED`**。修法：

- `common` 新增 `capabilityHint(signal)`：`verified → ''`（不打扰）、`partial → 字段已核实（默认值未证实）`、`unconfirmed → 能力未确认`；`capabilityNote` 与 chip hint 都读它，文案只此一份
- `byCapability` 对 `verified` 原样返回 clean（`usable=true, degraded=false`），不再降级
- 测试 +1 项锁住"已验证不得挂能力未确认"

**真机三态对照（修完后，逐条来自 `uitest dumpLayout` 的文本节点）**：

| 供应商 · 模型 | 面板横幅 | chip 第二行 |
|---|---|---|
| 月之暗面 Kimi · kimi-k2.6 | 未提供内置清单 · 请求字段已核实 | （无） |
| 字节豆包 · doubao-seed-1.6 | 未提供内置清单 · 字段已核实（默认值未证实） | 字段已核实（默认值未证实） |
| 通义千问 · qwen3-max | 未提供内置清单 · 能力未确认 | 能力未确认 |
| DeepSeek · deepseek-v4-pro | （无横幅，有内置清单） | `· 内置`，另有 思考模式 / 推理强度 |

三处口径一致，Kimi/豆包 都渲染出「思考模式」开关（来自 spec 的 thinking.toggle），说明规格控件与能力信号同源。**问题 1 至此真机收口。**

## A2A 延迟样本（2026-10-27，20 条，设备 3XTYD24C16203663）

采样方式：新增 `scripts/a2a-smoke/latency_series.py`，在小艺的「MindTrace 数学笔记助手」会话里连发 20 条 `整理数学题`，逐条 `hilog -r` 清缓冲、读 `MindTraceA2A` 时间戳算 `onData 收到 → task snapshot sent`。**全程不需要人说话**——小艺的消息是脚本点输入框打进去的。

| 口径 | min | P50 | P95 | max |
|---|---|---|---|---|
| 全部正常回复（含冷启动首条） | 1341 ms | 2024 ms | 15304 ms | 15304 ms |
| 去掉冷启动首条（n=17） | 1500 ms | **1963 ms** | 2940 ms | 2940 ms |

- **首条 15304 ms**：扩展进程冷启 + 模型加载，只出现在第一次拉起；后续稳定在 1.3–2.9s。
- **LLM 占端到端 99.9%**：`a2a_ms` 与 `llm_ms` 几乎相等，说明我们这层的编排/序列化不是瓶颈，长度全在模型往返。
- **20 条里 2 条失败**（1695 ms / 7810 ms）：回复正文是 `模型暂时不可用：chat answer validation failed after retry: JSON object extraction failed`。这是采样反复发同一句撞出来的新问题——**失败率 10% 比延迟更值得先修**，且失败时同样会走完 A2A 快照，所以不计入延迟统计。
- 结论方向：`deepseek-flash` 这条路径的 P50 ≈ 2s，与小艺侧体感「重连才出回复」的超时门槛还有余量；但要拍「默认模型切不切」仍需换模型跑同一份脚本对比（脚本已可复用）。

## A2A 聊天回复的 JSON 提取失败（2/20 → 已修，2026-10-27）

**现象**：20 条样本里 2 条回复正文是「模型暂时不可用：chat answer validation failed after retry: JSON object extraction failed」，耗时 1695 ms / 7810 ms。

**根因**（不是网络、不是超时）：
- A2A 的 `answerConfigured` 走 `ReplyService.complete` → `LlmGuard.callJsonWithRetry`，要求模型严格回 `{"answer": "..."}`。
- `LlmGuard` 只接受「恰好一个可解析顶层对象」，模型偶尔回纯文本 / 多个对象 / 被 max_tokens 截断，一律抛错。
- A2A 侧 `maxRetries = 0`（为了压延迟），所以一次不听话 = 整条回复失败；错误信息里还没有原文，线上只能看到一个笼统的「JSON object extraction failed」。

**修法**（只开在对话回复这一条链路）：
- `LlmGuardJsonOptions.salvageKey`：最终校验失败时按四类救回 `answer` —— ①```json 围栏里取对象 ②多个对象取第一个带 `answer` 的 ③被截断时按 JSON 转义规则捞回已生成部分 ④完全没有 `{` 就把原文当答案。
- `ReplyService` 传 `salvageKey: 'answer'`，救回时打 `[ReplyCtx] json salvage mode=<mode> chars=<n> issues=...`，方便日后统计真实发生率。
- 结构化链路（笔记生成等）**不开** `salvageKey`，半成品仍抛错；错误信息也从 `after retry` 改成 `after N attempt(s)`（A2A 本来就是 0 重试，旧文案会误导排查方向）。

**验证**：`scripts/arkts-lint/tests/llm-guard-salvage.test.mjs` 7 项（直接加载真 `LlmGuard.ets`，假 client 喂坏样本）全绿；`npm test` 388/381/7（7 项仍是既有基线）。真机 46 次连发未再复现该失败（修复前那一批是 2/20；装新 `common.hsp` 后复测 3/3 ok，A2A 2127–2345 ms），所以**失败率是否真的降到 0 无法证实**，能保证的是同样的坏输入不再整条失败、且降级会留日志。


