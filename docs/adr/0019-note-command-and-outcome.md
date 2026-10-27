# 0019 — NoteCommand / NoteOutcome: typed commands and terminal outcomes for the note pipeline

`Dispatcher.dispatch` currently accepts one flat `DispatchRequest` and returns one flat `DispatchResult` with a boolean `success`; the five real command shapes and the five real terminal states are implicit in branch order, so a caller cannot tell "needs input" from "failed", cannot see a retryable flag, and cannot tell a cancellation that already committed a note from one that wrote nothing. We **split the seam into a discriminated `NoteCommand` union (five types) and a discriminated `NoteOutcome` union (five terminal states)**: every command declares its persistence and idempotency key, every failure carries a stable code plus `retryable`, and every cancellation states whether a write was already committed. This ADR defines the target contract; the ports and adapters land in #238, the behavior baseline in #239, the `NoteAgent` wrapper in #241.

## Status

`accepted` (2026-10-27, ticket #237)

## Context

The five shapes already exist, but only as control flow:

- command selection: `agents/src/main/ets/core/Dispatcher.ets:119-130` (preparedCandidate → generation/regenerate → capture) plus the `analysisOnly` flag (`Dispatcher.ets:138`, `:161`);
- terminal states: `agents/src/main/ets/graph/AgentState.ets:26-32` already carries `CaptureGraphError.kind` and `.retriable`, but `Dispatcher.ets:147-152` copies only `error.message` into `DispatchResult.errorMessage` and drops both;
- cancellation: `common/src/main/ets/llm/CancellationToken.ets:41-45` throws `new Error('CONVERSATION_CANCELLED')`, which `agents/src/main/ets/graph/CaptureGraph.ets:41-43` immediately rewrites to `NODE_ERROR` with `retriable: false`;
- persistence: the write succeeds in `entry/src/main/ets/database/NoteDao.ets:96` before `agents/src/main/ets/graph/nodes/PersistNode.ets:40` checks the token again.

`NoteGenerationStatus` already names `'cancelled'` and `'committed'` (`common/src/main/ets/models/NoteGenerationModels.ets:22`), but `Dispatcher` never returns either through `DispatchResult` — the vocabulary exists at run level and is missing at the command seam.

## Decision

### (a) `NoteCommand`: five shapes

```ts
type NoteCommand =
  | { kind: 'capture'; operationId: string; source: DispatchSource; payload: DispatchPayload }
  | { kind: 'generation'; mode: 'light' | 'standard' | 'deep'; runId: string;
      instruction: string; sources: SourceBundle; requirement?: NoteGenerationRequirement;
      pendingSourceIds?: string[] }
  | { kind: 'regenerate'; range: RegenerateRange; runId: string;
      instruction: string; sources: SourceBundle }
  | { kind: 'preparedCandidate'; hash: string; commitKey: string; expectedVersion?: number;
      runId: string; checkpointId: string; candidate: KnowledgeUnit }
  | { kind: 'analysisOnly'; source: DispatchSource; payload: DispatchPayload };
```

`RegenerateRange` is `{ targetNoteId: string; baseVersion: number; targetSectionIds?: string[]; mustInclude?: string[]; preserveUserEdits?: boolean }`; `DispatchSource` is the existing `'app' | 'skill' | 'card'` union (`common/src/main/ets/models/CaptureChain.ets:116-123`).

| Command | Current entry branch | Persists? | Idempotency key |
|---|---|---|---|
| `capture` | `Dispatcher.dispatchRequest` capture branch `agents/src/main/ets/core/Dispatcher.ets:131-208`; graph wiring `:1646-1684` (`START → capture → classify → structure → truth_check → persist`) | **Yes by default.** `persist: options.persist !== false` (`:137`), persist edge `:1681`, plain `dao.insert` at `agents/src/main/ets/graph/nodes/PersistNode.ets:91-95`. No write when `persist: false`. | **None today.** `PersistNode.ets:92` is a plain insert and every structure pass mints a fresh `id` (`agents/src/main/ets/agents/CaptureStructurer.ets:191`, `:243`), so replaying the same capture inserts a second note. Target: mandatory `commitKey`; a missing key is rejected with `COMMIT_KEY_REQUIRED` instead of silently double-inserting. |
| `generation(mode: light \| standard \| deep)` | `Dispatcher.ets:125-130` → `:401-701`; standard `:555`, deep `:572`, light `:582-608` | **Run + checkpoint only, no note row.** `saveRun` `:449`, `:688`, `:1340`; `saveCheckpoint` `:645`, `:747-759`; `persist: false` at `:598`. | `runId` + `checkpointId = runId + ':0'` (`:628`). `saveRun` upserts by id (`entry/src/main/ets/database/NoteGenerationRepository.ets:67-81`); `saveCheckpoint` with an existing id is an idempotent no-op (`:120-126`). |
| `regenerate(range)` | `Dispatcher.ets:126-128` → `:210-373` | **Run + checkpoint only, no note row.** `saveCheckpoint` `:345`; returns `ready-preview` `:346-348`. | `runId` + `checkpointId = runId + ':incremental'` (`:333`). `baseVersion` is checked on read (`:239-240`, `VERSION_CONFLICT`), not enforced at write. |
| `preparedCandidate(hash)` | `Dispatcher.ets:122-124` → `:1443-1537`; graph `:1539-1561` (`truth_check → persist`) | **Yes — commits the previewed candidate.** `PersistNode` insert/update with commit key (`PersistNode.ets:25-90`) and commit record `Dispatcher.ets:1518-1528`. | `commitKey` (default `runId:checkpointId:candidateHash`, `:1456`), `candidateHash` (`:1449-1451`), `expectedVersion` via `PersistNode.ets:25-39` → `NoteDao.ets:110-138`. |
| `analysisOnly` | `Dispatcher.ets:131-177` (flag set `:138`, read `:161`); the classify conditional edge goes straight to `END` (`:1677-1679`) | **No.** `persist: false` (`:137`) and `structure`/`truth_check`/`persist` are never reached. | Not applicable (read-only). |

A command carries exactly one `kind`; the legacy fields (`DispatchRequest.generation`, `.preparedCandidate`, `DispatchOptions.analysisOnly`, `.persist`) become an adapter over `NoteCommand`, not the contract itself.

### (b) `NoteOutcome`: five terminal states

```ts
type NoteOutcome =
  | { kind: 'needsInput'; reason: string; issues: NoteGenerationIssue[] }
  | { kind: 'readyPreview'; draft: NoteDraftDocument | KnowledgeUnit; checkpointId: string;
      runId: string; degraded?: DegradedMarker }
  | { kind: 'committed'; noteId: string; version: number; commitKey: string;
      degraded?: DegradedMarker }
  | { kind: 'failed'; code: NoteErrorCode; message: string; retryable: boolean;
      issues?: NoteGenerationIssue[] }
  | { kind: 'cancelled'; committed: boolean; noteId?: string; version?: number; commitKey?: string };

interface DegradedMarker { from: string; to: string; reason: string }
```

Exactly one terminal state per command; `success: boolean` is not part of the new seam (it survives only as a compatibility field on the old `DispatchResult` during #241).

| Terminal state | Current evidence | Current behavior and gap |
|---|---|---|
| `needsInput(reason, issues[])` | `Dispatcher.ets:491-537` — `status: 'needs-input'` at `:503-514`, `questions` built at `:497-502`, returned at `:537`. Also `:264-266` (`NO_UNLOCKED_TARGET`) and `:1295` (standard/deep with no candidate). | Exists as `success: false` + `generation.issues`/`questions`. There is no terminal type, so a caller must inspect `generation.status`. `errorMessage` can be `''` when no question was generated (`:537` joins an empty array). |
| `readyPreview(draft, checkpointId)` | `Dispatcher.ets:628-668` — checkpoint `runId:0` saved at `:645`, `status: 'ready-preview'` at `:647`, `bestCheckpointId` at `:658`; regenerate variant `:333-348`; standard/deep `:1295-1320`. | Exists as `success: true` with `generation.bestCheckpointId`. The checkpoint id lives only in `generation`; `data` (the candidate) does not carry it, so a caller that only reads `data` cannot submit a `preparedCandidate`. |
| `committed(noteId, version)` | `Dispatcher.ets:1518-1536` — commit record with `noteId`/`version` saved at `:1518-1528`, success returned at `:1536`; replay path `:1457-1469`; capture success `:194-207`. | **Partial.** There is no `committed` type. The capture branch returns `finalState.knowledgeUnit` (`:194-198`) whose `id`/`version` come from the in-memory structure pass, not from the transaction. The idempotent replay path `:1458-1469` returns `success: true` with the restored candidate but no commit envelope (`commitKey`, explicit `noteId`/`version`), so a resumed client must parse the candidate JSON to guess what was committed. |
| `failed(code, retryable)` | `Dispatcher.ets:144-160` (capture: only `errorMessage`, `kind`/`retriable` discarded); `:240` `VERSION_CONFLICT`; `:329` merge failure with only `errorMessage`; `:1451`, `:1454`, `:1473`, `:1483` with no code at all; `:1498-1506`; `:692-700`. | Failures exist but are not uniform: some have `errorCode`, several have only Chinese `errorMessage`, and the graph-level `kind`/`retriable` (`AgentState.ets:26-32`) never reaches the caller. |
| `cancelled(committed: boolean)` | Entry: `Dispatcher.ets:120` throws. In-graph: `CaptureGraph.ets:37-43` rewrites the throw to `NODE_ERROR`. After write: `PersistNode.ets:39-40` / `:77-78` check the token *after* the DAO call; `AiService.ets:647-651` + `NoteGenerationRepository.ets:344-347` mark a run cancelled unconditionally; `AiService.ets:625-636` checks `cancelled` before looking for a commit record. | **现状不存在**：`cancelled(committed = true)` 今天没有对应分支，需在 #238/#241 新增。Cancellation is only observable as a thrown `Error`, or as a `NODE_ERROR` failure, or as a run status that can overwrite a committed fact. |

Notes on the two non-obvious states:

- `needsInput` is not `failed`. `MISSING_SOURCE` / `MISSING_INSTRUCTION` / `MISSING_USER_FACT` / `SOURCE_BUDGET_EXCEEDED` are user-fixable questions (`Dispatcher.ets:459-481`), while `process_gate` issues are hard failures (`:503-504`). The outcome keeps both the machine `issues[]` and the human `reason`.
- `committed` must always carry the port-returned `noteId` + `version` + `commitKey`. A `success: true` computed from `candidate !== undefined` (`Dispatcher.ets:693`) is not proof of a durable write.

### (c) Error codes

Rules: existing codes keep their names; a position that today has only a Chinese `errorMessage` gets a new code and is marked "现状：无码，只有文案"; every code has a fixed `retryable`; `NODE_ERROR` is allowed only when no more specific code is known and is never allowed to wrap cancellation or a domain error.

| Code | Status today | `retryable` | Caller action (HITL / A2A receipt / UI) |
|---|---|---|---|
| `OCR_FAILED` | **New.** No code: `OcrNode` lets the recognizer throw (`agents/src/main/ets/graph/nodes/OcrNode.ets:23`), `CaptureGraph.ets:41-43` wraps it as `NODE_ERROR`, `Dispatcher.ets:147-152` keeps only the message. `CAPTURE_NO_PAYLOAD` already exists for the programming error (`OcrNode.ets:11-21`). `ApiCodeMap.OCR_FAILED: 2001` (`common/src/main/ets/models/CaptureChain.ets:162`) is a legacy API code the pipeline never emits. | `true` | UI: re-shoot / retry. HITL: do not create a draft. A2A: `failed` with retryable hint. |
| `CAPTURE_TEXT_REFINEMENT_FAILED` | **Exists** (`agents/src/main/ets/graph/nodes/ClassifyNode.ets:15-24`): image text cleanup did not reach `refined`. | `true` | UI: retry or re-shoot. HITL: no draft. A2A: retryable failure. |
| `CLASSIFY_FAILED` | **New. 现状：无码，只有兜底** — `TypeClassifier.classifyPreparedText` catches LLM/schema failures and returns a rule fallback instead of failing (`agents/src/main/ets/agents/TypeClassifier.ets:136-147`, `ocrTextQuality: 'fallback'`); empty text returns a fixed fallback (`:115-123`); only image payloads turn a non-`refined` quality into `CAPTURE_TEXT_REFINEMENT_FAILED` (`ClassifyNode.ets:15-24`). `CLASSIFY_LOW_CONF: 2002` exists only in the legacy map (`CaptureChain.ets:163`) and is never emitted. | `false` | UI: when no usable classification exists, ask for clearer input; the rule fallback case is a `degraded` marker, not a silent success. HITL: do not present a fallback classification as model output. A2A: non-retryable. Transport causes must surface as `NETWORK_ERROR`/`TIMEOUT`/`STREAM_FAILED`, not as this code. |
| `STRUCTURE_ERROR` | **Exists** (`agents/src/main/ets/graph/nodes/StructureNode.ets:84-89`). Today it also absorbs transport causes and copies their `retriable` (`:78-83`); the target contract keeps the code for structural/parse failures only and surfaces transport causes as `NETWORK_ERROR`/`TIMEOUT`/`STREAM_FAILED`. | `false` | HITL: keep the source, retry with a narrower scope or regenerate. UI: show the structure failure. A2A: non-retryable. |
| `TRUTH_CHECK_ERROR` | **Exists** (`agents/src/main/ets/graph/nodes/TruthCheckNode.ets:29-37`). | `false` | HITL: show the failed checks; do not offer "confirm". UI: show the verification message. A2A: non-retryable. |
| `DOMAIN_VALIDATION_ERROR`, `JSON_SCHEMA_ERROR`, `JSON_EXTRACTION_ERROR`, `JSON_PARSE_ERROR`, `LLM_TRUNCATED` | **Exist** (`agents/src/main/ets/agents/GenerationJsonCaller.ets:53-59`); truncation throws with `retriable=false` (`:136`). | `false` | HITL: no confirm until the draft validates; allow an explicit regenerate. UI: explain the draft was rejected. A2A: non-retryable. |
| `NETWORK_ERROR`, `TIMEOUT`, `STREAM_FAILED` | **Exist** as `LlmErrorKind` (`common/src/main/ets/llm/LlmTypes.ets:83`, `:87`, `:88`) and are the only kinds treated as retryable (`GenerationJsonCaller.ets:62`, `:204`). | `true` | UI: retry with backoff. HITL: keep the preview, no re-commit. A2A: retryable receipt. |
| `API_ERROR`, `PARSE_ERROR`, `EMPTY_RESPONSE`, `NO_API_KEY`, `MODEL_SPEC_INCOMPLETE` | **Exist** (`LlmTypes.ets:81-91`); `GenerationJsonCaller.ets:204` leaves them non-retryable. | `false` | UI: show configuration/provider error. HITL: no draft. A2A: non-retryable, include the reason. |
| `MODEL_UNAVAILABLE` | **New at the pipeline seam.** Today only the A2A layer has codes — `A2A_MODEL_UNUSABLE` / `A2A_MODEL_ID_UNRESOLVED` (`entry/src/main/ets/agentextability/AgentExtAbility.ets:450`, `:458`) — and `ResolvedModel.usable=false` (`common/src/main/ets/llm/model-resolver.ets:140`) is never mapped to a pipeline error; `LlmConfig` only warns (`common/src/main/ets/llm/LlmConfig.ets:324-325`). | `false` | UI: open model settings. HITL: no draft. A2A: `failed` with a non-retryable reason. Must not be reported as a model answer (see (d)). |
| `VERSION_CONFLICT` | **Exists** (`entry/src/main/ets/models/KnowledgeUnitWriteModels.ets:13-15`; thrown at `entry/src/main/ets/database/NoteDao.ets:118-123`, `:128-134`; surfaced at `Dispatcher.ets:240`, `:1498-1506`). | `false` | HITL: return to preview; re-read the note, do not retry the same `expectedVersion`. UI: refresh and re-confirm. A2A: non-retryable, ask for a new preview. |
| `APPROVAL_HASH_MISMATCH` | **New. 现状：无码，只有文案** — `Dispatcher.ets:1449-1451` returns `'候选内容已变化'`; the checkpoint mismatch at `:1482-1483` returns `'草稿检查点不匹配'`. | `false` | HITL: discard the stale candidate, preview again. UI: reload the draft. A2A: non-retryable. |
| `PREPARED_CHECKPOINT_MISSING` | **New. 现状：无码，只有文案** — `'缺少草稿检查点'` (`Dispatcher.ets:1453-1454`) and `'草稿运行不存在'` (`:1471-1473`). | `false` | HITL: regenerate the draft. UI: show "草稿已失效". A2A: non-retryable. |
| `CANCELLED` | **New as an outcome.** Only a thrown message exists: `throw new Error('CONVERSATION_CANCELLED')` (`common/src/main/ets/llm/CancellationToken.ets:41-45`); the harness baseline records the inconsistency (`scripts/arkts-lint/tests/knowledge-baseline.md:55`). | `false` (no automatic retry; the user may re-issue the command) | UI: no error toast; offer manual retry. HITL: keep the uncommitted preview. A2A: settle once with `cancelled`; never resend. |
| `MISSING_SOURCE`, `MISSING_INSTRUCTION`, `MISSING_USER_FACT`, `SOURCE_BUDGET_EXCEEDED` | **Exist** (`Dispatcher.ets:459`, `:462`, `:465`, `:475-479`). | `false` | These are `needsInput`, not `failed`: UI asks the question; HITL keeps the workflow open; A2A returns the questions. |
| `NOTE_ID_REQUIRED`, `BASE_VERSION_REQUIRED`, `REGENERATION_REPOSITORY_REQUIRED`, `NOTE_NOT_FOUND`, `NO_UNLOCKED_TARGET` | **Exist** (`Dispatcher.ets:217`, `:220`, `:223`, `:237`, `:266`). | `false` | Caller bug or stale UI: fix the request; do not retry unchanged. |
| `PERSIST_DAO_REQUIRED`, `PERSIST_NO_UNIT`, `PERSIST_UPDATE_UNSUPPORTED`, `PERSIST_ERROR` | **Exist** (`Dispatcher.ets:1549`, `:1665`; `PersistNode.ets:16`, `:57`, `:44`/`:82`). | `false` | Wiring/data error: fail the command; alert, do not re-commit. |
| `NODE_ERROR`, `INVALID_GRAPH`, `MAX_NODE_RUNS`, `COMMIT_KEY_REQUIRED` | **Exist** (`CaptureGraph.ets:43`, `:68`; `common/src/main/ets/workflow/StateGraph.ets:61`). `COMMIT_KEY_REQUIRED` is **new** and belongs to #238. | `false` | Last-resort code only; when a domain code is known it must be preserved instead. |

Model unavailability and degradation are two different things:

- **Retryable transport failure** — `NETWORK_ERROR` / `TIMEOUT` / `STREAM_FAILED`, `retryable: true`.
- **Capability not usable** — `MODEL_UNAVAILABLE` / `NO_API_KEY` / `MODEL_SPEC_INCOMPLETE`, `retryable: false`.
- **Degradation is not a failure** — a downgrade (deep→standard source-budget downgrade, on-device→remote fallback, LLM-classify→rule fallback) keeps the outcome successful and attaches `degraded: { from, to, reason }` plus the user-facing marker `已降级：<原因>`. Precedent: `entry/src/main/ets/agentextability/AgentExtAbility.ets:463-465`; `entry/src/main/ets/services/ModelRouter.ets:48-53`. Gaps: the deep→standard downgrade only writes a log line (`Dispatcher.ets:424-428`) and changes `route`, with no marker in the result (`common/src/main/ets/models/NoteGenerationModels.ets:373-398` has no `degraded` field); the classification rule fallback only sets `ocrTextQuality: 'fallback'` (`TypeClassifier.ets:136-147`), which is not a degradation marker. `ResolvedModel.degraded` cannot be reused: it is `false` on every return path (`common/src/main/ets/llm/model-resolver.ets:95`, `:111`, `:128`, `:141`) and alias normalization is reported through `reason: 'ALIAS_RESOLVED:…'` (`:128-129`).

### (d) Two boundaries

**失败不得伪装成成功.** A failed command may only produce `failed`; it must never return `data` with `success: true`. ADR-0008 already sets the policy for AI failure: throw `CaptureGraphError` and short-circuit, generate no fallback `KnowledgeUnit` (`docs/adr/0008-capturegraph-self-built-runtime.md:21`). The current seam has two counterexamples that this ADR closes:

1. `dispatchPreparedCandidate` returns `success: true` at `Dispatcher.ets:1536` even when `finalState.commitResult === undefined`. Because `PreparedCandidate.commitKey` is optional (`common/src/main/ets/models/NoteGenerationModels.ets:324-336`), and `PersistNode` checks the *raw* `preparedCandidate.commitKey` (`PersistNode.ets:64`) rather than the default computed in `Dispatcher.ets:1456`, such a request falls into the plain `dao.insert` branch (`PersistNode.ets:91-95`): a note is written with no idempotency key and no commit record, and the caller cannot tell.
2. The idempotent replay at `Dispatcher.ets:1457-1469` returns `success: true` with a bare `KnowledgeUnit` and no commit envelope (`commitKey`, explicit `noteId`/`version`), so a retry cannot distinguish "already committed" from "newly committed".

Rule: `committed` requires a commit result returned by the write port (`noteId` + `version` + `commitKey`). No commit result means the command was not committed; if the command intended to persist, the outcome is `failed` with `PERSIST_ERROR`, never a success-shaped object.

**兜底文案不得冒充回答.** When the model cannot be used, the user-facing notice must not be returned as if it were the model's answer. The A2A path already states the intent — `MODEL_NOT_READY` is annotated "不调模型，也不假装回答" (`AgentExtAbility.ets:106-108`) and is returned as the reply text at `:520-522` — but because it travels in the same `text` field as a model reply, a downstream consumer can persist or display it as an assistant answer. `ModelRouter` shows the correct alternative: throw an explicit error instead of answering (`ModelRouter.ets:55`, `:66`). Rule: a fallback notice is a `failed(MODEL_UNAVAILABLE)` outcome or a distinctly flagged non-answer, never a `committed`/`readyPreview` payload, never stored as note content, and never counted as a successful model call. Reply-body formatting stays governed by ADR-0016.

### (e) Cancellation semantics

Cancellation has three distinct positions, and only the write port knows whether the third one already crossed the commit boundary.

| Position | Current behavior | Target |
|---|---|---|
| **Entry cancel** (before the graph starts) | `Dispatcher.ets:120` calls `throwIfCancelled()` before any work; the throw escapes as `Error('CONVERSATION_CANCELLED')` (`CancellationToken.ets:41-45`). | `cancelled(committed: false)` — no side effect, return a terminal outcome instead of a raw throw at the new seam. |
| **In-graph cancel** (a node observes the token) | Nodes call `throwIfCancelled()` (`OcrNode.ets:22`, `:24`; `ClassifyNode.ets:10`, `:12`; `StructureNode.ets:65`; `TruthCheckNode.ets:10`, `:27`; `PersistNode.ets:10`); `CaptureGraph.ets:37-43` catches the throw and rewrites it to `NODE_ERROR`, `retriable: false`. The baseline records this as "light 途中取消返回失败、issue code 为 `NODE_ERROR`" (`scripts/arkts-lint/tests/knowledge-baseline.md:55`). After the graph returns, `Dispatcher.ets:143` re-checks and throws again. | `cancelled(committed: false)` (or `committed: true` if the write already landed). Cancellation must not be converted into `NODE_ERROR`, and `retryable` must not be `false` for it. |
| **Cancel after commit** (the write already committed) | `NoteDao` commits the transaction at `NoteDao.ets:96`; `PersistNode` then checks the token at `PersistNode.ets:40` (update) and `:78` (insert) and throws, which becomes `NODE_ERROR`; nothing deletes the committed row. At run level, `AiService.cancelDraft` (`AiService.ets:647-651`) sets `status = 'cancelled'` unconditionally (`NoteGenerationRepository.ets:344-347`), and `restoreDraft` checks `cancelled` **before** the commit record (`AiService.ets:625-636`). | `cancelled(committed: true, noteId, version, commitKey)`. **`cancelled(committed = true)` does not exist today; it is added in #238/#241.** 已落库的写不能靠 `CancellationToken` 撤回；唯一正确的响应是如实报告为 committed。 |

Who decides `cancelled(committed: true)`: the persist node / `NoteWritePort`, because it is the only component that holds the transaction result. The rule is ordered — first read `commitResult`, then read the token. If `commitResult !== undefined`, the outcome is `cancelled(committed: true)`; if the token is cancelled and no commit result exists, `cancelled(committed: false)`. `Dispatcher` must not infer commit state from the token, and the run row must never overwrite a commit record with `cancelled` (the #238 `RunStore` contract).

## Considered Options

1. **Keep the flat `DispatchResult` and add more boolean fields** — rejected: `success` already carries three meanings (needs input, failed, cancelled), and adding `committed?: boolean` would still let a caller read `data` without knowing whether it is durable.
2. **One result class per command** — rejected: five near-identical envelopes, and every consumer (HITL, A2A receipt, UI) would switch on the command instead of the terminal state.
3. **Discriminated `NoteCommand` + `NoteOutcome`, with the old `DispatchResult` kept as a migration adapter** *(chosen)* — one exhaustive switch per caller, stable codes, and a single place (#238 ports) that owns idempotency, version checks and the committed/cancelled distinction.
4. **Fold cancellation into `failed` with `code: 'CANCELLED'`** — rejected: cancellation is not an error and must not be retried automatically; folding it loses the required `committed` flag and reproduces today's `NODE_ERROR` confusion.

## Consequences

- **#238** implements the contract at the ports: `commitKey` required, `expectedVersion` CAS, `approvedCheckpointHash`, idempotent replay returning the first `noteId`/`version`/`commitKey`, and a `RunStore` that stores the terminal outcome including `committed`/`cancelled`. `Dispatcher` keeps its old `DispatchResult` as an adapter until #241.
- **#239** records one golden snapshot per command and terminal state (not per branch name), including `cancelled(committed=true)` and the two hash-mismatch cases; those snapshots are the "nothing changed" criterion for #241.
- **#241** moves only the capture branch behind `NoteAgent`; the other four commands keep their current wiring, so the outcome mapping must be behavior-preserving except for the newly exposed codes and flags.
- Callers must switch exhaustively on `outcome.kind`; TypeScript/ArkTS exhaustiveness is the guard against a new terminal state being silently ignored.
- Logs and A2A receipts carry `code`, `retryable`, and (for cancellation) `committed`; this is what makes a failure attributable without reading Chinese message text. Text matching such as `error.message.indexOf('VERSION_CONFLICT')` (`Dispatcher.ets:1499`) is replaced by `error.code`.
- `NODE_ERROR` becomes a last-resort code. `CaptureGraph` must stop flattening domain errors and cancellation (`CaptureGraph.ets:41-43`), or the new codes never reach the caller.
- No change to the runtime decision of ADR-0008: LangGraph's model implemented natively in ArkTS, no Python sidecar. This ADR only fixes the command/outcome vocabulary at the `Dispatcher` seam.

## Reversibility

**Medium.** The unions are additive at the seam and the old `DispatchResult` can coexist during #241, but once HITL, A2A receipts and UI switch on `outcome.kind`, changing a terminal state or a code becomes a cross-module change. The five command shapes and five terminal states are expected to survive the `NoteAgent` migration; the concrete error-code list can grow without breaking callers.

## Related

- [0008 — Agent workflows: the LangGraph model, implemented natively in ArkTS](./0008-capturegraph-self-built-runtime.md) — the runtime decision this contract sits on; its Subgraph scope is revised there on 2026-10-27
- [0016 — Reply contract by transport](./0016-reply-contract-by-transport.md) — a chat reply body is model output; a fallback notice is not
- [0018 — Note evidence provenance](./0018-note-evidence-provenance.md) — verification results become `issues[]`, not free-form messages
- [v7 review §4 and 附](../architecture/review-v7-2026-10-27.md) — why a separate ADR is required for command/outcome semantics
- [#238 ports](../specs/execution/v7-architecture-contracts/tasks.md) — `commitKey` / `expectedVersion` / `approvedCheckpointHash` / `RunStore`
- [KnowledgeModel behavior baseline](../../scripts/arkts-lint/tests/knowledge-baseline.md) — the three inconsistent cancellation/error shapes this ADR replaces
