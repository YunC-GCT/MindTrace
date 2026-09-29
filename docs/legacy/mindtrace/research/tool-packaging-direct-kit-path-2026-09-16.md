# Tool Packaging — Direct Kit/ToolRegistry Path for MindTrace Tools — 2026-09-16

> **Date**: 2026-09-16 · **Author note**: research subagent output
> **Scope**: Decide whether future tool implementations should adopt the existing `ToolRegistry` / `ToolCatalog` / `AgentTool` 4 件套 pattern directly (per [ADR-0012](../adr/0012-tool-calling-protocol.md) / [spec 014](../specs/014-tool-calling-protocol.md)) vs the MCP-style path (`agents/src/main/ets/mcp/tools/OcrTool.ets`).
> **Trigger**: [`docs/research/capturegraph-architecture-evolution-2026-09-16.md`](./capturegraph-architecture-evolution-2026-09-16.md) §10.5 #5–#8 — user decisions deferred pending packaging research.
> **Method**: every cited file opened and verified, all references `path:LINE`.

---

## §1 What is "direct Kit/ToolRegistry packaging"?

A tool packaged via the direct Kit/Tool path is an `AgentTool` registered into `ToolRegistry`, callable by LLM via the OpenAI-compatible function-calling wire protocol (`tools` / `tool_choice` / `tool_calls`) and/or callable directly by workflow nodes via `registry.execute(name, argsJson)`. Three contracts + one factory:

### 1.1 `AgentTool` 4 件套 — the minimum contract

[`common/src/main/ets/tools/ToolRegistry.ets:17-22`](../../common/src/main/ets/tools/ToolRegistry.ets):

```ts
export interface AgentTool {
  name: string;                                   // ^[a-z][a-z0-9_]{0,63}$ (ToolRegistry.ets:25)
  description: string;
  parameters: Record<string, Object>;             // JSON Schema object (ArkTS 惯例, 同 LlmGuard)
  execute(args: Record<string, Object>): Promise<ToolResult>;
}
```

- **Naming rule** ([`ToolRegistry.ets:25`](../../common/src/main/ets/tools/ToolRegistry.ets)) — `^[a-z][a-z0-9_]{0,63}$`, **deliberately stricter** than the OpenAI wire rule `^[a-zA-Z0-9_-]{1,64}$` (spec 014 §2 / spec [014:75](../specs/014-tool-calling-protocol.md)); bad names are rejected at registration, not at send-time.
- **`parameters`** is a JSON Schema object (not ArkTS class). The 3 P1 tools use `Record<string, Object>` assignment with bracket notation ([`NoteQueryTools.ets:35-47`](../../common/src/main/ets/tools/NoteQueryTools.ets)) — strict-mode ArkTS cannot use untyped object literals.
- **`execute` returns `Promise<ToolResult>`** — the result is fed back to the LLM as a string (`ToolResult.content`).

### 1.2 `ToolResult` — the LLM-feeding shape

[`ToolRegistry.ets:11-14`](../../common/src/main/ets/tools/ToolRegistry.ets):

```ts
export interface ToolResult { ok: boolean; content: string; }
```

`content` is what gets fed back to the LLM (ReAct 慣例). Failures return `ok:false, content:'<reason>'` — **never throw** at the registry boundary ([`ToolRegistry.ets:57-76`](../../common/src/main/ets/tools/ToolRegistry.ets)).

### 1.3 `ToolRegistry` — 4 public methods

[`ToolRegistry.ets:27-76`](../../common/src/main/ets/tools/ToolRegistry.ets):

| Method | file:line | Behavior |
|---|---|---|
| `register(tool)` | `:31-40` | Duplicate / bad name → `throw new LlmError(kind='TOOL_REGISTRY_ERROR')`. Mutates internal `toolMap` + `toolList`. |
| `has(name)` | `:42-44` | Lookup, no side effects. |
| `listDefinitions()` | `:46-54` | Convert to OpenAI wire `LlmToolDefinition[]` (`{type:'function', function:{name,description,parameters}}`) — what gets attached to `LlmRequestBody.tools`. |
| `execute(name, argsJson)` | `:57-76` | **Fault-tolerant**: unknown tool → `ok:false 'unknown tool: '+name`; bad JSON → `ok:false 'invalid tool arguments for '+name+': ...'`. Never throws. |

The fault-tolerance design ([spec 014:74](../specs/014-tool-calling-protocol.md)) is the central reason this works for LLM callers — the model can hallucinate tool names or arguments and the loop does not crash; the model self-recovers via the `tool` role message.

### 1.4 `ToolCatalog` — factory

[`common/src/main/ets/tools/ToolCatalog.ets:18-26`](../../common/src/main/ets/tools/ToolCatalog.ets):

```ts
export class ToolCatalog {
  static createReadOnlyRegistry(): ToolRegistry {
    const registry: ToolRegistry = new ToolRegistry();
    const tools: AgentTool[] = createReadOnlyNoteTools();
    for (const tool of tools) { registry.register(tool); }
    return registry;
  }
}
```

- **Static factory, not constructor** (`:19` comment) — comment: "便于 ArkTS Hypium seam 测试注入" (consistent with [spec 014:11-13](../specs/014-tool-calling-protocol.md)). The composition root (entry / skill) controls which tools are wired.
- **Single production caller today**: [`SkillAbility.ets:27`](../../skill/src/main/ets/skillability/SkillAbility.ets) — `ToolCatalog.createReadOnlyRegistry()`. grep across `entry/src/main/ets` for `ToolRegistry|ToolCatalog|ToolLoop` returns **0 matches** (verified 2026-09-16).

### 1.5 Wire protocol — OpenAI-compatible

[`common/src/main/ets/llm/LlmTypes.ets`](../../common/src/main/ets/llm/LlmTypes.ets):

