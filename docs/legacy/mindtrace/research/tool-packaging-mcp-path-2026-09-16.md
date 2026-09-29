# MCP Packaging Path for MindTrace Tools — 2026-09-16

> **Scope**: Should future tool implementations follow the MCP-style pattern of `OcrTool` (`agents/src/main/ets/mcp/tools/`, ADR-0010) or the ToolRegistry/AgentTool pattern (`common/src/main/ets/tools/`, ADR-0012)?
> **Method**: Every claim cites `path:LINE`; one new file, no edits.
> **Audience**: Decisions on items H1 (ToolLoop wiring) / S3-S4 (SSE tool events) / S5 (P1 wiring) / P2 (write tools) — see §7.
> **Anchors**: [ADR-0010](../adr/0010-mcp-tools-semantics.md) (mcp/ semantics), [ADR-0012](../adr/0012-tool-calling-protocol.md) + [spec 014](../specs/014-tool-calling-protocol.md) (ToolRegistry protocol), [CONTEXT.md:110-116](../../CONTEXT.md) (vocabulary), [prior analysis](../legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) (drift inventory).

---

## §1 What is MCP-style packaging?

Two tool populations co-exist in MindTrace today. They are **deliberately different** shapes and live in different directories.

### 1.1 MCP-style (the OcrTool shape)

- **Class with public methods**, not the `AgentTool` 4 件套. `agents/src/main/ets/mcp/tools/OcrTool.ets:52` declares `export class OcrTool { ... }` directly — no `name`, no `description`, no `parameters: Record<string, Object>`, no `execute(args)` signature.
- **Called directly from code**, not through `ToolRegistry.execute`. Today the only caller is `TypeClassifier.extractText` (`agents/src/main/ets/agents/TypeClassifier.ets:140-148`) which does `const tool = new OcrTool(); baseText = await tool.recognize(payload.imageUri)`.
- **Lives under `agents/src/main/ets/mcp/tools/`** — directory semantics = "按 MCP 语义封装的 agent 工具" ([ADR-0010](../adr/0010-mcp-tools-semantics.md):3, [CONTEXT.md:110-113](../../CONTEXT.md)). The `mcp/` name is **taxonomy**, not "we have a running MCP server" (none does).
- **Throws on failure**, not `ToolResult{ok:false, content}`: `OcrTool.ets:101` throws `'OCR failed: ' + result.message` and `:106` throws `'OCR returned empty text'`. This is the synchronous-tool contract — callers handle the throw locally, no LLM "self-recovery" loop.
- **Configurable endpoint, no per-call name argument** — `OcrTool` constructor takes `formulaEndpoint?` (`:55-58`); runtime mode via `OcrConfig` singleton.

### 1.2 ToolRegistry style (the AgentTool shape)

- **4 件套 contract** — `common/src/main/ets/tools/ToolRegistry.ets:17-22` defines `AgentTool { name, description, parameters, execute(args) }`.
- **`ToolResult` instead of throw** — same file `:11-14`: `ToolResult { ok: boolean; content: string }`. `execute()` is **defensive**: unknown name → `ok:false 'unknown tool: ' + name` (`:60`); bad JSON → `ok:false 'invalid tool arguments...'` (`:72`). The defensive shape exists because LLM may hallucinate tool names; a throw would kill the loop.
- **Naming-rule-gated registration** — `ToolRegistry.ets:25-37` enforces `^[a-z][a-z0-9_]{0,63}$` at register time (stricter than OpenAI wire rule).
- **Lives under `common/src/main/ets/tools/`** — `ToolRegistry.ets:1-77`, `ToolCatalog.ets:1-27`, `NoteQueryTools.ets:1-253`. Common because both `agents/` and `skill/` import it ([ADR-0012](../adr/0012-tool-calling-protocol.md):11 — "registry cannot live in entry because skill/ (HSP) cannot import entry (HAP)").
- **Wire-shaped** — `listDefinitions()` (`ToolRegistry.ets:46-54`) emits OpenAI `LlmToolDefinition { type:'function', function:{name,description,parameters} }` ready for `LlmRequestBody.tools`.
- **Production consumer today**: only `SkillAbility.handleWant` (`skill/src/main/ets/skillability/SkillAbility.ets:27`) → `SkillIntentWorkflow.run` → `registry.execute('note_query', ...)` (`SkillIntentWorkflow.ets:38`) — **a non-LLM call**. `ToolLoop.run` has zero production callers (see §3).

### 1.3 The two shapes are not interchangeable

The two shapes serve different call graphs:

| Dimension | MCP (`OcrTool`) | ToolRegistry (`AgentTool`) |
|---|---|---|
| Caller | non-LLM pipeline code | LLM via `tool_calls` JSON, or skill via Want |
| Failure | `throw` (synchronous tool) | `ToolResult{ok:false, content}` (LLM self-recovers) |
| Tool identity | positional / typed args | string `name` + JSON `args` |
| Registry membership | none | `ToolRegistry.register(tool)` |
| Naming-rule | none (TypeScript class) | `^[a-z][a-z0-9_]{0,63}$` at register |
| Module location | `agents/src/main/ets/mcp/tools/` | `common/src/main/ets/tools/` |
| ADR | [0010](../adr/0010-mcp-tools-semantics.md) | [0012](../adr/0012-tool-calling-protocol.md) |
| Production callers today | `TypeClassifier.extractText` (`:140-148`) | `SkillAbility.handleWant` → `SkillIntentWorkflow.execute_search` |

The directory split is **not** "MCP runs a server vs LLM uses ToolRegistry". It is "is the tool *chosen by an LLM* (ToolRegistry) or *invoked as part of a pipeline* (mcp/)". This is what [CONTEXT.md:110-113](../../CONTEXT.md) makes canonical:

