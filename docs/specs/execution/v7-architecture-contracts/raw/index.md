# #239 dispatch golden 快照对照表

> 本目录每个 `.json` 是一条 `Dispatcher.dispatch` 行为快照；测试文件是
> [`v7-golden-dispatch.test.mjs`](../../../../../scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs)。
> 快照只记录 dispatch seam 上可观察的语义：终态、错误码、分类、落库计数、传输预算；
> 耗时字段不入盘，时间戳归一为 `<ts>`，随机 id / 哈希归一为 `<id>`。
> `commitKey` / `checkpointId` / `runId` 保留分隔结构（例如 `<id>:0`），否则幂等用例无法证明。

## 文件 → 命令 → 终态

| 文件 | 命令 | 终态 | 覆盖的 ADR-0019 条款 | 它证明什么行为 |
|---|---|---|---|---|
| [`capture-success.json`](./capture-success.json) | capture（正常文本） | `committed`（现状：`success:true` + `data`） | (a) capture / (b) committed / (c) capture 成功 | 分类 → 结构化 → TruthCheck → `dao.insert` 落 1 条笔记，分类与笔记同时返回 |
| [`capture-analysis-only.json`](./capture-analysis-only.json) | capture + `analysisOnly` | 无写入（`persist:false`） | (a) analysisOnly / no persist | 只调用分类、不结构化、不写 DAO；`data` 为空 |
| [`capture-model-unavailable.json`](./capture-model-unavailable.json) | capture，模型调用抛 `LlmError` | `failed`（现状：只有 `errorMessage`，无 `errorCode`） | (a) capture / (b) failed / (c) `MODEL_UNAVAILABLE`（目标码） | 模型不可用时结构失败、零落库；分类器先走规则兜底，错误只经 `errorMessage` 暴露 |
| [`capture-empty-input.json`](./capture-empty-input.json) | capture，空文本 | `failed`（现状：入口未校验，结构调用失败） | (a) capture / (b) failed / (c) 输入校验缺口 | 空文本分类走 fallback 后仍调用结构化模型；说明空输入没有在 capture 入口被拦截 |
| [`capture-cancel-entry.json`](./capture-cancel-entry.json) | capture，进图前已取消的 token | 现状：抛 `Error('CONVERSATION_CANCELLED')` | (e) entry cancel / (c) `CANCELLED` | 入口取消零 LLM、零写入，且以抛错而非 `NoteOutcome` 返回 |
| [`capture-cancel-in-graph.json`](./capture-cancel-in-graph.json) | capture，节点内观察到取消 | 现状：抛 `Error('CONVERSATION_CANCELLED')` | (e) in-graph cancel / (c) `CANCELLED` | 节点内取消已产生 1 次分类调用；`CaptureGraph` 先压成 `NODE_ERROR`，但 `Dispatcher` 在 graph 返回后再次 `throwIfCancelled`，所以 capture seam 仍抛错 |
| [`generation-light.json`](./generation-light.json) | generation(light) | `readyPreview` | (a) generation(light) / (b) readyPreview | light 生成 1 次调用（1200 tokens）、保存 checkpoint、零 DAO 写入 |
| [`generation-standard.json`](./generation-standard.json) | generation(standard) | `readyPreview` | (a) generation(standard) / (b) readyPreview | standard 草稿 + 只读 verifier 两次调用（6000 / 2600），零 DAO 写入 |
| [`generation-deep.json`](./generation-deep.json) | generation(deep) | `readyPreview` | (a) generation(deep) / (b) readyPreview | deep 两段顺序生成 + verifier（4800 / 4800 / 2600），多来源证据映射，零 DAO 写入 |
| [`generation-needs-input.json`](./generation-needs-input.json) | generation，空来源 | `needsInput` | (a) generation / (b) needsInput / (c) `MISSING_SOURCE` | 预检在 LLM 之前返回 `needs-input`，`issues[]` 含 `MISSING_*`，零调用、零写入 |
| [`regenerate-version-conflict.json`](./regenerate-version-conflict.json) | regenerate，`baseVersion` 落后 | `failed(VERSION_CONFLICT)` | (a) regenerate / (b) failed / (c) `VERSION_CONFLICT` | 版本不匹配在读取基础资料后立即失败，无生成、无写入 |
| [`regenerate-note-missing.json`](./regenerate-note-missing.json) | regenerate，`noteId` 不存在 | `failed(NOTE_NOT_FOUND)` | (a) regenerate / (b) failed / (c) `NOTE_NOT_FOUND` | 找不到目标笔记时返回稳定错误码，无生成、无写入 |
| [`prepared-candidate-hash-mismatch.json`](./prepared-candidate-hash-mismatch.json) | preparedCandidate，hash 不匹配 | 现状：`failed`，`候选内容已变化`，**无 `errorCode`** | (a) preparedCandidate / (b) failed / (c) `APPROVAL_HASH_MISMATCH`（目标码） | 审批哈希在写库前被拒绝；证明目标码尚未落地 |
| [`prepared-candidate-commit-and-replay.json`](./prepared-candidate-commit-and-replay.json) | 先 preview，再 commit，再原样重放 | 首次 `committed`；重放不再写第二条 | (a) preparedCandidate / (b) committed / (c) `commitKey` 幂等 | 首次 insert 1 条笔记并写 commit receipt；重放命中同一 `commitKey`，笔记数仍为 1 |
| [`generation-cancel-in-graph.json`](./generation-cancel-in-graph.json) | generation(light)，节点内观察到取消 | 现状：`failed` + `NODE_ERROR`（目标：`cancelled`） | (e) in-graph cancel / (b) failed / (c) `NODE_ERROR` | light 途中取消不生成 checkpoint、不写 DAO；`NODE_ERROR` 只在本路径可见，capture 同场景仍抛错 |