| Direction | Field | file:line |
|---|---|---|
| Request body | `LlmRequestBody.tools?: LlmToolDefinition[]` | `:32` |
| Request body | `LlmRequestBody.tool_choice?: string` (Phase 1: `'auto'\|'none'`) | `:33` |
| Request (call shape) | `LlmCallRequest.tools?: LlmToolDefinition[]` | `:213` |
| Request (call shape) | `LlmCallRequest.tool_choice?: string` | `:214` |
| Response | `LlmCallResult.toolCalls?: LlmToolCall[]` | `:224` (filled by `extractToolCalls`) |
| ChatMessage loop-back | `role: 'system' \| 'user' \| 'assistant' \| 'tool'` (added `'tool'`) | `:14` |
| ChatMessage loop-back | `tool_call_id?: string` | `:17` |
| ChatMessage loop-back | `tool_calls?: LlmToolCall[]` | `:18` |

All fields **additive / optional** — backward-compatible with prior requests.

### 1.6 The loop — `ToolLoop` + `ToolCallingWorkflow`

[`common/src/main/ets/tools/ToolLoop.ets:14-24`](../../common/src/main/ets/tools/ToolLoop.ets) is a 25-LOC shell:

```ts
export class ToolLoop {
  private llm: LlmCaller;
  constructor(llm: LlmCaller) { this.llm = llm; }
  async run(messages: ChatMessage[], registry: ToolRegistry, options?: ToolLoopOptions): Promise<LlmCallResult> {
    return await new ToolCallingWorkflow(this.llm, registry).run(messages, options);
  }
}
```

[`ToolCallingWorkflow.ets:11-68`](../../common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets) is the StateGraph ReAct loop (`DEFAULT_MAX_STEPS = 4`, `:9`):

```
START → call_model
       ├─ toolCalls empty    → END
       └─ toolCalls present  → execute_tools
                              ├─ stepCount >= maxSteps → max_steps_error → LlmError('TOOL_LOOP_MAX_STEPS')
                              └─ stepCount <  maxSteps → call_model (loop)
```

JSON path only ([`ToolLoop.ets:6`](../../common/src/main/ets/tools/ToolLoop.ets) comment) — SSE + tool-loop is **out of scope** (spec 014 §"Out of scope" + [capturegraph-architecture-evolution §10.2 S3](./capturegraph-architecture-evolution-2026-09-16.md)).

---

## §2 NoteQueryTools as the reference implementation

Three concrete `AgentTool` implementations live at [`common/src/main/ets/tools/NoteQueryTools.ets`](../../common/src/main/ets/tools/NoteQueryTools.ets) (253 LOC), composed by `createReadOnlyNoteTools()` (`:250-253`) into the catalog.

### 2.1 The 3 tools

| Tool class | file:line | `name` | Description (verbatim) | Parameters | SQL / query |
|---|---|---|---|---|---|
| `NoteQueryTool` | `:50-126` | `note_query` | "Search saved math notes (KnowledgeUnit). Filter by subject, review_status, or keyword (matches title or content). Returns at most 20 notes as a JSON array of metadata." | `{subject?, review_status?, keyword?}` | `RdbPredicates` on `knowledge_unit` with `equalTo` + `beginWrap / contains / or / endWrap` (`:77-95`); `limitAs(20)` (`:96`) |
| `NoteGetTool` | `:129-193` | `note_get` | "Fetch one saved math note by id, including full Markdown content. Returns a JSON object, or a 'not found' message." | `{id}` (required) | `equalTo('id', id)` + 17-column SELECT (`:157`) |
| `ReviewDueQueryTool` | `:196-247` | `review_due_query` | "Count saved math notes grouped by review status (new / learning / review / graduated / lapsed). Optionally pass review_status to count one status only." | `{review_status?}` | `querySql('SELECT review_status, COUNT(*) ... GROUP BY ...')` (`:226, 232`) |

### 2.2 Public interface — `AgentTool` 4 件套

Each tool exposes the canonical 4 methods/fields. Example from `NoteQueryTool` ([`NoteQueryTools.ets:50-126`](../../common/src/main/ets/tools/NoteQueryTools.ets)):

```ts
export class NoteQueryTool implements AgentTool {
  public name: string = 'note_query';                              // :51
  public description: string = 'Search saved math notes ...';      // :52
  public parameters: Record<string, Object>;                       // :53 (built in ctor:55-61)
  async execute(args: Record<string, Object>): Promise<ToolResult> { ... }
}
```

Parameters are assembled via two small builders (`NoteQueryTools.ets:35-47`):

```ts
function stringProp(description: string): Record<string, Object> {
  const prop: Record<string, Object> = {};
  prop['type'] = 'string';
  prop['description'] = description;
  return prop;
}
function objectSchema(props: Record<string, Object>): Record<string, Object> {
  const schema: Record<string, Object> = {};
  schema['type'] = 'object';
  schema['properties'] = props;
  return schema;
}
```

— bracket-assignment because ArkTS strict forbids untyped object literals.

### 2.3 Wire path — 3 hops from SkillAbility to NoteDao

```
SkillAbility.handleWant                     // :20-46
  ├─ request.target === 'search_note' → DatabaseHelper.init(this.context)  // :25
  ├─ ToolCatalog.createReadOnlyRegistry()                                 // :27
  │     └─ new ToolRegistry() + [NoteQueryTool, NoteGetTool, ReviewDueQueryTool]
  └─ new SkillIntentWorkflow(registry).run(request)                       // :28
        └─ execute_search node → registry.execute('note_query', argsJson)  // :38
              └─ NoteQueryTool.execute → store.query → JSON.stringify(rows) → ToolResult
```

— [`SkillAbility.ets:1-48`](../../skill/src/main/ets/skillability/SkillAbility.ets), [`SkillIntentWorkflow.ets:35-56`](../../skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets).

### 2.4 Uniform error shape

All three tools return the same `ok:false, content:'store not ready'` when `DatabaseHelper.getStore() === null` ([`:72-76, 149-153, 218-222`](../../common/src/main/ets/tools/NoteQueryTools.ets)):

```ts
const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
if (store === null) {
  const notReady: ToolResult = { ok: false, content: 'store not ready' };
  return notReady;
}
```