> MCP 工具 (mcp/): A tool in `agents/src/main/ets/mcp/tools/` (currently `OcrTool`), built by the team as an MCP-语义 tool. The directory classifies tools by **MCP tool semantics** — not by whether an MCP server is running (none does today). CRUD-style tools (增删查改) belong in `tools/` instead (ADR-0010).

---

## §2 OcrTool as reference impl — extract the pattern

### 2.1 Surface

Full read: `agents/src/main/ets/mcp/tools/OcrTool.ets` (427 LOC). Public surface at `:52-174`:

```ts
// OcrTool.ets:52  — class shape, no AgentTool
export class OcrTool {
  private formulaEndpoint: string;
  constructor(formulaEndpoint?: string) { ... }                                    // :55
  async recognizeBytes(imageBytes: ArrayBuffer, fileName?: string): Promise<OcrRecognitionResult>  // :60
  async recognizeBytesWithEndpoint(imageBytes, endpoint, fileName?, mode?): Promise<OcrRecognitionResult>  // :64
  async recognize(imageUri: string): Promise<string>                               // :98 — throws, returns promptText
  async recognizeImage(imageUri: string): Promise<OcrRecognitionResult>           // :111
}
```

**Return-type split**: `recognize*Image*`/`recognize*Bytes*` return a structured `OcrRecognitionResult { success, formulas, textLines, text, message }` (`:6-12`); `recognize` (the high-level pipeline entry) returns a `string` prompt and **throws** on failure (`:101, 106`). This asymmetry is intentional: the high-level entry is the pipeline seam, the lower-level entries are seam/test surfaces.

### 2.2 Wiring (the only caller)

`agents/src/main/ets/agents/TypeClassifier.ets:136-152`:

```ts
// TypeClassifier.ets:140-148 — synchronous, no AgentTool / ToolRegistry involvement
if (payload.kind === 'image') {
  const tool = new OcrTool();
  baseText = await tool.recognize(payload.imageUri);
  return this.mergeUserText(baseText, payload.userText);
}
if (payload.kind === 'file') {
  if (payload.mimeType.startsWith('image/')) {
    const tool = new OcrTool();
    baseText = await tool.recognize(payload.fileUri);
  }
  return this.mergeUserText(baseText, payload.userText);
}
```

`OcrTool` is **constructed per call** (not a singleton) — no shared state, no LLM involvement, no JSON-Schema payload. The pipeline argument `payload.imageUri` is a typed ArkTS string; no JSON serialize/parse happens.

### 2.3 Why not in ToolRegistry

Three reasons stated in the ADRs/specs:

1. **Taxonomy** ([ADR-0010](../adr/0010-mcp-tools-semantics.md):3,11): `mcp/` is for "按 MCP 语义封装的 agent 工具", `tools/` (in `common/`) is for "增删查改类". OCR is not CRUD; it's a pipeline step.
2. **Tool Registry scope** ([ADR-0012](../adr/0012-tool-calling-protocol.md):20): "`OcrTool` stays where it is (`mcp/`, MCP-semantic) — registering it as an `AgentTool` is a possible follow-up, not part of this decision." And [spec 014](../specs/014-tool-calling-protocol.md):136 (out-of-scope): "OcrTool 注册为 AgentTool(保持 `mcp/` 语义不动, ADR-0010; 可能的后续单独决策)".
3. **Call-graph fit**: OCR is invoked during `capture` *before* LLM involvement ([CaptureGraph capture step](../../CONTEXT.md:56-58)). Wrapping it in `ToolRegistry` would force a tool-call round-trip and JSON Schema definition for a tool that's already a typed ArkTS call site.

### 2.4 What would change if converted to AgentTool

Hypothetical `OcrAgentTool implements AgentTool`:
- New file: `agents/src/main/ets/mcp/tools/OcrAgentTool.ets` (or `common/src/main/ets/tools/OcrAgentTool.ets` if we want it reusable across skill/, but `agents/...mcp/...` is fine).
- New contract: `name='recognize_image'`, `description`, `parameters={type:'object', properties:{imageUri:{type:'string'}}, required:['imageUri']}`, `execute(args)` → `JSON.stringify(OcrRecognitionResult)` + `ok:true`.
- New call site in `TypeClassifier.ets:140,146` (hypothetical): `const result = await registry.execute('recognize_image', JSON.stringify({imageUri: payload.imageUri}));` then `JSON.parse(result.content)` to get `OcrRecognitionResult`.
- New top-level wiring in `ToolCatalog.createReadOnlyRegistry()` (`ToolCatalog.ets:19-26`) — would need to also live in `agents/` since OcrTool is an agents concern.
- **Costs**:
  - +1 JSON serialize + 1 JSON parse per OCR call (cold path; pipeline latency is dominated by OCR HTTP anyway — see `OcrTool.ets:299-300 connectTimeout=5000, readTimeout=300000`).
  - LLM-facing description + schema have to be carefully written so LLM doesn't misuse OCR (image OCR makes no sense in a chat reply context).
  - **Schema drift**: `ToolRegistry.ets:46-54` reads `parameters` straight through; the OCR tool would need to expose a `Record<string, Object>` schema that survives ArkTS strict (compare `NoteQueryTools.ets:55-61` building `parameters` with bracket-assignment).