## 现状注记（一手依据）

- **capture 图内取消为什么记抛错而不是 `NODE_ERROR`**：`CaptureGraph.ets:41-43` 先把节点抛出的
  `CONVERSATION_CANCELLED` 改写成 `NODE_ERROR`，但 `Dispatcher.ets:143` 在 `graph.run` 返回后再次
  `options.cancellationToken?.throwIfCancelled()`，所以 capture seam 上看到的是抛错；`NODE_ERROR`
  只在没有这道复检的 light generation 路径可见（见 `generation-cancel-in-graph.json`）。
- **capture 空输入为什么不是输入校验**：`TypeClassifier.ets:115-123` 对空文本直接返回 fallback，
  `Dispatcher.ets:131-208` 没有空文本入口检查，随后仍调用结构化模型；本快照记录的是这次模型调用失败。
- **preparedCandidate hash 不匹配为什么没有 `errorCode`**：`Dispatcher.ets:1449-1451` 只返回中文
  `候选内容已变化`；ADR-0019 目标码 `APPROVAL_HASH_MISMATCH` 尚未在该分支落地。

## 录制 / 比对

从仓库根目录运行：

```sh
# 录制：重写本目录下每个 <case>.json
V7_GOLDEN=record node --test scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs

# 默认：读文件比对；不相等时打印字段级 diff 并 fail
node --test scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs
```

Windows PowerShell 等价写法：

```powershell
$env:V7_GOLDEN = 'record'; node --test scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs; Remove-Item Env:V7_GOLDEN
node --test scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs
```

文件不存在时默认模式会直接 fail 并提示用 `V7_GOLDEN=record` 录制，不会静默生成。
测试还会对 `prepared-candidate-commit-and-replay` 连跑两次并断言归一化结果字节相同，
并对不该落库的用例断言 `storage.writes.length === 0`。

## 与 #241 的关系

这批快照是 **#241 迁移的等价判据**：`NoteAgent` 只包 capture 分支时，capture 相关快照必须逐字段不变；
其余 generation / regenerate / preparedCandidate 路径保持现有装配，快照同样不得漂移。
若 #241 有意改变某个终态或错误码，必须先改 ADR-0019 与对应快照，再改实现，不能反过来让快照追认实现。