Additional validation errors return their own descriptive content:
- `NoteQueryTool` (`NoteQueryTools.ets:65-71`): `review_status` not in `LEGAL_REVIEW_STATUSES` → `'review_status must be one of: ' + LEGAL_REVIEW_STATUSES.join(', ')`.
- `NoteGetTool` (`NoteQueryTools.ets:144-148`): missing `id` → `'note_get requires id'`.
- `ReviewDueQueryTool` (`NoteQueryTools.ets:208-217`): same status check.

This uniformity is essential because the LLM reads the content text and decides next steps; every tool body writes strings the LLM can parse.

### 2.5 Schema source-of-truth note

[`NoteQueryTools.ets:5-7`](../../common/src/main/ets/tools/NoteQueryTools.ets) file-header explicitly states:

> "schema source-of-truth: entry/src/main/ets/database/NoteDao.ets — knowledge_unit 表与列名 以 NoteDao 为准, 本文件只读直查; 两端漂移时以 NoteDao 为准修这里"

— this is the [ADR-0012 §Consequences](../adr/0012-tool-calling-protocol.md) "schema ownership caveat" and [spec 014 §4](../specs/014-tool-calling-protocol.md) "schema 归属警示" — surfaced as `soft drift #9` in [capturegraph-architecture-evolution §10.1](./capturegraph-architecture-evolution-2026-09-16.md).

### 2.6 Why this pattern works as reference

The 3 readonly tools demonstrate the four elements every AgentTool needs:

1. **Name + Description** — what the LLM sees in `tools: [...]`.
2. **Parameters schema** — what the LLM uses to build arguments.
3. **`execute(args)`** — what runs on the host, returning `ToolResult.content` as the LLM-feeding string.
4. **Failure shape** — uniform `{ok:false, content:'...'}` string that the LLM can read.

All three avoid `entry` imports ([ToolRegistry.ets:5](../../common/src/main/ets/tools/ToolRegistry.ets) + spec 014 acceptance item — "无任何 entry import 出现在 common/src/main/ets/tools/"). The `knowledge_unit` table is accessed via `common/src/main/ets/DatabaseHelper` (which wraps `relationalStore`), not via any `entry`-side DAO.

---

## §3 Direct path for ToolLoop wiring (items #5–#8)

Each of the 4 items the user wants implementation for, analyzed against the direct Kit/Tool path.

### §3.1 H1 — ToolLoop 接 ConversationWorkflow ([§10.5 #5](./capturegraph-architecture-evolution-2026-09-16.md))

**Current state**: [`ConversationWorkflow.ets:1-23`](../../entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets) import list does NOT include `ToolRegistry` / `ToolCatalog` / `ToolLoop`. `handleCompleteReply` (`ConversationWorkflow.ets:283-312`) calls `replyService.complete()` → `ReplyService.guardedComplete` ([`ReplyService.ets:53-66`](../../entry/src/main/ets/services/ReplyService.ets)) → `LlmGuard.callJsonWithRetry`. `handleStreamReply` (`ConversationWorkflow.ets:318-372`) calls `replyService.stream()` ([`ReplyService.ets:68-146`](../../entry/src/main/ets/services/ReplyService.ets)) → `client.call({stream:true, onDelta})` → SSE parsing. **No `tools` field is attached**.

**Direct Kit/Tool path — recommended**:
- Composition root: `EntryAbility.onCreate` constructs one `ToolRegistry` (via `ToolCatalog.createReadOnlyRegistry()`) and passes it into `AgentChatService` → `ReplyService` → `ConversationWorkflow`. The `common/src/main/ets/Index.ets:212-219` already exports all needed types.
- `ReplyService.stream()` and `ReplyService.complete()` gain an optional `tools?: LlmToolDefinition[]` parameter — built once via `registry.listDefinitions()`.
- `ConversationWorkflow` adds no new node — `handleStreamReply` / `handleCompleteReply` pass `replyContext` to `ReplyService` unchanged except for an extra `tools`. The `tool_calls` callback (if any) is a future SSE work item (see §3.2).

| Dimension | Direct Kit/Tool |
|---|---|
| Wrapping cost | Low — 1 new field on `ReplyContext`, 1 new optional arg on `stream()`/`complete()`, 1 wiring line in `EntryAbility` |
| LLM integration | Trivial — `LlmCallRequest.tools?: LlmToolDefinition[]` already exists (`LlmTypes.ets:213`); `CallModelNode` pattern reusable |
| Tool loop wiring | **Doesn't need a loop here** — chat reply is single-shot; the loop is for cases where the LLM autonomously calls tools. P1 readonly tools (`note_query` etc.) may want loop when user asks "搜一下我之前记的级数笔记" — handled by a **new `tool_call_reply` node** that wraps `ToolLoop.run(messages, registry)` |
| SSE events | see §3.2 |
| External exposure | Same registry is reusable by skill (`SkillAbility.ets:27`) — no second surface |
| Existing alignment | **Strongest** — uses the exact 4 件套 pattern already in production (skill) |
| Type strictness | ✅ — ArkTS-strict; no new types needed |

**Pros**: minimal new code, leverages existing pattern, reuses the `tools` field already on `LlmCallRequest`, allows the same registry to serve both chat (when a tool helps the reply) and tool-driven chat ("查笔记 → 总结"). **Cons**: introduces two reply paths (single-shot + tool loop) — both must be handled in `ConversationState`; UI sink must distinguish stream-without-tools vs stream-with-tools (see §3.2).

**Effort**: **M** (1 PR): registry injection + tools field + optional `tool_call_reply` node + tests for both paths.

---

### §3.2 S3/S4 — SSE tool_call/tool_result emit + ToolLoop event output ([§10.5 #6](./capturegraph-architecture-evolution-2026-09-16.md))

**Current state**: [`LlmTypes.ets:129`](../../common/src/main/ets/llm/LlmTypes.ets) already defines all 4 `StreamEventType` values:

