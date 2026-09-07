# MindTrace Agent Framework — LangGraph Comparison Research

> **Date:** 2026-09-02
> **Scope:** Is MindTrace's agent pipeline built on LangGraph (or any equivalent graph/state-machine framework)?
> **Project:** MindTrace (`<本地仓库根>`)

---

## Verdict

**No.** MindTrace does **not** use LangGraph. It uses a **custom Dispatcher + sub-agent pipeline** (linear / synchronous call chain). The framework is purpose-built for HarmonyOS / ArkTS, not ported from any external agent library.

Specifically:
- ❌ No LangGraph (`@langchain/langgraph`) imports anywhere
- ❌ No `node` / `edge` / `state` / `channel` / `checkpoint` / `interrupt` / `command` / `StateGraph` concepts
- ❌ No graph topology (no conditional edges, no DAG)
- ✅ Custom `Dispatcher` class with 3 public methods (`analyze`, `dispatch`, `routeDispatch`)
- ✅ Sub-agents invoked via plain `new` + method call (not via graph)
- ✅ Pipeline is **linear and synchronous**: `recognizeText() → structure()` (per `Dispatcher.ets:105-131`)

---

## MindTrace's Actual Architecture

### The orchestrator

**`Dispatcher` (`agents/src/main/ets/core/Dispatcher.ets`, 159 lines)** is the main entry point.

Three public methods (per `Dispatcher.ets:63, 97, 155`):

```ts
// Dispatcher.ets:63-93
async analyze(req: DispatchRequest, context?: Context): Promise<DispatchAnalysisResult> {
  // Step: OCR + classify ONLY, returns analysis (no persistence)
  const classifier = new TypeClassifier();
  const classification = await classifier.classify(req.payload, context);
  ...
}

// Dispatcher.ets:97-152 — main entry
async dispatch(req: DispatchRequest, context?: Context): Promise<DispatchResult> {
  // Step 1: recognize text (OCR or manual)
  // Step 2: structure (LLM call inside KnowledgeModel)
  // Step 3: return KnowledgeUnit
  ...
}

// Dispatcher.ets:155-157 — alias
async routeDispatch(req: DispatchRequest, context?: Context): Promise<DispatchResult> {
  return this.dispatch(req, context);  // identical
}
```

