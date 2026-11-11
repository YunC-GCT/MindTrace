# 042 — A2A 错误语义统一

> **Status**: implemented (2026-11-02)
> **Related**: [spec 040](./040-writejob-persistence-cross-process.md) · [ADR-0024](../adr/0024-writejob-persistence-cross-process.md)
> **Code**: `entry/src/main/ets/services/A2AErrorTaxonomy.ets` · `entry/src/main/ets/services/A2AController.ets` · `entry/src/main/ets/agentextability/AgentExtAbility.ets`
> **Verified by**: `node scripts/agent-gate/index.mjs`（pass=1219）；真机 A2A 冒烟 hilog `INGEST_TEXT done`

## 1. 目标

把散落在 `A2AController` 与 `AgentExtAbility` 里的错误码、分类和用户文案收敛到一处，避免新增错误时各写各的字符串，也便于后续按 kind 做统一重试/降级。

## 2. 映射

`A2AErrorTaxonomy.ets` 定义 `A2AErrorCode -> A2AErrorKind + a2aErrorText(code, detail)`：

| code | kind | 说明 |
|---|---|---|
| `A2A_PARSE_ERROR` | protocol | 请求 JSON / 顶层结构非法 |
| `A2A_CONFIG_READ_TIMEOUT` | config | 等 `LlmConfig` 超时；detail = 毫秒 |
| `A2A_MODEL_NOT_READY` | model | 端侧模型未就绪且未配置云端 |
| `A2A_MODEL_UNUSABLE` / `A2A_MODEL_ID_UNRESOLVED` | model | 模型不可用；detail = model + 原因 |
| `A2A_LLM_FAILED` | model | 非超时类 LLM 错误；detail = 原因 |
| `A2A_LLM_TIMEOUT` / `A2A_DEADLINE_EXCEEDED` | timeout | 单次调用超时 / 整个请求超时 |
| `A2A_INGEST_TIMEOUT` | ingest | 入库 deadline，已转待整理 |
| `A2A_INGEST_FAILED` | ingest | 入库失败；detail = 稳定错误码 |
| `A2A_REPLY_SENT` | none | 成功码，不参与错误文案 |

## 3. 规则

- 新错误先加进 `A2AErrorCode` 与 `a2aErrorKind`，用户文案只经 `a2aErrorText`。
- `A2AController` / `AgentExtAbility` 不再保留本地错误文案常量。
- 文案变更必须同步 `scripts/arkts-lint/tests/v7-a2a-error-taxonomy.test.mjs`。
- 现有文案保持原样（本次只收口，不改用户可见措辞）。