```ts
export type StreamEventType = 'thinking' | 'text' | 'tool_call' | 'tool_result';
export interface StreamToolCallEvent { type: 'tool_call'; delta: string; toolCallId?: string; toolName?: string; argumentsJson?: string; }  // :141-147
export interface StreamToolResultEvent { type: 'tool_result'; delta: string; toolCallId?: string; toolName?: string; result?: string; ok?: boolean; }  // :149-156
```

— types are ready. **But** [`parseStreamEventsFromSseData` (`LlmClient.ets:497-522`)](../../common/src/main/ets/llm/LlmClient.ets) currently emits only `thinking` + `text` (`ToolLoop.ets:6` comment: "SSE 流式工具循环不在 spec 014"). This is the root gap for both S3 and S4.

**Direct Kit/Tool path — required**:
1. **SSE emit (S3)**: extend `parseStreamEventsFromSseData` to detect `delta.tool_calls` field on the OpenAI SSE chunk and emit `StreamToolCallEvent` with `toolCallId` / `toolName` / `argumentsJson` (incremental, matches the SSE wire — OpenAI streams tool-call arguments incrementally).
2. **ToolLoop event sink (S4)**: extend [`ToolLoopOptions`](../../common/src/main/ets/workflow/tool-calling/ToolCallingState.ets:5-8) with `sink?: (event: StreamEvent) => void`. Pass it into the `StateGraph` so `CallModelNode` emits `tool_call` events and `ExecuteToolsNode` emits `tool_result` events after each `registry.execute(...)` (currently both nodes return state only).
3. **Result body contract**: when `ToolLoop.run` returns `LlmCallResult` with `streamed:true`, callers that want `toolCalls` must rely on the sink — `LlmCallResult.toolCalls` ([`LlmTypes.ets:224`](../../common/src/main/ets/llm/LlmTypes.ets)) is only populated on the JSON path (`CallModelNode.ets:29`).

**Pros**: brings UI parity (process visibility) between tool-loop chat and CaptureGraph's error states; allows `ReplyService` to feed tool events back into the chat sink. **Cons**: stateful incremental `argumentsJson` reassembly on SSE is non-trivial (arguments span multiple chunks); `ToolLoopOptions.sink` is a new public surface — must update `SkillAbility` and any other caller.

**Effort**: **L** (2-3 PRs): (a) SSE parsing + emit; (b) ToolLoop sink + event shapes; (c) UI integration test on a long-form tool loop.

---

### §3.3 S5 — P1 tools in entry/agents wiring ([§10.5 #7](./capturegraph-architecture-evolution-2026-09-16.md))

**Current state**: grep across `entry/src/main/ets` for `ToolRegistry | ToolCatalog | ToolLoop` returns **0 matches** (verified 2026-09-16). grep across `agents/src/main/ets` returns 2 matches, both **comments** only ([`PromptBuilder.ets:5`](../../agents/src/main/ets/agents/PromptBuilder.ets), [`KnowledgeModel.ets:7`](../../agents/src/main/ets/agents/KnowledgeModel.ets)). The only production consumer is `skill/`.

**Direct Kit/Tool path — recommended**:
- **Where should the registry live?** Per [ADR-0012 §Chosen 1](../adr/0012-tool-calling-protocol.md), `common/` is correct — it's reachable by both `entry` (HAP) and `skill` (HSP) per [`agent-toolkit-and-skill-dispatch §5.1`](./agent-toolkit-and-skill-dispatch-2026-09-06.md) "skill 是 HSP, **不可依赖 entry HAP**; 依赖声明只放行 common+agents". `agents/` (HSP) is also reachable by skill but tools doing RDB queries via `DatabaseHelper` are already in `common/` (`NoteQueryTools.ets:13`); putting the registry anywhere else creates two surfaces.
- **Construction site**: `EntryAbility.onCreate` calls `ToolCatalog.createReadOnlyRegistry()` once and caches it (similar to `DatabaseHelper.init`). `AgentChatService` receives the registry via constructor injection.
- **Skill wiring**: unchanged — `SkillAbility.ets:27` already uses the same factory. **One registry, two callers** — the unified-surface goal from [ADR-0012 §Consequences](../adr/0012-tool-calling-protocol.md).

| Dimension | Direct Kit/Tool |
|---|---|
| Wrapping cost | 1 line in `EntryAbility.onCreate`; AgentChatService gets 1 new constructor arg |
| LLM integration | (depends on H1) — entry gets `tools: registry.listDefinitions()` for any chat-with-tool use |
| Tool loop wiring | (depends on H1) — same registry usable in `tool_call_reply` node |
| SSE events | (depends on S3/S4) — UI process visibility |
| External exposure | ✅ — same registry serves both `entry` and `skill`, satisfying unified-surface |
| Existing alignment | **Strongest** — extends the existing pattern to entry |
| Type strictness | ✅ — no new types |

**Pros**: closes the long-standing "ToolLoop is infrastructure with no production consumer" finding ([capturegraph-architecture-evolution §10.2 H1](./capturegraph-architecture-evolution-2026-09-16.md)); reuses the exact catalog from `common/`. **Cons**: small blast radius if `ToolCatalog` grows to include write tools later — see §3.4.

**Effort**: **S** (½ PR).

---

### §3.4 P2 — NoteQueryTools write tools ([§10.5 #8](./capturegraph-architecture-evolution-2026-09-16.md))

**Current state**: P1 only ships `note_query` / `note_get` / `review_due_query` (read-only). [ADR-0012 §Chosen 3](../adr/0012-tool-calling-protocol.md) deferred write tools behind the F2 write-path unification gate, now closed per handoff (`NoteDaoAdapter.ets:8-74` already implements `insert / insertWithCommitKey / update / updateWithCommitKey` against `KnowledgeUnitWriteService`, with `expectedVersion` optimistic lock). [Spec 014 §"Out of scope"](../specs/014-tool-calling-protocol.md) explicitly defers write tools.