- **Benefits**:
  - Unified execution path; LLM in chat could (theoretically) request an OCR if it had a stored imageUri.
  - Reusable by skill/ if skill wants to OCR a user-supplied image (today it doesn't).
  - Future "agent workflow with OCR" could compose it.

**Conclusion**: the conversion is **mechanical but low-value** for current product. The real value of `mcp/` is signalling "this is a pipeline tool, not an LLM tool". A forced conversion would erase that signal without unlocking new behaviour.

---

## §3 MCP path for ToolLoop wiring (items H1 / S3-S4 / S5 / P2)

The 4 pending items from the capturegraph-tool-layer §4 drift table (mapped 1-1 to the user-provided #5-#8):

| ID | Item | Drift reference |
|---|---|---|
| **H1** | `ToolLoop` 接 `ConversationWorkflow` (tool loop zero production consumers) | [§4.1 #1-#2](../legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) |
| **S3/S4** | SSE `tool_call`/`tool_result` emit + `ToolLoop` event output | [§4.2 #3-#4](../legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) |
| **S5** | P1 只读工具 in `entry`/`agents` 注入 | [§4.2 #5](../legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) |
| **P2** | `NoteQueryTools` write tools (note insert/update/delete) | [spec 014 §"Out of scope"](../specs/014-tool-calling-protocol.md):134; [ADR-0012 §Chosen 3](../adr/0012-tool-calling-protocol.md) |

### H1 — Should `ToolLoop` wrap MCP-style tools or ToolRegistry tools?

**ToolRegistry tools**, exclusively. Three reasons:

1. **API contract**: `ToolLoop.run(messages, registry, options)` (`ToolLoop.ets:21-24`) takes `ToolRegistry`, not a list of MCP-style classes. `ExecuteToolsNode.run` (`ExecuteToolsNode.ets:24`) calls `this.registry.execute(call.function.name, call.function.arguments)` — that exact string-keyed dispatch is the AgentTool contract.
2. **Tool-calling shape**: LLM emits `tool_calls` JSON (OpenAI wire format, `LlmTypes.ets:39-49`). To turn that into a typed ArkTS call to `OcrTool.recognize(imageUri)` requires either (a) writing an AgentTool wrapper that JSON-parses args and dispatches, or (b) extending LlmCallResult to carry typed ArkTS args. Both are regression vs the registry shape.
3. **MCP-style tools don't fit ReAct**: `OcrTool` throws on failure; the ReAct loop relies on `ok:false` returning content for the LLM to self-recover (`ToolRegistry.ets:57-76` + `LlmToolCalling.test.ets:175-191` "loop_feeds_tool_error_back_and_model_recovers"). An MCP-style throw inside `ExecuteToolsNode` would either bubble up (killing the loop) or need exception-to-content translation (reinventing what `ToolResult` already does).

**Hybrid scenario** (in theory): a future "agent OCR" where the LLM in a chat asks "what does this user-saved image say?" — could be implemented as **`OcrAgentTool implements AgentTool`** wrapping the existing `OcrTool` class (no duplication; OcrTool keeps `mcp/` semantics). The AgentTool wrapper holds a reference to the MCP-style class instance and translates `args:{imageUri:string}` → `tool.recognize(args.imageUri)` → `JSON.stringify(result)`. Cost: ~30 LOC per such wrap. **Keep this option open for after the competition, not now** (spec 014 out-of-scope row).

### S3/S4 — SSE `tool_call`/`tool_result` emit + `ToolLoop` event output

Drift detail:
- `LlmTypes.ets:129` defines `StreamEventType = 'thinking' | 'text' | 'tool_call' | 'tool_result'` — all 4 vocabulary slots exist.
- `LlmClient.parseStreamEventsFromSseData` (`LlmClient.ets:497-522`) currently emits only `thinking` and `text` ([capturegraph-tool-layer §1.7.3](../legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) at lines 423-444).
- `ToolLoop.run` returns only the final `LlmCallResult` (`ToolCallingWorkflow.ets:41-44`); intermediate tool_call/tool_result not exposed to UI.

**Path is independent of MCP vs ToolRegistry** — both shapes use the same `LlmClient` and `ToolLoop` infrastructure:

| Sub-item | Path | Why |
|---|---|---|
| S3 — `LlmClient` stream emits `tool_call`/`tool_result` when delta carries `tool_calls` | JSON path only, SSE path adds delta-tool_calls → `tool_call` event | `LlmClient.ets:506-515` is the only place to change; no MCP/ToolRegistry coupling |
| S4 — `ToolLoop` exposes a `sink?: (event: StreamEvent) => void` | Add `ToolLoopOptions.sink`, `ExecuteToolsNode` emits pre/post events | Same; affects only `ToolCallingWorkflow.ets:22-45` |

These two sub-items belong to **a future extension spec**, not in scope of this packaging decision. The path is **ToolRegistry-side**: events describe `tool_call.name` (the AgentTool name) and `tool_result` (the `ToolResult.content`) — vocabulary that already lives in spec 014 §2 and matches the OpenAI wire shape. **No MCP alternative applies** here — `OcrTool` does not produce tool_calls (it's a synchronous pipeline tool); SSE events are about LLM-produced tool calls flowing back through the loop.

### S5 — P1 只读工具在 `entry`/`agents` 注入

Current state: `ToolCatalog.createReadOnlyRegistry()` is called **only by `SkillAbility.handleWant`** (`SkillAbility.ets:27`). `entry/` and `agents/` have no `ToolRegistry` import. This is the §4.2 #5 drift — "应用方 wiring" missing.

**Path stays ToolRegistry**. Three options:

1. **Inject at composition root** — `EntryAbility.onCreate` builds `const registry = ToolCatalog.createReadOnlyRegistry();` and caches it for `ConversationWorkflow.handleCompleteReply` to pick up. Matches the `DatabaseHelper` init style.
2. **Inject per-call** — every chat reply call constructs its own registry; matches `TypeClassifier` constructing `new OcrTool()` per call (`TypeClassifier.ets:140, 146`). Lower blast radius but no shared state.
3. **Move `OcrTool` into the same registry** — not recommended (see §2.4); OCR is not LLM-mediated.

**Hybrid does not apply** because P1 read-only tools are already ToolRegistry-shaped by design (`NoteQueryTools.ets:50-247`). The MCP path would mean giving them a class with public methods and skipping `ToolRegistry` entirely — that's a regression, not a packaging decision.

### P2 — Write tools (Note insert/update/delete)

Deferred by ADR ([spec 014 §Out-of-scope](../specs/014-tool-calling-protocol.md):134; [ADR-0012 §Chosen 3](../adr/0012-tool-calling-protocol.md)): "写类工具(Note insert/update/delete)— 与 F2 写库路径统一绑定, 赛后另立 spec".

**Path**: **ToolRegistry, not MCP**. Four reasons:

1. **LLM gate** — write tools **must** be LLM-chosen (user asks "save this as a note" → LLM decides when). MCP-style tools are pipeline-invoked, not LLM-invoked.
2. **Validation gate unification** ([ADR-0012](../adr/0012-tool-calling-protocol.md):13): "three AI-triggered write paths already exist with inconsistent gating (inventory F2); adding LLM-initiated writes before that unification would compound the risk. Write tools are a post-competition phase." A unified gate has to be a single `ToolRegistry.execute()` path so the gate logic lives at one boundary.
3. **Schema-ownership** ([ADR-0012](../adr/0012-tool-calling-protocol.md):19): "`knowledge_unit` etc. are currently declared by `entry` DAOs — P1 tools must either lift shared schema constants into `common` or cite NoteDao as the schema source-of-truth." Write tools amplify this — they need to share column names with both `entry/NoteDao` and `common/ToolRegistry`. The MCP path does not solve this; the ToolRegistry path puts the schema discussion at the registry boundary where it already exists.
4. **Audit/observability** — `ToolRegistry.execute` already routes through `LlmError('TOOL_REGISTRY_ERROR', 'TOOL_LOOP_MAX_STEPS')` and `ToolResult{ok:false, content}`. Adding write tools to a separate MCP-style surface would require a parallel observability story.

**Hybrid (theoretical)**: a write tool that's both LLM-callable **and** directly invokable from pipeline code (e.g. `KnowledgeUnit.persist` writes during `CaptureGraph` persist node AND a future LLM-initiated "re-write this note"). Implementation: ToolRegistry AgentTool with **explicit caller discrimination** (only callable from `ConversationWorkflow`, not from arbitrary LLM loops). Cost: ACL on `ToolRegistry` itself — adds complexity without solving the F2 unification problem.

---

## §4 MCP server-side architecture (future)

> **Status today**: no MCP server runs. ADR-0010:18 explicitly leaves this open: "是否/何时以 MCP 协议对外暴露(如 JSON-RPC server), 由该工具的维护队员决定."

### 4.1 What an MCP server would look like

Per [MCP spec 2026-07-28](https://modelcontextprotocol.io/specification/latest) (verified 2026-09-16):
- Transport: **JSON-RPC 2.0** over stdio / streamable HTTP (per [research ⑤ §2.4 #4](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md):52 — "MCP 规范(2026-07-28 版) ... JSON-RPC 2.0, 语言无关").
- Server features: `tools/list`, `tools/call`, `resources/*`, `prompts/*`. We only need `tools/list` + `tools/call`.
- Hosting: per [research ⑤ §4.2](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md):67 — "app 以 MCP Server 形式向小艺注册 tools" — the 小艺开放平台 MCP 上架 flow.

### 4.2 Feasibility in ArkTS

**Transport**: feasible. `@kit.NetworkKit` `http` module is already used by `OcrTool` (`OcrTool.ets:282, 337` — `http.createHttp()` with `requestInStream` not used here but available). JSON-RPC 2.0 = JSON envelopes; no exotic protocol. A minimal MCP server is ~200 LOC: HTTP listener + 3-5 methods (`initialize`/`tools/list`/`tools/call`/`ping`).

**Schema**: feasible. Tool definitions (`LlmToolDefinition`) already in spec 014 (`LlmTypes.ets:175-185`) are wire-compatible with MCP `Tool` schema (both are JSON Schema objects in `parameters`).

**Caveat — no official HarmonyOS MCP server SDK** ([research ⑤ §2.4 #4](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md):52 — "MCP 规范 ... 语言无关 — 官方 TS SDK 不可移植, 按 spec 自实现最小 client 与项目 OcrTool 思路一致"). Self-implement per spec; borrow patterns from `@modelcontextprotocol/sdk` TypeScript reference.

### 4.3 Comparison to current `SkillAbility` Want-based interface

| Dimension | `SkillAbility` (today) | MCP server (future) |
|---|---|---|
| Caller | 小艺 platform via Want | any MCP-compatible host |
| Transport | `Want` + `AbilityResult` ([`SkillAbility.ets:40-46`](../skill/src/main/ets/skillability/SkillAbility.ets:40)) | JSON-RPC 2.0 over HTTP (or stdio) |
| Tool identity | `want.action` mapped by `IntentRouter.fromWant` | `tool.name` in `tools/call` |
| Surface | 7 declared actions in `module.json5` | flat list from `ToolRegistry.listDefinitions()` |
| Protocol spec | OpenHarmony-specific | Industry-standard MCP |
| Production consumer | Yes (SearchNote) | None (none today) |

**They are not the same path**: Want-based is HarmonyOS-specific, MCP-server is industry-standard. A future MCP server **complements** `SkillAbility`, doesn't replace it.

### 4.4 Open question — do we even need a server?

Re-reading ADR-0010:18: the team explicitly punted on this decision. Today `OcrTool` is "按 MCP 语义封装" but not "exposed as MCP server". The **packaging path** (this document's question) is **orthogonal** to whether we eventually expose a server — MCP-style class shape is the **directory signal**, not a server contract.

If/when a server lands:
- `common/src/main/ets/tools/ToolRegistry` becomes the single source for `tools/list` and `tools/call` (no duplication).
- `agents/src/main/ets/mcp/tools/OcrTool` (and any future MCP-style class) needs a thin shim to expose its public methods as `tools/list`-shaped metadata if we want it on the server. Or — keep it out of server scope and only expose `ToolRegistry` tools.
- The "directory split" (`mcp/` vs `tools/`) becomes a server-side **filter**: only `tools/` is exposed via MCP; `mcp/` stays internal pipeline tool.

---

## §5 When MCP path is the right call — decision checklist

Apply these in order. First matching rule wins.

| # | Question | If yes → | If no → |
|---|---|---|---|
| 1 | Is the tool called from non-LLM pipeline code (synchronous call graph)? | **MCP path** (`mcp/tools/`) | continue |
| 2 | Is the tool exposed to external system (e.g. 小艺 MCP server)? | **MCP server path** (separate from §1) | continue |
| 3 | Is the tool invoked by LLM via `tool_calls` JSON? | **ToolRegistry path** (`common/src/main/ets/tools/`) | continue |
| 4 | Is the tool called by `SkillAbility.handleWant` (no LLM, Want-driven)? | **ToolRegistry path** (reuses the shared tool surface, see ADR-0011) | continue |
| 5 | Is the tool stateful / multi-step / streaming? | **ToolRegistry path** (ToolLoop will wrap it; `ToolResult{ok,content}` handles error) | continue |
| 6 | Is the tool a CRUD (增删查改) operation? | **ToolRegistry path** ([ADR-0010](../adr/0010-mcp-tools-semantics.md):11) | continue |
| 7 | (Fallback) | **Default to MCP path** if no other rule matches, then evaluate | |

The dominant axis is **"who calls this tool, and how?"** — not "is MCP exposed as a server?". MCP-style is for *pipeline tools*, ToolRegistry-style is for *LLM/skills tools*.

---

## §6 Pros / cons summary

| Dimension | MCP path (`mcp/tools/`, `class X` with public methods) | ToolRegistry path (`common/src/main/ets/tools/`, `AgentTool` 4 件套) |
|---|---|---|
| **Wrapping cost** | 0 — just write the class | Per tool: schema (`parameters: Record<string, Object>`) + `execute(args)` impl + `ToolResult` shape |
| **LLM integration** | None directly — LLM never sees MCP-style tools | First-class — `tools: [...]` in `LlmRequestBody`, parsed `tool_calls` loop |
| **Tool loop wiring (H1)** | Not applicable — MCP-style tools aren't `tool_calls` | Native fit — `ToolLoop.run` → `ExecuteToolsNode` → `registry.execute` |
| **SSE events (S3/S4)** | N/A (no `tool_calls`) | Natural — `tool_call`/`tool_result` events map to `registry.execute` invocations |
| **External exposure (小艺 MCP server)** | Requires thin shim to map `method` → typed call | Direct — `listDefinitions()` already wire-shaped |
| **Existing alignment** | 1 prod tool (`OcrTool`), `TypeClassifier.ets:140-148` is the pattern | 3 prod tools (`NoteQueryTools.ets:50-247`), `SkillAbility.ets:27` is the consumer |
| **Type strictness** | High — typed ArkTS args, no JSON | Medium — `Record<string, Object>` schema (LlmTypes.ets:176); validation gap |
| **Failure mode** | `throw` (caller handles) | `ToolResult{ok:false, content}` (LLM self-recovers, see `ToolRegistry.ets:57-76`) |
| **Naming rule** | None (TypeScript identifier) | `^[a-z][a-z0-9_]{0,63}$` at register (`ToolRegistry.ets:25-37`) |
| **Discoverability** | Class symbol only | Listed via `ToolRegistry.listDefinitions()` |
| **Module location** | `agents/src/main/ets/mcp/tools/` | `common/src/main/ets/tools/` (reachable by `skill/` HSP) |
| **ADR basis** | [ADR-0010](../adr/0010-mcp-tools-semantics.md) | [ADR-0012](../adr/0012-tool-calling-protocol.md), [spec 014](../specs/014-tool-calling-protocol.md) |
| **Open spec risk** | Low — ADR-0010 settled | Medium — write tools gated on F2 ([ADR-0012](../adr/0012-tool-calling-protocol.md):13) |

---

## §7 Recommendation for items #5-#8

| # | Item | Recommendation | Key reason | Evidence |
|---|---|---|---|---|
| **H1** | ToolLoop 接 ConversationWorkflow | **Direct Tool (ToolRegistry)** | `ToolLoop.run` takes `ToolRegistry`; LLM emits `tool_calls` JSON; MCP-style throws break ReAct self-recovery | `ToolLoop.ets:21-24`, `ExecuteToolsNode.ets:24`, `ToolRegistry.ets:57-76` |
| **S3/S4** | SSE `tool_call`/`tool_result` emit + ToolLoop event output | **Direct Tool (LlmClient stream extension)** | Events describe AgentTool names + `ToolResult.content` — ToolRegistry vocabulary; MCP-style doesn't produce `tool_calls` | `LlmTypes.ets:129` (StreamEvent 4-type), `LlmClient.ets:497-522`, `ToolCallingWorkflow.ets:22-45` |
| **S5** | P1 只读工具 in entry/agents 注入 | **Direct Tool (ToolRegistry via `ToolCatalog`)** | P1 tools are already ToolRegistry-shaped; injecting them via `EntryAbility` composition root is the natural fix; OCR stays MCP (no change) | `ToolCatalog.ets:19-26`, `NoteQueryTools.ets:50-247`, drift §4.2 #5 |
| **P2** | NoteQueryTools write tools (note insert/update/delete) | **Direct Tool (ToolRegistry)** | LLM-mediated writes need validation-gate unification (F2) — putting writes on a separate MCP-style surface would fork the gate; spec 014 explicitly defers | [spec 014 §Out-of-scope:134](../specs/014-tool-calling-protocol.md), [ADR-0012 §Chosen 3](../adr/0012-tool-calling-protocol.md) |

**Net recommendation**: all 4 items use the **Direct Tool (ToolRegistry) path**. The MCP path is the right call for `OcrTool`-shaped pipeline tools (image→text, future audio→text, etc.); none of the 4 items are pipeline tools. **OcrTool should not be re-shaped**; if a future LLM-driven chat needs OCR, the recommended path is a thin `OcrAgentTool implements AgentTool` wrapper (~30 LOC) that holds an `OcrTool` instance and translates `args:{imageUri}` → `tool.recognize()` → `JSON.stringify(result)`.

---

## §8 Source citations count

### 8.1 Primary sources (read in full this session)

| # | Path | Lines read | Purpose |
|---|---|---|---|
| 1 | `docs/adr/0010-mcp-tools-semantics.md` | 1-29 | MCP semantics definition |
| 2 | `docs/adr/0011-skill-xiaoyi-reservation.md` | 1-32 | skill/ HSP topology |
| 3 | `docs/adr/0012-tool-calling-protocol.md` | 1-32 | ToolRegistry ADR |
| 4 | `docs/specs/014-tool-calling-protocol.md` | 1-139 | Protocol spec (out-of-scope list) |
| 5 | `docs/specs/018-agent-workflow-architecture.md` | 1-153 | 4-workflow architecture |
| 6 | `agents/src/main/ets/mcp/tools/OcrTool.ets` | 1-427 | MCP-style reference impl |
| 7 | `agents/src/main/ets/agents/TypeClassifier.ets` | 130-299 (incl. lines 140-148 wiring) | OcrTool caller |
| 8 | `common/src/main/ets/tools/ToolRegistry.ets` | 1-77 | ToolRegistry impl |
| 9 | `common/src/main/ets/tools/ToolCatalog.ets` | 1-27 | Factory |
| 10 | `common/src/main/ets/tools/NoteQueryTools.ets` | 1-253 | P1 tools |
| 11 | `skill/src/main/ets/skillability/SkillAbility.ets` | 1-48 | ToolCatalog consumer |
| 12 | `skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets` | 1-86 | `registry.execute('note_query')` site |
| 13 | `docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md` | 1-133 | research ⑤ (skill/MCP research) |
| 14 | `docs/research/langgraph-mapping-verification-2026-09-06.md` | 1-70 | Kit API 24/26 boundary |
| 15 | `docs/legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md` | 1-874 (full) | prior analysis |
| 16 | `docs/legacy/mindtrace/research/capturegraph-processing-chain-2026-09-16.md` | §10 drift table (lines 374-440) | drift items reference |
| 17 | `CONTEXT.md` | 1-205 | vocabulary (MCP tool term at 110-113) |
| 18 | `https://modelcontextprotocol.io/specification/latest` | full text (webfetch 2026-09-16) | MCP spec JSON-RPC 2.0 confirmation |

### 8.2 Citation count summary

- **`path:LINE` citations in this report**: ~95 (counted: every claim in §1-§7 cites at least one)
- **ADR references**: 3 (0010, 0011, 0012)
- **Spec references**: 2 (014, 018)
- **Research references**: 3 (agent-toolkit, langgraph-mapping, legacy capturegraph-tool-layer)
- **CONTEXT.md references**: 1 (vocabulary §110-113, §56-58)
- **Webfetch references**: 1 (MCP spec)
- **Total unique references**: **~105 citations** across 18 sources

### 8.3 Drift found during research

| # | Drift | Where | Status |
|---|---|---|---|
| **A** | User-cited `capturegraph-architecture §10.5 #5-#8` does not map to the 4 items claimed | `capturegraph-processing-chain-2026-09-16.md:374-440` actually enumerates 13 sub-items; §10.5 = `DispatchResult` shape, not the 4-item list | The 4 items H1/S3-S4/S5/P2 are from `capturegraph-tool-layer-and-patterns-2026-09-16.md` §4.1-4.2 (drift #1-#5), not §10.5. **Verified — naming mismatch in user prompt, content is what user described** |
| B | `agents/src/main/ets/TypeClassifier.ets` referenced as `agents/src/main/ets/TypeClassifier.ets` in user prompt | Actual path: `agents/src/main/ets/agents/TypeClassifier.ets` | Path corrected in this report at `TypeClassifier.ets:140-148` |
| C | `agents/src/main/ets/core/Dispatcher.ets` referenced in `capturegraph-processing-chain-2026-09-16.md:470` and `CONTEXT.md:81`; the same path is implied in this report | Verified by capturegraph-processing-chain §10.5 | Consistent |

---

## §9 Cross-references / see also

- [ADR-0010](../adr/0010-mcp-tools-semantics.md) — `mcp/` semantics (canonical)
- [ADR-0011](../adr/0011-skill-xiaoyi-reservation.md) — `skill/` reservation (canonical)
- [ADR-0012](../adr/0012-tool-calling-protocol.md) — ToolRegistry protocol (canonical)
- [spec 014](../specs/014-tool-calling-protocol.md) — Protocol spec (canonical)
- [spec 018](../specs/018-agent-workflow-architecture.md) — 4-workflow architecture (canonical)
- [CONTEXT.md](../../CONTEXT.md) — vocabulary at lines 110-116
- [`capturegraph-tool-layer-and-patterns-2026-09-16.md` §1.9](../legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) — "MCP 工具 (OcrTool) vs ToolRegistry" comparison
- [`capturegraph-tool-layer-and-patterns-2026-09-16.md` §4.1-§4.2](../legacy/mindtrace/research/capturegraph-tool-layer-and-patterns-2026-09-16.md) — drift items H1/S3-S4/S5
- [research ⑤ §2.4 #4](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md) — MCP spec language-agnostic note
- [research ⑤ §4.2](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md) — 小艺开放平台 MCP 上架
- [MCP spec 2026-07-28](https://modelcontextprotocol.io/specification/latest) — JSON-RPC 2.0 transport

---

## §10 Drift observed in source materials (verification report)

Reading every primary source uncovered a few inconsistencies worth recording (in addition to the user-prompt `capturegraph-architecture §10.5` mismatch already noted in §8.3):

| # | Drift | Source claim | Code reality | Where confirmed |
|---|---|---|---|---|
| 1 | User prompt refers to `capturegraph-architecture §10.5 #5-#8` as the source of H1/S3-S4/S5/P2 | §10.5 is "DispatchResult carries optional classification/recognized text" (`capturegraph-processing-chain-2026-09-16.md:394-396`) — unrelated | The 4 items are real drift but live in `capturegraph-tool-layer-and-patterns-2026-09-16.md` §4.1 #1-#2 (H1) + §4.2 #3-#5 (S3-S4/S5); P2 lives in `spec 014` out-of-scope list | `capturegraph-tool-layer-and-patterns-2026-09-16.md:778-787` |
| 2 | User prompt cites `agents/src/main/ets/TypeClassifier.ets:140-148` | Path is `agents/src/main/ets/agents/TypeClassifier.ets:140-148` | Same lines, different prefix | Verified by reading `TypeClassifier.ets` |
| 3 | `OcrTool` described in [research ⑤ §4.2](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md):67 as a future "MCP Server" candidate | ADR-0010:18 explicitly defers the server decision to the maintainer | Today: no MCP server; ADR says "由该工具的维护队员决定" | `docs/adr/0010-mcp-tools-semantics.md:18` |
| 4 | `OcrTool.ets:107` throws on empty text — counted as "throw on failure" | True for `recognize()` (high-level pipeline entry, `:101, 106`); **not** true for `recognizeImage`/ `recognizeBytes` which return `OcrRecognitionResult{success:false}` | Two different failure-handling shapes within the same class | `OcrTool.ets:89-95` vs `:101, 106` |
| 5 | CaptureGraph description in [CONTEXT.md:85](../../CONTEXT.md) says "built per dispatch; no checkpoint / HITL / subgraph by design (ADR-0008)" | Spec 018 §Out-of-scope line 144 says "Checkpoint / Subgraph / HITL / Reducer / parallel fan-out" | Both consistent | — |
| 6 | `TypeClassifier.ets:140, 146` constructs `new OcrTool()` per call (no singleton) | OcrTool class has no shared state, only `formulaEndpoint` field | Construction is idempotent; not a leak, just verbose | `OcrTool.ets:53-58` |
| 7 | `ToolCatalog.ets:19` named `createReadOnlyRegistry` — read-only is intentional | ADR-0012 §Chosen 3: write tools are post-competition | Consistent | — |
| 8 | [research ⑤ §2.4 #4](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md):52 mentions `@langchain/langgraph/web` "全网零鸿蒙案例" | 2026-09-06; MCP server SDK for HarmonyOS not searched at the time | Today's MCP server SDK availability for HarmonyOS: still none found; spec is language-agnostic so self-implement ~200 LOC | [MCP spec 2026-07-28](https://modelcontextprotocol.io/specification/latest) |

**No spec/ADR/code contradictions** found — all "drift" entries are either user-prompt naming mismatches or non-contradictory timing notes.

---

## §11 Self-review checklist

Before considering this research document final:

- [x] Every tool-related file was opened and verified (OcrTool, TypeClassifier 140-148, ToolRegistry, ToolCatalog, NoteQueryTools, SkillAbility, SkillIntentWorkflow)
- [x] ADR-0010 and ADR-0012 fully read
- [x] spec 014 (out-of-scope row 136 explicit) + spec 018 (4-workflow table line 44) fully read
- [x] MCP spec webfetched 2026-09-16 — confirmed JSON-RPC 2.0
- [x] All 4 items H1/S3-S4/S5/P2 mapped to specific drift sources
- [x] Recommendation for each item has at least one `path:LINE` evidence citation
- [x] Pros/cons table covers wrapping cost, LLM integration, tool loop, SSE, external exposure, alignment, type strictness (7 dimensions)
- [x] Decision criteria checklist has 7 rules with first-match-wins ordering
- [x] Drift section captures 8 verification findings including the user-prompt mismatch

---

## §12 Appendix A — Tool interface shape (raw)

For reference. Side-by-side declaration fragments from the canonical implementations.

### A.1 MCP-style (OcrTool)

```ts
// agents/src/main/ets/mcp/tools/OcrTool.ets:52
export class OcrTool {
  private formulaEndpoint: string;
  constructor(formulaEndpoint?: string) {
    this.formulaEndpoint = formulaEndpoint ?? 'http://127.0.0.1:8000/api/v1/formula/recognize';
  }
  async recognizeBytes(imageBytes: ArrayBuffer, fileName: string = 'upload.png'): Promise<OcrRecognitionResult> { ... }   // :60
  async recognizeBytesWithEndpoint(imageBytes: ArrayBuffer, endpoint: string, fileName?: string, mode?: string): Promise<OcrRecognitionResult> { ... }  // :64
  async recognize(imageUri: string): Promise<string> { ... }                                                          // :98 — throws
  async recognizeImage(imageUri: string): Promise<OcrRecognitionResult> { ... }                                       // :111
}

// Caller (agents/src/main/ets/agents/TypeClassifier.ets:140-148)
const tool = new OcrTool();
baseText = await tool.recognize(payload.imageUri);
```

### A.2 ToolRegistry-style (NoteQueryTool)

```ts
// common/src/main/ets/tools/NoteQueryTools.ets:50-61
export class NoteQueryTool implements AgentTool {
  public name: string = 'note_query';
  public description: string = 'Search saved math notes (KnowledgeUnit)...';
  public parameters: Record<string, Object>;
  constructor() {
    const props: Record<string, Object> = {};
    props['subject'] = stringProp('exact subject name, e.g. 数学分析');
    props['review_status'] = stringProp('one of: new, learning, review, graduated, lapsed');
    props['keyword'] = stringProp('keyword matched against title or content');
    this.parameters = objectSchema(props);
  }
  async execute(args: Record<string, Object>): Promise<ToolResult> { ... }
}

// Caller (skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets:38)
const toolResult: ToolResult = await this.registry.execute('note_query', input.request.argsJson);
```

### A.3 Contract obligations (what each shape must provide)

| Obligation | MCP-style | ToolRegistry-style |
|---|---|---|
| Identity | class name | `name` field, regex-gated `^[a-z][a-z0-9_]{0,63}$` |
| Description (LLM-readable) | implicit in class JSDoc | `description` field, free-form but wire-shown |
| Parameter schema | TypeScript types + class shape | `parameters: Record<string, Object>` (JSON Schema object literal) |
| Failure shape | `throw` (or `success:false` for low-level entry) | `ToolResult{ok:false, content: string}` |
| Registration | none | `ToolRegistry.register(tool)` at composition root |
| Discoverability | class symbol / file path | `ToolRegistry.listDefinitions()` returns wire-shaped definitions |

---

## §13 Appendix B — Drift → Recommendation cross-reference

For traceability, mapping each item back to its source drift row + my recommendation + the rejection rationale for the alternative path.

| Item | Source drift row | Recommendation | Alternative considered | Why rejected |
|---|---|---|---|---|
| H1 | `capturegraph-tool-layer-and-patterns-2026-09-16.md:778-779` (§4.1 #1-#2) | Direct Tool (ToolRegistry via `ToolLoop.run`) | Wrap `OcrTool` as `OcrAgentTool` so LLM can inline-OCR | OCR is pipeline-invoked, not LLM-chosen; re-shaping creates ambiguity. If a future LLM needs OCR, write a thin wrapper (~30 LOC) — don't convert `OcrTool` |
| S3 | `capturegraph-tool-layer-and-patterns-2026-09-16.md:785` (§4.2 #3) | Direct Tool (extend `LlmClient.parseStreamEventsFromSseData`) | Emit "tool_call" events from a future MCP-style server | SSE tool_call events describe AgentTool `name` — vocabulary is ToolRegistry; MCP-style tools don't emit `tool_calls` |
| S4 | `capturegraph-tool-layer-and-patterns-2026-09-16.md:786` (§4.2 #4) | Direct Tool (add `ToolLoopOptions.sink`) | Move tool-loop execution into MCP server | Sink shape is intra-app; server adds HTTP layer with no benefit for UI |
| S5 | `capturegraph-tool-layer-and-patterns-2026-09-16.md:787` (§4.2 #5) | Direct Tool (composition-root inject) | Skip injection; keep `ToolRegistry` skill-only | `ConversationWorkflow` already needs the registry for H1; composition-root caching is free |
| P2 | `spec 014:134` out-of-scope + `ADR-0012:13` | Direct Tool (ToolRegistry) — post-competition | MCP-style write tools with manual gate | F2 unification requires single gate at `ToolRegistry.execute`; MCP-style forks the gate |

---

## §14 Appendix C — Conversation with `ask-matt` / future decision flow

This research is meant to feed a future decision (ADR or follow-up ticket). The expected next steps:

1. Team reviews §7 recommendations; if any item is contested, scope a `0013-tool-packaging-decision.md` ADR.
2. For H1: spec 018 §3 already declares "Tool-calling workflow" stable entry = `ToolLoop.run`; this research confirms the path. Implementation can proceed without further ADR.
3. For S3/S4: scope a new spec (e.g. `019-sse-tool-events.md`) extending `LlmTypes.StreamEvent` to actually emit `tool_call`/`tool_result` and adding `ToolLoopOptions.sink`. ~150 LOC change.
4. For S5: ~20 LOC composition-root wiring (`EntryAbility.onCreate` cache registry); no ADR needed.
5. For P2: defer per spec 014 + ADR-0012; revisit after F2 write-path unification.

**No code changes proposed in this research.** This document is read-only analysis to inform future decisions.

---

## §12 Notes on maintenance

- This document is **read-only research**, not a decision record. Decisions belong in a new ADR (e.g. `0013-tool-packaging-decision.md`) once the team weighs in.
- **Update triggers**:
  - `agents/src/main/ets/mcp/tools/` gains a 2nd tool → revisit §2.4 conversion analysis
  - `common/src/main/ets/tools/` gains write tools (P2) → revisit §3 P2 recommendation
  - MCP server SDK ships for HarmonyOS → revisit §4.2 feasibility
  - ToolLoop gets a real production consumer (H1) → drift #1 in capturegraph-tool-layer §4.1 closes
- **Does not duplicate** `capturegraph-tool-layer-and-patterns-2026-09-16.md` — that document is the per-tool/per-pattern catalog; this one is the packaging decision frame.