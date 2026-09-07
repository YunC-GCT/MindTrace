# Ticket #7 — AgentChatService decomposition into 3 services

> **Status**: in progress (2026-09-06 — PR1 IntentClassifier 已落地; PR2 ChatStatusMachine / PR3 ReplyService 待续)
> **Source ADR**: implicit (mirrors ticket #3, ADR-0006 philosophy)
> **Files affected**: `entry/src/main/ets/services/AgentChatService.ets` (split into 3 files); `entry/src/main/ets/overlays/AgentFloatWindow/` (consumer, unchanged)
> **Test files**: new `entry/src/ohosTest/ets/test/AgentChatService.test.ets` (Hypium)

## Why this ticket

`entry/src/main/ets/services/AgentChatService.ets` is **861 LOC** (2026-09-06 复核) with 12+ responsibilities per the audit (§4.3):
- Intent classification (note_generation vs chat)
- LLM orchestration (streaming + non-streaming)
- Image recognition (analyzeImage)
- Note generation pipeline
- Chat reply (realReply / realReplyStream)
- Memory read/write (10+ safeX wrappers)
- Status state machine (13 named steps incl. completed)
- Prompt construction
- 30+ keyword dictionaries (intent, deny, explicit)
- Session management
- Content protocol normalization
- History persistence

This is the entry/services layer's biggest god class. Per the architecture principle established in ADR-0006 (each class ≤ 300 LOC, single reason to change), AgentChatService should be split.

This ticket mirrors #3 (KnowledgeModel split) but at the entry/services layer. Same 3-way split rationale.

## What we will build

Three new classes in `entry/src/main/ets/services/`:

```ts
// 1. Intent classification + prompt building (~250 LOC)
class IntentClassifier {
  classify(userText: string): Promise<Intent>;
  //   - keyword arrays (intent, deny, explicit)
  //   - hasActionNearTarget distance algorithm
  //   - returns 'note_generation' | 'chat'

  buildSystemPrompt(intent: Intent): string;
  //   - prompt construction for chat
}

// 2. Reply orchestration (~300 LOC)
class ReplyService {
  constructor(
    private intentClassifier: IntentClassifier,
    private memoryService: MemoryService,
    private contentProtocol: ContentProtocol,
  ) {}
  async realReply(req: ChatRequest): Promise<ChatReply>;        // non-streaming
  async realReplyStream(req: ChatRequest, onDelta: (delta: string) => void): Promise<void>;  // streaming
  async captureReply(imageUri: string, userText: string): Promise<ChatReply>;  // image path
  // delegates: classify → memory → prompt → LLM → normalize → memory-write
}

// 3. Status state machine (~150 LOC)
class ChatStatusMachine {
  step: ChatStatusStep;  // observable state, updated as reply progresses
  advance(reason: string): void;
  reset(): void;
  // 13 named steps (image_message_save, image_recognize, ..., completed)
}
```

**PR2 design notes (post-`0399d8f`, 2026-09-07):**
- `advance` signature: spec 伪代码 L60 写 `advance(reason: string): void`（observable step 字段 + void 返回），实际 PR2 实现为 `advance(step: ChatStatusStep): ChatStatusMeta`（纯函数返回 meta，给 setStatusMeta 直用）。后者更适合 facade 路径（无需 ChatStatusModel 自己持 step 状态）—— 保留。
- `step` observable 字段（L59）+ `reset()` 方法（L61）**PR2 未实现**，留给 PR3 与 ReplyService 拆分一起裁决：是否需要 observable step 取决于 ReplyService 是否要 query step（PR3 时再决定）。
- `finishBusy()`（setStatusMeta(null) + setBusy(false)）**不挪入 ChatStatusMachine**：busy lifecycle 由 AgentChatService 持有，状态机只负责 step→meta 转换。

`AgentChatService` becomes a thin facade that the UI calls:

```ts
class AgentChatService {
  private intentClassifier = new IntentClassifier();
  private statusMachine = new ChatStatusMachine();
  private replyService = new ReplyService(
    this.intentClassifier,
    this.memoryService,
    new ContentProtocol(),
  );
  // Public surface preserved (called by AgentFloatWindow)
  async realReply(req): Promise<ChatReply> {
    return this.replyService.realReply(req);
  }
  async realReplyStream(req, onDelta) {
    return this.replyService.realReplyStream(req, onDelta);
  }
  // status callbacks
  setStatusMeta(meta): void { this.statusMachine.step = meta; }
}
```

## Public surface change

`AgentFloatWindow` and other callers use `AgentChatService.realReply / realReplyStream / setStatusMeta`. **All preserved**. The class becomes a thin facade (~80 LOC) that delegates to 3 internal services.

The status state machine is exposed via `setStatusMeta` and `getStatusMeta` (or as a separate callback interface), unchanged from current behavior.

## Migration (3 atomic PRs)

### PR 1: extract `IntentClassifier`

```bash
git mv entry/src/main/ets/services/AgentChatService.ets \
       entry/src/main/ets/services/_AgentChatService.ets.legacy
# new file: entry/src/main/ets/services/IntentClassifier.ets
# AgentChatService delegates intent + prompt to it (1 line change)
# add entry/src/ohosTest/ets/test/IntentClassifier.test.ets
```

After PR 1: intent logic isolated, behavior preserved.

### PR 2: extract `ChatStatusMachine`

```bash
# new file: entry/src/main/ets/services/ChatStatusMachine.ets
# AgentChatService delegates status to it (status setter/getter methods)
# add tests for the 12-step transitions
```

After PR 2: status state isolated.

### PR 3: extract `ReplyService`, delete legacy

```bash
# new file: entry/src/main/ets/services/ReplyService.ets
# ReplyService contains orchestration (realReply, realReplyStream,
# captureReply, note-generation orchestration)
# AgentChatService becomes a thin facade (~80 LOC)
# delete _AgentChatService.ets.legacy
# add entry/src/ohosTest/ets/test/ReplyService.test.ets
# add entry/src/ohosTest/ets/test/AgentChatService.test.ets (facade)
```

After PR 3: 3 services extracted, AgentChatService is a thin facade.

## Test plan (TDD, Hypium)

| Class | Tests | What each verifies |
|-------|-------|-------------------|
| `IntentClassifier` | 3 | (1) note-generation intent detected; (2) chat intent detected; (3) deny intent rejected |
| `ChatStatusMachine` | 2 | (1) initial state correct; (2) advance through full 13-step cycle |
| `ReplyService` | 4 | (1) non-streaming reply flow; (2) streaming with onDelta callback; (3) image reply via captureReply; (4) memory write on success |
| `AgentChatService` (facade) | 1 | (1) all 3 delegate paths work end-to-end |

10 new Hypium tests total. Adds to existing test count. Reduces lint warnings by ~80 (methods that flagged `struct-no-regular-methods` now live in properly-typed services).

## Reversibility

**Hard** (structural split is hard to undo). Each PR is independently revertable.

## Acceptance criteria

- [ ] `AgentChatService.ets` ≤ 100 LOC (facade only)
- [ ] 3 new files exist: `IntentClassifier.ets`, `ReplyService.ets`, `ChatStatusMachine.ets`
- [ ] 10 new Hypium tests in `entry/src/ohosTest/ets/test/`
- [ ] `node scripts/arkts-lint/index.mjs --quiet` shows warnings count reduced by ~80
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` all 65+ pass
- [ ] No change in observable behavior: same replies, same status transitions, same memory writes

## Progress (2026-09-07)

| PR | Scope | Status | Notes |
|----|-------|--------|-------|
| PR1 | extract `IntentClassifier` | ✅ landed (`23be44c`) | IntentClassifier.ets 326 LOC; 4 Node structural guards; Hypium deferred to user |
| PR2 | extract `ChatStatusMachine` | ✅ landed (`8f5ce3f` + `0399d8f` + `0147078`) | ChatStatusMachine.ets 43 LOC; AgentChatService 562 → 516; 6 Node structural guards; `advance(step): ChatStatusMeta` 纯函数形式（vs spec L60 `advance(reason): void`） |
| PR3 | extract `ReplyService`, delete legacy | ⏳ pending | 待 spec L59/L61 (`step` 字段 + `reset()` 方法) 决裁 + facade ≤100 LOC 收敛 + Hypium 补齐 |

## Sequence (3 atomic PRs)

As above. Each revertable. Each adds tests at every step.

## Out of scope (intentionally)

- Refactoring `MemoryService` (own class, separate concern)
- Refactoring `ContentProtocol` (already in `common/`, separate concern)
- Adding new intent types or new prompts
- LlmClient consolidation (ticket #5, separate)
- Dispatcher changes (entry doesn't use Dispatcher; entry uses AgentChatService directly)

## Sequencing note

This ticket is independent of ticket #3 (KnowledgeModel split) and ticket #4 (Dispatcher single-entry). All 3 are P0 god-class refactors; they can be done in any order. Doing #4 first might make the test plumbing simpler, but is not a hard dependency.