**Direct Kit/Tool path — recommended (with caveats)**:
- **Tool shapes** (sketch): `note_create({title, content, subject, category, ...})` → `KnowledgeUnitWriteService.create(...)` → returns `{noteId, version, duplicate}`. `note_update({noteId, expectedVersion, ...})` → `service.update(...)` → returns `{version, duplicate}`. `note_delete` is probably **not a tool** — delete-via-LLM is too risky (a hallucination wipes user data); keep it UI-only.
- **Where they live**: in `common/src/main/ets/tools/WriteTools.ets` next to `NoteQueryTools.ets` (new file). The tool body reaches `KnowledgeUnitWriteService` from `entry` — **but** `entry` cannot be imported by `common`. Solution per ADR-0012 §Consequences: register a `WriteToolFacade` interface in `common`, implementation injected from `entry` composition root (`EntryAbility.onCreate` constructs the facade and passes it into `ToolCatalog.createRegistry({writeFacade: ...})`).
- **Validation gate**: all writes go through the same `KnowledgeUnitWriteService` validation already used by `NoteDaoAdapter` (note-id collision check, version conflict, content protocol validation, MM-MD-v1). Tools must NOT bypass this — they call `writeFacade.create(unit, source='tool_loop')` and translate error codes to `ok:false, content:'VERSION_CONFLICT: ...'` etc.
- **Schema ownership**: the existing P1 caveat ([`NoteQueryTools.ets:5-7`](../../common/src/main/ets/tools/NoteQueryTools.ets)) carries over — write tools must use the same shared `KnowledgeUnit` schema constants and not import `entry`'s DAOs.

| Dimension | Direct Kit/Tool |
|---|---|
| Wrapping cost | New `WriteToolFacade` interface (≈ 30 LOC) + new `WriteTools.ets` (≈ 200 LOC) + injection wiring in `EntryAbility` |
| LLM integration | Trivial — same 4 件套 |
| Tool loop wiring | Same as P1 — register in `ToolCatalog.createWritableRegistry` (new factory) |
| SSE events | Same as P1 |
| External exposure | ✅ — same unified surface |
| Existing alignment | **Strongest** — extends the pattern; ties into existing `KnowledgeUnitWriteService` |
| Type strictness | ✅ — same shape as P1 |

**Pros**: closes ADR-0012's deferred write-tools slice; reuses the existing `KnowledgeUnitWriteService` validation gate (no bypass risk); one unified tool surface. **Cons**: introduces a `WriteToolFacade` interface (extra seam); adds an LLM-initiated write path — must not become a delete-by-hallucination surface.

**Effort**: **L** (2 PRs): (a) facade + write tool bodies; (b) EntryAbility wiring + tests + safety evaluation (which tools to expose, which to keep UI-only).

---

## §4 ToolLoop ↔ ConversationWorkflow integration design

Concrete sketch for items H1 + S3/S4 + S5 combined.

### §4.1 Composition root wiring (entry side)

```ts
// EntryAbility.onCreate (new): 1 line
private toolRegistry: ToolRegistry = ToolCatalog.createReadOnlyRegistry();
// pass to AgentChatService constructor
```

[`SkillAbility.ets:27`](../../skill/src/main/ets/skillability/SkillAbility.ets) shows the exact factory call already in production — same code, different composition root.

### §4.2 `ReplyContext` + `ReplyService` extension

[`ReplyService.ets:53-66`](../../entry/src/main/ets/services/ReplyService.ets) and [`ReplyService.ets:68-146`](../../entry/src/main/ets/services/ReplyService.ets) both build an `LlmCallRequest` (or via `LlmGuard.callJsonWithRetry`) — add `tools?` field. `IntentClassifier.buildReplyMessages` ([`IntentClassifier.ets:14`](../../entry/src/main/ets/services/IntentClassifier.ets)) does NOT need changes — system prompt stays the same; tool definitions ride alongside the messages.

### §4.3 Workflow node insertion

Current `ConversationWorkflow` 9 nodes + 6 conditional edges ([`ConversationWorkflow.ets:125-233`](../../entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets)):

| Step | file:line | Trigger / behavior |
|---|---|---|
| `START → image_reply \| regenerate_reply \| classify_intent` | `:206-214` | input kind decides |
| `classify_intent → note_reply \| load_reply_context` | `:215-220` | intent === 'note_generation' decides |
| `load_reply_context → save_reply_input` | `:221` | plain |
| `save_reply_input → stream_reply \| complete_reply` | `:222-227` | responseMode decides |

**Recommended addition** (when H1 lands):

| Step | file:line (proposed) | Behavior |
|---|---|---|
| **NEW** `tool_call_reply` | (after `classify_intent`, conditional) | When intent is `'chat_with_tools'` (a new `TextIntent` variant) → run `ToolLoop.run(messages, this.toolRegistry)`; feed back via sink |
| `stream_reply` / `complete_reply` | `:152-168` | Add `request.tools = this.toolRegistry.listDefinitions()` so the LLM sees tools even on single-shot chat |

