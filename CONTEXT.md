# MindTrace Domain Context

> **For:** MindTrace project only.
> **Scope:** MindTrace-specific terms (`KnowledgeUnit`, `NoteType`, etc.)
> **NOT for:** universal agent architecture terms (Atom, Molecule, Node, State, etc.) — see [`docs/agents/agent-glossary.md`](./docs/agents/agent-glossary.md).

The single source of truth for what MindTrace-specific words mean. New agent sessions or PRs that introduce a new MindTrace-specific term must register it here; terms not here should be challenged.

## Universal vs project-specific

This file is **project-specific** (MindTrace). For universal agent / software architecture terms that apply to any agent project, see [`docs/agents/agent-glossary.md`](./docs/agents/agent-glossary.md) — that file covers:

- Agent, sub-agent, Node, Edge, State, Channel, StateGraph
- Checkpoint, Thread, Run, Command, Interrupt
- Tool, Reducer, Dispatcher, Subgraph, HITL, Streaming
- Atomic Design: Atom, Molecule, Organism, Template, Page
- Frontend Service vs Backend Service
- Component, Hook, Prop, State (React)

## Language (MindTrace-specific)

**Order**:
The single source-of-truth pipeline the user triggers when capturing a math note. An Order flows Capture → Classify → Structure → TruthCheck → Persist; with `persist: false` it runs analysis-only and stops before Persist.
_Avoid_: pipeline, job, request

**KnowledgeUnit**:
The canonical structured representation of a note. Carries subject, chapter, difficulty (1–4), type, content, embedding, prerequisites, related links, review state.
_Avoid_: Card, NoteData, Unit (in user-facing copy), note (in code surface)

**NoteType (5 values)**:
The semantic category of a KnowledgeUnit, exactly one of: 概念, 定理, 公式, 证明题, 计算题. Persisted as the `type` field; rule IDs reference it.
_Avoid_: kind, category (used internally for the subject axis only), class

**NoteCategory (5 values)**:
The subject axis. A KnowledgeUnit belongs to exactly one subject. 概念/定理/公式/证明题/计算题 is NoteType, not NoteCategory. NoteCategory is the subject axis (数学分析, 线性代数, etc.). NoteType and NoteCategory are independent — a "概念" can belong to "线性代数".
_Avoid_: subject, tag

**Subject**:
The high-level grouping axis (数学分析, 线性代数, 概率论, etc.). Independent of note type.
_Avoid_: category, tag, topic (in code surface)

**Chapter**:
Mid-level grouping within a Subject (e.g. "极限与连续" within 数学分析). Free-text; not enforced to be unique across notes.

**Difficulty**:
One of EASY / MEDIUM / HARD / EXPERT (numeric 1–4). Indicates mastery cost, not review urgency.

**Prerequisites**:
A directed edge: this KnowledgeUnit's `prerequisites` array lists the KnowledgeUnit IDs that must be understood first.
_Avoid_: dependencies (in code surface), requires

**Related**:
A non-gating edge: this KnowledgeUnit's `related` array lists the KnowledgeUnit IDs that are useful but not blocking.
_Avoid_: seeAlso, links

**Capture**:
The act of producing raw text from an image, via OCR or manual input. Output is a string, not a KnowledgeUnit.

**Structure**:
The act of turning a Capture result into a KnowledgeUnit (subject, chapter, type, etc.). Performed by the LLM.
_Avoid_: organize, process (in code surface)

**TruthCheck**:
The pipeline step that validates the structured KnowledgeUnit against the capture text before persisting (the `truth_check` step of the CaptureGraph). A failed check stops the Order with a CaptureGraphError — no fallback KnowledgeUnit is produced.

**ReviewStatus (5 values)**:
NEW / LEARNING / REVIEW / GRADUATED / LAPSED. Drives spaced-repetition scheduling.
_Avoid_: state (in code surface, e.g. `state`), status (ambiguous with HTTP status)

**ReviewInterval**:
Days until next review, computed from ReviewStatus and review history.
_Avoid_: interval (in code surface), delay

**Embedding**:
A fixed-dimension vector representation of the note content, used for similarity search. Stored on KnowledgeUnit.

**Dispatch**:
The orchestration entry point that runs a Capture through the AI pipeline. Returns either a structured analysis or a KnowledgeUnit.

**Dispatcher**:
The class in `agents/core/Dispatcher.ets` that runs the pipeline. Single public entry: `dispatch(req, context?, options)`. Sub-agents are private collaborators.
_Avoid_: Controller, Manager, Handler

**CaptureGraph**:
The project's native ArkTS implementation of the LangGraph graph model — **LangGraph is the project's primary orchestration design**, and its naming (Node / Edge / State / conditional edge / START / END) is canonical (universal definitions in `docs/agents/agent-glossary.md`). CaptureGraph (in `agents/src/main/ets/graph/`) executes an Order: fixed edges between steps, plus a conditional edge after `truth_check` that reaches `persist` only when the state's `persist` flag is set. Built per dispatch; no checkpoint / HITL / subgraph by design (ADR-0008).

**CaptureStep**:
The node vocabulary of the CaptureGraph: `START | capture | classify | structure | truth_check | persist | END`. Lowercase for steps, uppercase for sentinels.

**CaptureGraphError**:
The structured error a CaptureGraph node throws on failure: `kind`, `message`, `step`, `retriable`, optional `cause`. It short-circuits the Order — the user sees an error, never a fabricated KnowledgeUnit.