Per ADR-0003, these 3 methods should collapse to one `dispatch(req, opts?)`. The audit recommends single-entry design (issue #4).

### The sub-agents

Two sub-agents, both in `agents/src/main/ets/agents/`:

| Sub-agent | File | Lines | Public method(s) | Returns |
|-----------|------|-------|-------------------|---------|
| `TypeClassifier` | `TypeClassifier.ets` | 363 | `classify(payload, ctx)`, `recognizeText(payload, ctx)` | `ClassificationResult { category, subject, chapter, confidence }` |
| `KnowledgeModel` | `KnowledgeModel.ets` | 929 (god class) | `structure(ocrText, ...)` | `KnowledgeUnit` (the god class flagged in ADR-0006 for split) |

### The flow

```
AiService.capture(imageUri, userText)
        ↓
   new Dispatcher().dispatch(req)
        ↓
   ┌─ Step 1 (Dispatcher.ets:105) ───────────────────┐
   │ new TypeClassifier().recognizeText(payload, ctx)│ ← OCR + text extraction
   └─────────────────────────────────────────────────┘
        ↓ (recognized.text)
   ┌─ Step 2 (Dispatcher.ets:129) ──────────────────┐
   │ new KnowledgeModel().structure(ocrText, ...)  │ ← LLM structuring + truth-check
   └─────────────────────────────────────────────────┘
        ↓
   Promise<DispatchResult> with success, data, route
```

This is a **linear, sequential, synchronous chain** — no parallel branches, no conditional routing, no checkpointing.

---

## Comparison vs LangGraph

| LangGraph concept | MindTrace equivalent | Status |
|---|---|---|
| `StateGraph` | None — there's no state machine | ❌ Missing |
| `Node` (a function taking/returning state) | Sub-agents (`TypeClassifier`, `KnowledgeModel`) — but invoked as **plain method calls**, not as graph nodes | 🟡 Partial (similar role, different abstraction) |
| `Edge` (default: A → B) | Hardcoded sequential calls in `Dispatcher.dispatch()` | 🟡 Implicit (no graph object, but same connectivity) |
| `Conditional Edge` (route by state predicate) | None — pipeline is fixed | ❌ Missing |
| `START` / `END` nodes | `dispatch()` entry + `return DispatchResult` | 🟡 Manual |
| `State` (typed channel for inter-node data) | Local variables (`recognized.text`, `ocrText`) — not a typed state channel | 🟡 Implicit |
| `Checkpoint` (save/restore state at a node) | None — no resume capability | ❌ Missing |
| `Command` (imperative state update) | None | ❌ Missing |
| `interrupt` / `human-in-the-loop` | None — agent runs end-to-end without pause | ❌ Missing |
| Subgraph composition | None — single Dispatcher, no nested graphs | ❌ Missing |
| Conditional entry point | None — single `dispatch()` entry | ❌ Missing |
| Streaming events | None — only final `DispatchResult` returned | ❌ Missing |

**Verdict:** MindTrace implements the **minimum** of what LangGraph provides: 2 "nodes" connected by 1 implicit "edge". It does **not** have state management, conditional routing, checkpointing, interrupts, or streaming events.

---

## Comparison vs other patterns

| Pattern | Match | Why |
|---|---|---|
| **LangGraph** | 0/12 concepts | None of the framework abstractions |
| **Plain Orchestrator** (GoF pattern) | ✅ Strong | `Dispatcher` IS an orchestrator |
| **Pipeline** (sequential stages) | ✅ Strong | `recognizeText → structure` is linear |
| **State Machine** | ❌ Weak | No state object; no transitions; no guards |
| **Strategy** (sub-agents swappable) | 🟡 Partial | Sub-agents constructed via `new`, not injected |
| **Service Locator** | 🟡 Partial | `new TypeClassifier()`, `new KnowledgeModel()` are service-like |
| **Hexagonal / Ports** | 🟡 Partial | `LlmGuard` wraps LLM as a port |

The closest pattern match is **Orchestrator + Pipeline** (two complementary GoF patterns). MindTrace's `Dispatcher` orchestrates a 2-stage pipeline.

---

## Primary source citations

Every architectural claim is grounded in:

| Claim | File:line |
|---|---|
| `Dispatcher` is the orchestrator | `agents/src/main/ets/core/Dispatcher.ets:55` (`export class Dispatcher`) |
| `analyze()` exists | `Dispatcher.ets:63` |
| `dispatch()` is main entry | `Dispatcher.ets:97` |
| `routeDispatch()` is alias | `Dispatcher.ets:155-157` |
| Pipeline order: recognize → structure | `Dispatcher.ets:105, 129` |
| TypeClassifier methods | `agents/src/main/ets/agents/TypeClassifier.ets` (line 1-363) |
| KnowledgeModel methods | `agents/src/main/ets/agents/KnowledgeModel.ets:1-929` |
| No LangGraph imports | `grep` across `*.ets`, `*.ts`, `package.json` — no matches |
| `mcp/tools/` is HTTP, not MCP | `AGENTS.md` rule #9, ADR-0005 |
| Single entry recommended | `docs/adr/0003-dispatcher-single-entry-design.md` |
| 870-LOC god class for split | `docs/adr/0006-knowledge-model-decomposition-plan.md` |

---

## Implications for the agent pipeline

Since MindTrace is NOT LangGraph, extending it has different costs:

### Easy (no abstraction needed)
- ✅ Add a new sub-agent class: just write a new file and `new` it from Dispatcher
- ✅ Add a new pipeline step: just add a method call in `Dispatcher.dispatch()`
- ✅ Change sub-agent order: edit the Dispatcher code directly

### Hard (would require new abstraction)
- ❌ **Conditional routing** ("if classify says formula, go to A; if proof, go to B") — would need a routing layer
- ❌ **Checkpoint / resume** ("user paused mid-pipeline") — would need state persistence
- ❌ **Human-in-the-loop** ("confirm before final step") — would need interrupt mechanism
- ❌ **Streaming events** ("emit partial KnowledgeUnit as it's built") — would need observable/promise chain
- ❌ **Parallel branches** ("try TypeClassifier + LlmGuard validation in parallel") — would need Promise.all

### ADR-driven evolution (per audit)

The audit (2026-09-01) flagged 4 P0 refactor tickets that would add LangGraph-like capabilities without adopting LangGraph:

- **#3** (ADR-0006): Split `KnowledgeModel` into `StructureService` + `TruthCheckService` + `PromptBuilder` — adds module boundaries
- **#4** (ADR-0003): Collapse Dispatcher's 3 methods to `dispatch(req, opts?)` — cleaner seam
- **#5** (ADR-0004): Collapse `LlmClient` 3 calls to `call(opts) + adapters` — cleaner LLM abstraction
- **#7** (split `AgentChatService` into 3 services): same pattern at services layer

**Conclusion:** MindTrace's roadmap is *toward* the kind of clean module boundaries LangGraph enforces, but without adopting LangGraph. Each refactor adds 1 concept (a service, an option, an adapter) without an external framework.

---

## Conclusion

MindTrace has a **custom 2-stage pipeline orchestrator** (Dispatcher → TypeClassifier → KnowledgeModel), not a graph framework. It's the simplest architecture that could work for the current scope (拍照→AI 分类→知识结构化), and the audit's refactor tickets (3, 4, 5, 7) push it toward *cleaner* orchestration without adopting a heavier framework like LangGraph.

If you need graph features later (conditional routing, checkpointing, parallel branches, streaming), the closest lightweight alternatives for ArkTS would be:
1. Build the abstractions inline (a `RoutingGraph` class, a `CheckpointStore`)
2. Adopt a different framework that runs on HarmonyOS's Node-like runtime (would require bridge)

For now, the **3-method Dispatcher + 2 sub-agents + linear pipeline** is appropriate for MindTrace's scope.