**Where does the tool loop branch activate?** In two places: ① when the user explicitly opts into tool-using chat (new `TextIntent`); ② when the existing chat decides tools are useful (currently `ReplyService` always sends no-tools — adding `tools` doesn't force the LLM to call them; `tool_choice` stays default-`auto`).

### §4.4 handleCompleteReply vs handleStreamReply integration

- **`handleCompleteReply`** ([`ConversationWorkflow.ets:283-312`](../../entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets)): passes `replyContext` to `replyService.complete()`. Add `tools` to the request. The complete path can return `LlmCallResult.toolCalls` non-empty (after tool loop finished in JSON). On non-empty: loop returns the final text — caller doesn't see tool events (only the result). **No new node needed**.
- **`handleStreamReply`** ([`ConversationWorkflow.ets:318-372`](../../entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets)): passes `replyContext` to `replyService.stream()` + a sink callback `(event) => this.cbs.appendAiMsg(msgId, event)`. The sink must handle the 4 event types (`LlmTypes.ets:129`); for tool-loop chat, the sink must also forward `tool_call` / `tool_result` events to the UI (new step type on UI). **New node `tool_call_reply` recommended** because the loop runs longer than a single SSE stream and the user-visible state is multi-step.

### §4.5 New node sketch (`tool_call_reply`)

```ts
// Proposed ConversationWorkflow.ets
graph.addNode('tool_call_reply', async (input: ConversationState): Promise<ConversationState> => {
  const messages: ChatMessage[] = /* build from memoryContext + history + userContent */;
  const result: LlmCallResult = await new ToolLoop(this.llm).run(messages, this.toolRegistry, {
    maxSteps: 4,
    sink: (event: StreamEvent): void => {
      this.cbs.appendAiMsg(input.msgId, event);   // or new cbs.toolEvent(...)
    },
  });
  await this.safeSaveAssistantMessage(input.sessionId, result.text ?? '');
  return this.copyState(input, 'tool_call_reply');
});
```

Adds 1 conditional edge off `classify_intent`:
```
classify_intent → (intent === 'chat_with_tools' ? tool_call_reply : load_reply_context)
```

**Effort estimate**: S for the new node if `tool_choice:'auto'` and `tools:[defs]` are wired; M if incremental SSE argument reassembly is also needed (S3/S4).

---

## §5 When direct Kit/Tool is the right call — decision checklist

Use this checklist before adding a new tool. Default answer for everything that says "LLM / user loop" is **Direct Kit/Tool**:

| If the tool… | Packaging | Why |
|---|---|---|
| Is called by the LLM via inline `tool_calls` decision (ReAct) | **Direct Kit/Tool** | This is what `AgentTool` is for. |
| Sits in the app's main user loop (chat reply, note generation draft, regenerate) | **Direct Kit/Tool** (via `ToolLoop` + `ConversationWorkflow` or `KnowledgeModel` extension) | LLM may want to call it inline; already in `common/`; no second surface. |
| Is synchronous to the Capture pipeline (e.g. OCR) | **MCP-style** (`agents/src/main/ets/mcp/tools/`) | Pipeline-internal, no LLM decision — `class OcrTool` with `recognize(uri)` direct. ADR-0010. |
| Needs a stateful multi-step procedure | **Direct Kit/Tool** (with `execute` returning a Promise) | `execute(args)` is already async; pipeline composition stays inside the tool body. |
| Will be exposed to the **external 小艺 platform** (MCP server) | **MCP server wrapping the same AgentTool** | Both surfaces come from one tool body — see [agent-toolkit-and-skill-dispatch §4.2](./agent-toolkit-and-skill-dispatch-2026-09-06.md) "把 ToolRegistry 包成 MCP Server 即可上架". |
| Is invoked by `skill/` intent action (search_note, recommend_review, etc.) | **Direct Kit/Tool** (today) | `SkillAbility.ets:27` already in this mode. |
| Is invoked by `Capture`/`Generation` workflow as a pipeline node (no LLM decision) | **Either, but lean MCP** if the tool is agent-internal | Pipeline-internal — no need for `parameters` JSON schema or `tool_calls` wire shape. |

---

## §6 Pros / cons summary

| Dimension | MCP path (`agents/src/main/ets/mcp/tools/OcrTool.ets`) | Direct Kit/Tool path (`common/src/main/ets/tools/`) |
|---|---|---|
| **Wrapping cost** | 0 — just `class OcrTool` with public methods (`OcrTool.ets:52-109`). No registration, no parameters schema, no execute contract. | M — implement `AgentTool` 4 件套 (name, description, parameters schema, execute), register into `ToolRegistry` via `ToolCatalog`. ~30 LOC + JSON Schema. |
| **LLM integration** | ❌ LLM cannot call it. Caller invokes `new OcrTool().recognize(uri)` synchronously (`TypeClassifier.ets:140, 146`). | ✅ LLM calls inline via `tools=[defs], tool_choice='auto'` on the request body (`LlmTypes.ets:32-33, 213-214`). |
| **Tool loop wiring** | N/A — not in the loop. | ✅ `ToolLoop.run` + `ToolCallingWorkflow` ReAct loop (`ToolCallingWorkflow.ets:22-68`) handles iteration, max-steps, error recovery. |
| **SSE events** | N/A | ❌ **Currently gap** — `StreamEvent` types defined (`LlmTypes.ets:129, 141-156`) but not emitted from SSE parse path (`LlmClient.ets:497-522`). Item S3/S4. |
| **External exposure (小艺)** | ✅ MCP-server wrapping is the canonical 上架 path ([agent-toolkit-and-skill-dispatch §4.2](./agent-toolkit-and-skill-dispatch-2026-09-06.md)) | ✅ Same — wrap `ToolRegistry` as MCP server. Both paths converge. |
| **Skill 入口** | ❌ skill can't reach `agents/` directly only via dispatcher; but OcrTool is in agents which skill can import. Still, the unified registry pattern is in common. | ✅ `skill/oh-package.json5` depends on `common` (`SkillAbility.ets:2` imports `ToolCatalog`, `ToolRegistry` from `common`). |
| **Existing alignment** | 1 tool today (`OcrTool`); pipeline-internal. | 3 tools today (`NoteQueryTools`); one production wiring site (`SkillAbility.ets:27`). Spec 014 §4 already directs new read-only tools here. |
| **Type strictness (ArkTS)** | ✅ Plain class — no JSON Schema to author. | ✅ JSON Schema via `Record<string, Object>` bracket assignment (`NoteQueryTools.ets:35-47`) — ArkTS-strict-compatible. |
| **Unified surface** (one tool, two callers: app + skill) | ❌ Each surface rebuilds. | ✅ `ToolCatalog.createReadOnlyRegistry()` is the single factory; both `EntryAbility` and `SkillAbility` would call it. |
| **Schema source-of-truth risk** | Low — `OcrTool` doesn't touch RDB. | Medium — `knowledge_unit` columns declared by entry's `NoteDao`, queried by common (`NoteQueryTools.ets:5-7` caveat). [Spec 014 §4](../specs/014-tool-calling-protocol.md) + [capturegraph-architecture-evolution §10.1 #9](./capturegraph-architecture-evolution-2026-09-16.md) "动态做". |
| **Discovery cost** (LLM knows it exists) | ❌ LLM has no view. | ✅ `registry.listDefinitions()` flows into `tools` field automatically. |

---

## §7 Recommendation for items #5–#8

| # | Item | Recommendation | Key reason (citation) |
|---|---|---|---|
| **#5** | **ToolLoop 接 ConversationWorkflow** (H1) | **Direct Kit/Tool** — Hybrid with **single new node** (`tool_call_reply`) | `common/src/main/ets/tools/ToolLoop.ets:14-24` is already the spec-stable entry; `ToolCallingWorkflow.ets:11-68` ReAct loop exists; `LlmCallRequest.tools` field already on wire (`LlmTypes.ets:213`). Single injection at `EntryAbility.onCreate`; reply path gains optional `tools`; new node only for explicit tool-loop chat. Aligns with [ADR-0012 §Consequences](../adr/0012-tool-calling-protocol.md) "single tool surface serving two callers" + [spec 014 §"Out of scope" — inline already, no scope-creep]. |
| **#6** | **SSE tool_call/tool_result emit + ToolLoop event output** (S3/S4) | **Direct Kit/Tool** — required to land #5 with UI parity | `StreamToolCallEvent` / `StreamToolResultEvent` types already defined (`LlmTypes.ets:141-156`) — emit just not wired. `parseStreamEventsFromSseData` extension + `ToolLoopOptions.sink?: (event: StreamEvent) => void` are pure additions; no new tool surface. No MCP alternative exists (OcrTool is not in the chat path). |
| **#7** | **P1 tools in entry/agents injection** (S5) | **Direct Kit/Tool** — same factory, two composition roots | `ToolCatalog.createReadOnlyRegistry()` already exists (`ToolCatalog.ets:19`); `common/src/main/ets/Index.ets:212-219` already exports the types; skill-side `SkillAbility.ets:27` is the reference wiring. Closing [capturegraph-architecture-evolution §10.2 S5](./capturegraph-architecture-evolution-2026-09-16.md) is a 1-line composition-root change. MCP path would create a second surface in `agents/` — violates ADR-0012 §Consequences "unified surface". |
| **#8** | **NoteQueryTools write tools** (P2) | **Direct Kit/Tool** — `WriteToolFacade` injection from `common/` | Closes [ADR-0012 §Chosen 3](../adr/0012-tool-calling-protocol.md) deferred write-tools slice. `KnowledgeUnitWriteService` validation gate already exists (`NoteDaoAdapter.ets:8-74`); new tools call the same gate. MCP path can't host the gate — it's an entry-side service; MCP tools sit in `agents/` and would need a parallel write path (forbidden by unified-write gate per handoff). |

**Net recommendation**: all 4 items follow the **Direct Kit/Tool path**. MCP path remains correct for **pipeline-internal tools** (OCR pattern, captured by `OcrTool` ADR-0010). Future hybrid: a tool body lives in `common/` (AgentTool 4 件套); an `MCP server adapter` (ADR-0010 开放注记) wraps it for 小艺 上架. One tool body, two surfaces — exactly what [agent-toolkit-and-skill-dispatch §4.2](./agent-toolkit-and-skill-dispatch-2026-09-06.md) prescribes.

---

## §8 Source citations

All citations are `relative/path/file.ets:LINE` (no absolute paths). Every file cited has been opened and verified on 2026-09-16.

### Tool-side files (production)

- `common/src/main/ets/tools/ToolRegistry.ets:1-77` — ToolRegistry + AgentTool contract + ToolResult
- `common/src/main/ets/tools/ToolCatalog.ets:1-27` — factory + skill-only caller today
- `common/src/main/ets/tools/NoteQueryTools.ets:1-253` — 3 readonly tools reference impl
- `common/src/main/ets/tools/ToolLoop.ets:1-25` — 25-LOC shell, delegates to ToolCallingWorkflow
- `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets:1-69` — ReAct loop, DEFAULT_MAX_STEPS=4
- `common/src/main/ets/workflow/tool-calling/ToolCallingState.ets:1-19` — state + ToolLoopOptions
- `common/src/main/ets/workflow/tool-calling/nodes/CallModelNode.ets:1-45` — tools + tool_choice='auto'
- `common/src/main/ets/workflow/tool-calling/nodes/ExecuteToolsNode.ets:1-51` — registry.execute + message pushback
- `common/src/main/ets/llm/LlmTypes.ets:1-226` — wire types + 4 StreamEventType values
- `common/src/main/ets/Index.ets:212-219` — public exports (ToolRegistry/ToolCatalog/ToolLoop + types)

### Tool-side files (consumers + contrast)

- `skill/src/main/ets/skillability/SkillAbility.ets:1-48` — only production registry consumer (`ToolCatalog.createReadOnlyRegistry()` at `:27`)
- `skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets:1-86` — direct `registry.execute('note_query', argsJson)` at `:38`
- `agents/src/main/ets/mcp/tools/OcrTool.ets:1-427` — MCP-style contrast; `class OcrTool` at `:52`; no AgentTool 4 件套
- `agents/src/main/ets/agents/TypeClassifier.ets:136-152` — OcrTool caller (`new OcrTool().recognize(...)` at `:141, 147`)
- `agents/src/main/ets/agents/PromptBuilder.ets:5` — comment-only ToolLoop reference (no production import)
- `agents/src/main/ets/agents/KnowledgeModel.ets:7` — comment-only ToolLoop reference (no production import)
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:1-665` — import list at `:1-23` (no ToolRegistry/ToolCatalog/ToolLoop); `handleCompleteReply:283-312`; `handleStreamReply:318-372`
- `entry/src/main/ets/workflows/conversation/ConversationState.ets:1-60` — ConversationStep + ConversationState 9 fields
- `entry/src/main/ets/services/ReplyService.ets:1-227` — `complete:49-66` + `stream:68-146` (no tools field today)
- `entry/src/main/ets/services/IntentClassifier.ets:14` — `TextIntent = 'note_generation' | 'chat'`
- `entry/src/main/ets/adapters/NoteDaoAdapter.ets:1-75` — 4-method DAO adapter for write-path unification
- `entry/src/main/ets/database/NoteDao.ets` (cited) — schema source-of-truth per `NoteQueryTools.ets:5-7`

### Documentation

- `docs/adr/0010-mcp-tools-semantics.md` — `mcp/` MCP semantic vs `tools/` CRUD taxonomy (29 lines)
- `docs/adr/0012-tool-calling-protocol.md` — OpenAI-compatible protocol; ToolRegistry in `common/`; read-only first (32 lines)
- `docs/specs/014-tool-calling-protocol.md` — full ToolRegistry / ToolLoop / NoteQueryTools spec (139 lines)
- `docs/specs/018-agent-workflow-architecture.md` — 4 workflow shared kernel; spec 018 §3 ToolLoop = stable entry; §4 conversation rules (153 lines)
- `docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md` — skill HSP dependency rule (common+agents only, NOT entry) §5.1; MCP 上架 §4.2
- `docs/research/langgraph-mapping-verification-2026-09-06.md` — API 24 vs API 26 boundary (A2A / AgentExtensionAbility at 26, not 24)
- `docs/research/capturegraph-architecture-evolution-2026-09-16.md` — drift §10.2 H1/H2/S3/S4/S5; user decisions §10.5 #5-#8; packaging research hook §10.6
- `docs/legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md` — prior tool layer + patterns analysis (874 lines)
- `AGENTS.md` / `CONTEXT.md` — repo-wide conventions + vocabulary

### Verification log (2026-09-16)

| Check | Method | Result |
|---|---|---|
| ToolRegistry / ToolCatalog / ToolLoop present in `common/` | `Get-ChildItem` | ✅ confirmed |
| ToolCallingState / ToolCallingWorkflow / CallModelNode / ExecuteToolsNode present | `Test-Path` | ✅ all True |
| `entry/src/main/ets` references to ToolRegistry/ToolCatalog/ToolLoop | `grep` | **0 matches** |
| `agents/src/main/ets` references | `grep` | 2 matches, both comments |
| `LlmTypes.ets:129` 4 StreamEventType | `read` | ✅ `'thinking'\|'text'\|'tool_call'\|'tool_result'` |
| `ToolRegistry.ets:25` name regex | `read` | ✅ `^[a-z][a-z0-9_]{0,63}$` |
| `ToolCatalog.ets:19` static factory | `read` | ✅ `static createReadOnlyRegistry()` |
| `SkillAbility.ets:27` production caller | `read` | ✅ `ToolCatalog.createReadOnlyRegistry()` |
| `ConversationWorkflow.ets:1-23` import list (no tool registry) | `read` | ✅ confirmed |
| `ReplyService.ets:68-146` no `tools` field today | `read` | ✅ confirmed |

---

## Appendix A. Items referenced but not directly verified (out of immediate scope)

These would be needed to fully spec the write-tool facade (§3.4) and are noted here for the implementation PR:

- `entry/src/main/ets/database/NoteDao.ets` (schema declarations) — cited by `NoteQueryTools.ets:5-7` but not opened; needed when defining `WriteTools.ets`.
- `entry/src/main/ets/services/KnowledgeUnitWriteService.ets` — facade target for write tool bodies (size + line counts not pulled).
- `common/src/test/LlmToolCalling.test.ets:128,148,164,185` — the test that already calls `new ToolLoop` (per [capturegraph-architecture-evolution §10.2 H1](./capturegraph-architecture-evolution-2026-09-16.md) grep result) — confirms the entry-point exists and has Hypium coverage.

---

## Appendix B. Drift / open items discovered during this research

| # | Drift | Source | Action |
|---|---|---|---|
| D1 | `LlmCallResult.toolCalls` is populated only on JSON path (`CallModelNode.ets:29`); SSE path relies on event sink only. `ReplyService.stream:68-146` does not surface `toolCalls` from sink. | `LlmClient.ets:497-522` + `ReplyService.ets:68-146` | doc — note in §3.2 (S4 dependency) |
| D2 | `LlmCallOptions` does not include `tools` field; `ReplyService.complete` uses `LlmGuard.callJsonWithRetry` which only forwards `LlmGuardJsonOptions` (`LlmGuard.ets`) — no `tools` plumbing on the JSON path used by chat completion. | `LlmTypes.ets:164-173` + `ReplyService.ets:53-66` | code (item H1) — must extend the JSON-completion path |
| D3 | `LlmGuard.callJsonWithRetry` assumes response body has `.answer` JSON field ([`ReplyService.ets:184-203`](../../entry/src/main/ets/services/ReplyService.ets) `validateChatAnswerJson`) — tool-loop chat wants plain text response, not JSON. `ReplyService.complete` cannot host tool-loop chat as-is. | `ReplyService.ets:184-203` | code (item H1) — either bypass `LlmGuard` for tool-loop or define a new `validateText` |
| D4 | `IntentClassifier.TextIntent = 'note_generation' \| 'chat'` ([`IntentClassifier.ets:14`](../../entry/src/main/ets/services/IntentClassifier.ets)) — no `'chat_with_tools'`. Adding tool-loop chat requires intent vocabulary expansion. | `IntentClassifier.ets:14` | code (item H1) — minor type extension |
| D5 | The `soft drift #9` (NoteDao vs NoteQueryTools schema drift) is still dynamic-only ([capturegraph-architecture-evolution §10.1 #9](./capturegraph-architecture-evolution-2026-09-16.md)). Writing tools exacerbates the risk — must add CI AST check before P2 lands. | `NoteQueryTools.ets:5-7` | code — AST guard test (item P2 dependency) |