# Delivery Checklist — spec 019 P0 / issue #111 StreamEvent vertical slice

## Scope and branch inventory

- Project root checked: `D:\HMgent\MindTrace`
- Required Harmony project files present before setup work: root `build-profile.json5` and root `oh-package.json5` both exist; no scaffold action required.
- Current branch confirmed by `git branch --show-current`: `feature/spec-019-p0`
- Implementation scope: only issue #111 StreamEvent protocol vertical slice; verification tasks T043-T044 are excluded for the later `spec-verify` phase.

## Pre-existing dirty / untracked files excluded from #111 staging unless explicitly required

Observed before implementation (`git status --short`):

- `M docs/research/frontend-component-audit-2026-09-06.md` — unrelated research/audit document; exclude.
- `?? docs/research/arkweb-render-pipeline-stability-2026-09-11.md` — unrelated ArkWeb research document; exclude.
- `?? entry/src/main/ets/shared/atoms/WebKeepAlive.ets` — unrelated UI/ArkWeb keep-alive atom; exclude.
- `?? spec/feature.json` — pre-existing/unrelated SDD pointer; exclude unless parent requests SDD metadata staging.
- `?? spec/019-reasoning-process-display-p0/` — feature SDD artifacts; include only `delivery-checklist.md`, `review-report.md`, and updated `tasks.md` plus approved source/test files for #111.

## Reference review evidence

- T002 ArkTS strict review: `docs/style/arkts-1.1.md` read before `.ets` edits. Key constraints applied: no `any`/`unknown`, no destructuring, typed object literals, explicit imports/exports, no untyped inline object type aliases.
- `arkts-grammar-standards` skill loaded before first `.ets` edit, and `references/recipes-core.md` read before writing ArkTS files.
- Official ArkTS docs availability checked with `devecocli docs search ArkTS`.
- T003 ADR-0015 review: `docs/adr/0015-structured-stream-events.md` read. Same-PR constraint applied: structured callback migration and reasoning-to-content fallback deletion are implemented in the same slice.

## Existing stream callsite inventory and migration notes

Initial grep inventory for old `(delta, kind)` stream contract:

- `common/src/main/ets/llm/LlmTypes.ets`
  - `LlmStreamCallback = (delta, kind)` old callback type.
  - `LlmCallRequest.onDelta` depends on old callback type.
- `common/src/main/ets/llm/LlmClient.ets`
  - Usage comment references `(delta, kind)`.
  - `callStreamInternal`, `processSseBuffer`, `processSseBufferFinal`, and SSE delta parsing consume `LlmStreamCallback`.
  - Old SSE fallback emits `reasoning_content` as content when `content` is empty; must be removed.
- `entry/src/main/ets/services/ReplyService.ets`
  - `ReplyDeltaSink = (delta, kind)` old type.
  - Stream `onDelta` accumulates every delta into final content; must become text-only final answer accumulation.
  - Three explicit `enableThinking: false` overrides must be removed from complete/stream/fallback paths.
