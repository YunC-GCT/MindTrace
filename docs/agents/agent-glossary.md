# Agent Glossary

> **For:** all agents (any project, framework-agnostic)
> **Scope:** universal agent / software architecture terms
> **NOT for:** project-specific terms (those live in `CONTEXT.md` at the repo root)

The single source of truth for what agent-architecture words mean. New agent sessions or PRs that introduce a new universal term should register it here; terms not here should be challenged.

If a term is **project-specific** (e.g. `KnowledgeUnit` in MindTrace, `PydanticModel` in a FastAPI project), it belongs in the project's glossary (`CONTEXT.md` or equivalent), NOT here.

> **LangGraph note**: the graph vocabulary below (Node / Edge / State / StateGraph / Channel / …) follows LangGraph — adopted as MindTrace's primary orchestration design model, implemented natively in ArkTS as `CaptureGraph` (ADR-0008).

## Language

**Agent**:
A system that takes input, makes decisions, and produces output. In agent frameworks, usually a graph of nodes.
_Avoid_: bot, AI, model, LLM, assistant (overloaded — see "agent" disambiguation below)

**Sub-agent**:
A specialized component within a larger agent. Handles a specific concern (e.g. classification, retrieval, validation).
_Avoid_: tool (overloaded with "function tool"), subagent (one word)

**Node (atom)**:
The smallest unit of work in an agent. Takes state, returns state. Synchronous or async. Composable.
_Examples_: `RetrieveNode`, `ClassifyNode`, `FormatResponseNode`

**Edge (molecule)**:
A connection between two nodes. May be conditional (route by predicate), normal (always go), or named (explicit).
_Examples_: "if classification is 'math', go to SolveNode; else go to RefuseNode"

**State (graph state)**:
The typed data structure passed between nodes. Often a `TypedDict` or Pydantic model. Single source of truth during execution.
_Avoid_: state (ambiguous with "US state", "state machine state"), context, memory

**Channel**:
A named field within state. Type-safe accessor. E.g. `state["messages"]` reads the messages channel.

**StateGraph**:
The complete graph definition: nodes, edges, state schema. Entry point + exit point defined.

**Checkpoint**:
A persisted snapshot of state at a given point. Allows resume-after-failure. Implementation-specific (in-memory, SQLite, Postgres, Redis).

**Thread**:
A single execution of the graph from entry to exit (or to interrupt). One user message = one thread.

**Run**:
An active or completed execution of a thread. Has a unique ID, state, and history.

**Command**:
An imperative update to state. Can be issued from inside a node, or from outside (e.g. resume after interrupt).

**Interrupt**:
A pause in graph execution at a specific point, awaiting external input (human approval, async callback). Paired with `Command` to resume.

**Tool**:
A function callable by a node. Often an LLM-callable tool (with JSON schema). Distinct from a node: a tool is data, a node is flow.

**Reducer**:
A function that combines two state values (e.g. list merge). Used in StateGraph annotation.

**Dispatcher (orchestrator)**:
The class that wires up nodes, edges, and state into a runnable graph. Single entry point.
_Avoid_: Controller, Manager, Handler (overloaded)

**Subgraph**:
A StateGraph used as a node in a parent graph. Enables composition.

**HITL (Human-In-The-Loop)**:
Pattern where a graph pauses for human review (via `interrupt`) before proceeding.

**Streaming**:
Emitting partial results (e.g. tokens from an LLM) as they're generated, rather than waiting for the full response.

**Reasoning**:
The chain-of-thought or planning step an agent performs before acting. Often a separate node that emits thoughts.

---

## Frontend terms (Atomic Design / React)

When the frontend follows Brad Frost's Atomic Design:

**Atom**:
A single, indivisible UI element. No internal state, no dependencies on other components.
_Examples_: `Button`, `Input`, `Label`, `Icon`, `Avatar`

**Molecule**:
A group of atoms serving a single purpose. Composed of 2+ atoms. May have simple state.
_Examples_: `SearchField` (Input + Button), `FormField` (Label + Input + Error)

**Organism**:
A more complex component. Contains business logic. May have rich state. Composed of molecules and atoms.
_Examples_: `Header` (Logo + Nav + Search), `CommentList` (multiple CommentCard)

**Template**:
A page-level layout. Slots for content. No business logic itself.
_Examples_: `MainLayout` (header + content area + footer), `AuthLayout`

**Page**:
A complete page. The route endpoint. Composed of templates + organisms + molecules + atoms. One per route.
_Examples_: `HomePage`, `LoginPage`, `DashboardPage`

**Service**:
A non-React module that handles external communication (API client, WebSocket, etc.). Has no UI.
_Examples_: `auth-service.ts`, `http-client.ts`, `websocket-service.ts`

**Hook (React)**:
A function starting with `use` that adds state or side effects to a function component.
_Examples_: `useAuth`, `useFetch`, `useLocalStorage`

**State (React)**:
Component-local data that triggers re-render when changed. Managed via `useState`, `useReducer`, or external state library.

**Prop**:
Data passed from a parent component to a child. Read-only in the child.

---

## Backend terms (general service)

**Service (backend)**:
A class or module that encapsulates business logic, often with external dependencies (DB, network, third-party APIs).
_Examples_: `UserService`, `PaymentService`, `EmailService`

**Repository**:
A class that abstracts data persistence. Methods like `findById`, `save`, `delete`. No business logic.

**Adapter**:
A class that wraps an external interface (e.g. third-party API) behind a project-owned interface. Enables substitution.

**Facade**:
A class that exposes a simplified interface to a complex subsystem. Combines multiple services behind one entry point.

---

## Ambiguous terms

The word **"agent"** is overloaded. Use the precise form:

| Form | Meaning | Where |
|---|---|---|
| **Project name** (e.g. `MindTrace`, `LangChain`) | The whole project | repo name, `AppScope` config |
| **Framework / module** (e.g. `agents/`, `langgraph`) | The agent framework or its module | `agents/src/...`, `langgraph.graphs.StateGraph` |
| **User-facing service** (e.g. `assistant`, `chatbot`) | The end-user helper | UI copy, product docs |
| **Sub-agent** | A specialized component | `class RetrieveNode`, `class ClassifyNode` |

The word **"service"** has two unrelated meanings in this repo:

| Form | Meaning | Example |
|---|---|---|
| **Frontend service** | API client / external integration | `frontend/src/services/auth-service.ts` |
| **Backend service** | Business logic class | `backend/src/services/user_service.py` |

The word **"state"** has at least three meanings:

| Form | Meaning | Example |
|---|---|---|
| **Graph state** | TypedDict passed between nodes | `class GraphState(TypedDict): ...` |
| **React state** | Component-local data | `const [count, setCount] = useState(0)` |
| **HTTP state** | Request/response state | `state: "open" | "closed"` |

---

## How to use this glossary

- **When writing code**: if you invent a new agent-architecture term (e.g. a new abstraction type), add it here
- **When reading code**: if a term is unclear, look it up here first
- **When reviewing PRs**: challenge new terms; if they're project-specific, push them to the project's `CONTEXT.md` instead
- **When choosing a name**: pick from this glossary's vocabulary; if no fit, invent carefully and add it

## Last updated

2026-09-02 (created from CONTEXT.md split — see git history for migration notes)