**DispatchOptions**:
The per-dispatch options bag passed to `Dispatcher.dispatch`: `persist` (may this Order write the KnowledgeUnit?) and `dao` (the injected persistence implementation).

**Sub-agent**:
A private collaborator inside the Dispatcher pipeline (TypeClassifier, KnowledgeModel). Sub-agents are not user-facing.
_Avoid_: agent (overloaded, see below)

**NoteDaoAdapter**:
The entry-side adapter that implements `agents`' `NoteDaoInterface` on top of `entry`'s `NoteDao`. The seam that lets the agents module persist without depending on entry.

**Kit Facade (contract)**:
An interface in `common/src/main/ets/kit/` (`ReminderFacade`, `BackgroundTaskFacade`, `FormCardFacade`) declaring a HarmonyOS kit capability for the business pipeline. Implementations are injected at the composition root when kit integration lands; this is a seam, not an import ban — DevEco template modules (abilities, FormAbility) import kit APIs directly (ADR-0009).

**MCP 工具 (mcp/)**:
A tool in `agents/src/main/ets/mcp/tools/` (currently `OcrTool`), built by the team as an MCP-语义 tool. The directory classifies tools by MCP tool semantics — not by whether an MCP server is running (none does today). CRUD-style tools (增删查改) belong in `tools/` instead (ADR-0010).
_Avoid_: renaming `mcp/` away; calling it "the MCP server".

**OCR 服务 (tools/ocr_service/)**:
The team-built Python FastAPI OCR service at the **repo-root** `tools/` directory (formula/combined recognition over HTTP :8000, started via `start.bat`), consumed by `OcrTool`. Entirely distinct from `agents/src/main/ets/tools/` — the ArkTS CRUD-tool reservation slot (ADR-0010).
_Avoid_: confusing repo-root `tools/` (Python 服务) with the agents `tools/` 预留位 (F7, agent-tools inventory 2026-09-06).

**小艺 skill 预留位 (skill/)**:
The `skill/` HSP, reserved for Xiaoyi (小艺) skill integration. Deliberately a stub today (`SKILL_VERSION` + placeholder `SkillAbility`); retention is a recorded decision ([ADR-0011](./docs/adr/0011-skill-xiaoyi-reservation.md)), and its 7 intent actions are declared in `skill/src/main/module.json5`.
_Avoid_: calling it dead code or an empty shell; proposing its removal or freeze.

## Ambiguous terms

The word **agent** is overloaded in this codebase. Use the precise form:

| Form | Meaning | Where |
|------|---------|-------|
| **MindTrace** | The whole app (project name) | repo name, `AppScope` config |
| **`agents/`** (HSP) | The AI business module | `agents/src/main/ets/...` |
| **`Agent*` (user-facing service)** | An in-app AI helper. *TODO: rename to `Assistant*` per `docs/adr/0002-agent-terminology-disambiguation.md`* | `AgentChatService`, `AgentFloatWindow`, `AgentMemoryService` |
| **sub-agent** | A private collaborator inside the Dispatcher | `TypeClassifier`, `KnowledgeModel` |

**User-facing rule**: when writing copy the user sees (toast, placeholder, button label), use the precise form ("assistant" or "AI helper"), never "agent". When naming code, the migration is staged.

## Disambiguation pitfalls

| Confusion | Disambiguation |
|-----------|----------------|
| "subject" (math) vs "subject" (vs object) | Always math sense here. "Object" appears only in OOP context (interface fields, decorator). |
| "note" (raw OCR text) vs "note" (KnowledgeUnit) | User says "note" → means KnowledgeUnit. Raw text from OCR is "OCR result" or "capture text". |
| "category" (NoteType) vs "category" (NoteCategory) | Two different fields. "category" in code = NoteCategory (subject axis). The 5-type classification is `type` or `NoteType`. |
| "preview" (in code) vs "preview" (in git/diff) | `ENABLE_GALAXY_PREVIEW_UNITS` is the demo fixture flag, not UI rendering. |
| "Lint" (CLI tool) vs "lint" (the verb) | Capital "Lint" = the `scripts/arkts-lint/` engine. "lint" = the action of running it. |

## Rules

- **Be opinionated.** The glossary disambiguates; it does not enumerate every synonym. When two words could mean the same thing, pick one and list the others under `_Avoid_`.
- **Be project-specific.** This file is for MindTrace. Universal terms (Node, Edge, State, Atom, Molecule) live in [`docs/agents/agent-glossary.md`](./docs/agents/agent-glossary.md). General terms (function, string, Promise) don't belong in either glossary.
- **Cross-reference code.** When a term is defined here, it should match the field name in code. If you find a mismatch, surface it.

## Note on this file

This file is **devoid of implementation details**. Where a term's meaning *requires* code knowledge (e.g. "Dispatcher" is the class name in `agents/core/Dispatcher.ets`), the link is given for grounding but the *meaning* here is what an agent should treat as canonical. If the code contradicts this file, the code is wrong.

Implementation decisions (why this Dispatcher signature, why LlmGuard exists, why mcp/ is misnamed) live in [`docs/adr/`](./docs/adr/).

## Migration note (2026-09-02)

Universal agent terms (previously here) have been moved to [`docs/agents/agent-glossary.md`](./docs/agents/agent-glossary.md) as part of the naming governance refactor. This file now contains only MindTrace-specific terms.

If a term is **not** in this file and is **not** a common programming term, it likely belongs in the universal glossary.