- `entry/src/main/ets/workflows/conversation/ConversationTypes.ets`
  - `appendAiMsg(id, delta, kind?)` old callback shape.
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`
  - Stream sink forwards `(delta, kind)` to callbacks.
  - Interruption message is appended without `kind`; after migration it must append through a final-answer text event.
  - Persistence must save only `StreamReplyResult.content`, which should be true text-only final answer content.
- `entry/src/main/ets/services/AgentChatService.ets`
  - Callback and adapter use old `(delta, kind?)` shape.
- `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets`
  - UI consumes `kind === 'reasoning'` into `ChatMsg.reasoning`, else content; must switch to `StreamEvent.type` with tool-event safe ignore.

Required migration surface is intentionally limited to the files named above plus new Seam A/B tests and SDD delivery artifacts.

## TDD and validation log

- Foundational TDD seams created:
  - Seam A: `common/src/test/LlmStreamEvents.test.ets` covers SSE payload to `StreamEvent` conversion, four event categories, reasoning-only, text-only, both-fields ordering, null delta, empty choices, and default thinking expectations.
  - Seam B: `entry/src/test/AgentChatStreamEvents.test.ets` covers `StreamEvent` dispatch into `ChatMsg.reasoning` / `ChatMsg.content` via planned `applyStreamEventToChatMsg` helper, plus reserved tool-event safe ignore.
- The new tests intentionally referenced the new protocol seam before production implementation, satisfying the TDD red-step intent. `arkts_check` on the two new test files reported no standalone syntax errors; full project compile/test is expected to fail until production exports and implementations are added.
- US3 protocol migration completed:
  - `StreamEventType`, `StreamEvent`, and concrete thinking/text/tool_call/tool_result event interfaces are defined in `common/src/main/ets/llm/LlmTypes.ets`.
  - `LlmStreamCallback` and `LlmCallRequest.onDelta` now use a single structured `StreamEvent` parameter.
  - `common/src/main/ets/Index.ets` exports the new event family and `STREAM_EVENT_TYPES` for entry consumers.
  - `LlmClient`, `ReplyService`, `ConversationWorkflowCallbacks`, and the conversation adapter callback surface now compile against the structured event contract.
- US1 thinking channel flow completed:
  - Seam A reasoning-only fixture maps to exactly one `thinking` event.
  - Seam B `thinking` fixture maps to `ChatMsg.reasoning` via `applyStreamEventToChatMsg`.
  - `LlmClient.tryEmitSseDelta` forwards parsed `StreamEvent` objects through regular and final SSE buffer processing.
  - `ReplyService`, `ConversationWorkflow`, `AgentChatService`, and `AgentFloatWindow` now forward/consume `StreamEvent` objects without filtering out thinking events.
- ArkTS strict check after US1/US3 implementation group: `arkts_check` on 13 changed `.ets` files returned no errors.
- US2 final-answer separation completed:
  - Seam A regression asserts reasoning-only payload emits one `thinking` event and zero `text` events.
  - Seam B regression asserts thinking/text events remain separated in `ChatMsg.reasoning` and `ChatMsg.content`.
  - Removed SSE reasoning-to-content masquerade in `LlmClient.parseStreamEventsFromSseData`; `reasoning_content` no longer emits a fallback text event.
  - `ReplyService.stream` accumulates final answer `content` only for `event.type === 'text'`; thinking events are forwarded but not persisted as final answer text.
  - `ConversationWorkflow` appends fallback and interruption UI deltas as `text` events, and saves `streamResult.content` only, preserving text-only persistence.
- US4 thinking supply default completed:
  - `common/src/main/ets/llm/LlmConfig.ets` now exports `DEFAULT_ENABLE_THINKING = true`.
  - Runtime cache initial value, preferences load fallback, and `resetDefaults()` persisted default now use `DEFAULT_ENABLE_THINKING`.
  - Removed explicit `enableThinking: false` overrides from `ReplyService.complete`, `ReplyService.stream`, and `ReplyService.fallback` paths, so LlmClient config fallback controls thinking supply.
  - Seam A config test asserts `DEFAULT_ENABLE_THINKING` and current singleton fallback are enabled.
- US5 regression lock evidence:
  - `common/src/test/LlmStreamEvents.test.ets` covers reasoning-only, text-only, both-fields thinking-before-text, null delta, empty choices, no reasoning-to-text fallback, four event categories, and default thinking behavior.
  - `entry/src/test/AgentChatStreamEvents.test.ets` covers thinking-to-reasoning, text-to-content, ordered separation, and reserved tool-event safe ignore.
  - `arkts_check` on all changed source/test `.ets` files returned: `No errors found in 13 file(s).`
  - `devecocli check lint` was attempted for the new Seam A/B test files and key changed source files. It reported `No defects found` but also `Files checked: 0`; therefore it is recorded as non-authoritative compared with `arkts_check` and the final project lint/test sweep.
  - Direct Hypium single-test execution was not available in this API session without invoking build/deploy-style verification tooling. The new tests were wired into `common/src/test/List.test.ets` and `entry/src/test/List.test.ets` for the next test/build-capable phase.

## Final scoped staging list

Reviewed with `git status --short`, `git diff --name-status`, and `git diff --check`.

Stage these #111 implementation files:

- `common/src/main/ets/llm/LlmTypes.ets`
- `common/src/main/ets/llm/LlmClient.ets`
- `common/src/main/ets/llm/LlmConfig.ets`
- `common/src/main/ets/Index.ets`
- `common/src/test/LlmStreamEvents.test.ets`
- `common/src/test/List.test.ets`
- `entry/src/main/ets/services/ReplyService.ets`
- `entry/src/main/ets/services/AgentChatService.ets`
- `entry/src/main/ets/workflows/conversation/ConversationTypes.ets`
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`
- `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets`
- `entry/src/test/AgentChatStreamEvents.test.ets`
- `entry/src/test/List.test.ets`
- `spec/019-reasoning-process-display-p0/tasks.md`
- `spec/019-reasoning-process-display-p0/delivery-checklist.md`
- `spec/019-reasoning-process-display-p0/review-report.md`

If the main agent wants the full SDD bundle in one commit and those files are not already tracked elsewhere, also stage:

- `spec/019-reasoning-process-display-p0/spec.md`
- `spec/019-reasoning-process-display-p0/plan.md`

Do not stage these unrelated pre-existing files:

- `docs/research/frontend-component-audit-2026-09-06.md`
- `docs/research/arkweb-render-pipeline-stability-2026-09-11.md`
- `entry/src/main/ets/shared/atoms/WebKeepAlive.ets`
- `spec/feature.json`

## Implementation summary

- Implemented the structured stream protocol vertical slice for issue #111.
- Common LLM layer now defines a forward-compatible `StreamEvent` family (`thinking`, `text`, `tool_call`, `tool_result`), exports it, and converts SSE `reasoning_content` / `content` into ordered structured events.
- Removed the old reasoning-to-content masquerade fallback from SSE parsing and non-stream content extraction.
- Entry chat stream path now carries `StreamEvent` objects through `ReplyService`, `ConversationWorkflow`, `AgentChatService`, and `AgentFloatWindow`.
- `thinking` events update `ChatMsg.reasoning`; `text` events update `ChatMsg.content`; reserved `tool_*` events are ignored safely in P0.
- `ReplyService.stream` accumulates final answer content from `text` events only, so persisted streamed assistant content excludes thinking text.
- Thinking supply defaults are now enabled through `DEFAULT_ENABLE_THINKING`, preferences fallback, reset defaults, and removal of ReplyService explicit false overrides.
- Seam A and Seam B tests were added and wired into module test entry points.

## Polish validation evidence

- `node scripts/arkts-lint/index.mjs --quiet`: passed; no output.
- `npm --prefix scripts/arkts-lint test`: passed; 80 tests, 80 pass, 0 fail.
- `node scripts/naming-lint/index.mjs`: passed; 0 violations.
- `git diff --check`: passed; no whitespace errors.
- `git diff --name-status`: reviewed; only #111 source/test/SDD files listed above should be staged. One unrelated tracked research doc remains dirty and is excluded.
