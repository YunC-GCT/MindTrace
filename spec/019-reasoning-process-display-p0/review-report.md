# Review Report — spec 019 P0 / issue #111 StreamEvent vertical slice

## Reference point and capability note

- Review reference point: current branch `feature/spec-019-p0` against `HEAD` at start of implementation (`38955f7 docs(specs): refine spec 019 bubble structure to attachment-style single fold`).
- Diff inspected: working-tree implementation diff for #111 source, test, and SDD artifact files.
- Requested reviewer preference: `GLM-5.3` with reasoning strength `max`.
- Capability limitation: the available `code-review` skill in this API session exposes no model-selection or reasoning-strength parameter, and there is no separate model-switching control for the skill. Therefore `GLM-5.3/max` could not be selected or verified.
- Alternate review path used: loaded the `code-review` skill, inspected the implementation diff manually against the documented standards (`AGENTS.md`, `docs/style/arkts-1.1.md`, `docs/adr/0015-structured-stream-events.md`) and spec requirements (`spec/019-reasoning-process-display-p0/spec.md`, `plan.md`, `tasks.md`). Tool evidence also included `arkts_check`, project ArkTS lint, lint unit tests, and naming lint.

## Standards review

- Result: no blocking standards findings in #111 scoped files.
- ArkTS strict constraints checked:
  - No remaining old `(delta, kind)` stream callback shape in scoped `.ets` files.
  - No explicit `enableThinking: false` override remains in the scoped reply path.
  - `arkts_check` on changed source/test files reported no errors.
  - Project ArkTS lint scan completed with no reported #111 findings.
- Scope hygiene checked:
  - Existing unrelated dirty/untracked files are documented in `delivery-checklist.md` and excluded from the recommended #111 staging list.

## Spec review

- Result: no blocking spec findings found.
- FR-001/FR-002: `StreamEvent` family covers `thinking`, `text`, `tool_call`, and `tool_result`; parser emits P0 `thinking`/`text` from `reasoning_content`/`content`.
- FR-003: SSE reasoning-to-content fallback emission was removed; reasoning-only stream chunks produce no `text` event.
- FR-004/FR-007: existing `ChatMsg.reasoning` and `ChatMsg.content` fields are used; no persisted model field addition was introduced.
- FR-005: reserved `tool_call` / `tool_result` events are safely ignored by the ChatMsg dispatch helper in P0.
- FR-006: default thinking behavior is enabled and ReplyService no longer forces it off.
- FR-008/FR-009: Seam A and Seam B test files were added and wired into module test entry points.
- FR-010: build/deploy verification is intentionally not run in this implementation phase; T043-T044 remain for `spec-verify`.

## Findings

- Standards: 0 blocking findings.
- Spec: 0 blocking findings.

## Follow-up two-axis review resolution

- Follow-up review reference point: `38955f7...HEAD` after commit `2990579 feat(llm): add structured stream events for reasoning display`.
- Confirmed Standards H1: the two new `.ets` test files only had short line comments and missed the required file-header fields. Fixed by adding full headers to `common/src/test/LlmStreamEvents.test.ets` and `entry/src/test/AgentChatStreamEvents.test.ets`.
- Confirmed Standards J1: `applyStreamEventToChatMsg` was a `ChatMsg` reducer living in `AgentChatService`. Fixed by moving it next to `ChatMsg` in `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets`.
- Confirmed Spec C1: changing stream fallback from blank final-answer content to any received event would allow thinking-only streams to save an empty assistant answer. Fixed by restoring blank-content fallback through `ReplyService.shouldUseFallback()` while still keeping thinking events separate from final answer text.
- Confirmed Spec C2: fallback stream content bypassed `ReplyService.normalize()` before append/save. Fixed by normalizing fallback display and persisted content in `ConversationWorkflow`.
- Confirmed Spec A2 as residual integration coverage gap: Seam B unit tests cover the shared reducer used by UI callbacks; device-backed adapter integration remains for future acceptance.
- Confirmed Spec C3 during initial review, then resolved after a running emulator became available: deploy/start passed on `MatePad Pro 13`, so T044 is complete.
- Runtime diagnosis: `⚠️ AI 回复异常: LLM response truncated by max_tokens` is anchored in `LlmClient` non-stream JSON handling and the conversation path's fixed `maxTokens: 4096`; the root condition predates #111, while default thinking can increase token pressure. This gotcha is recorded in `AGENTS.md`.

## Runtime truncation follow-up

- User reproduced `⚠️ AI 回复异常: LLM response truncated by max_tokens` after the first follow-up, proving that diagnosis-only was insufficient.
- Confirmed actual trigger: `ReplyService.complete`, `ReplyService.stream`, and `ReplyService.fallback` still passed `maxTokens: 4096`, while `LlmClient` throws on non-stream `finish_reason === 'length'`.
- Fixed by replacing the hardcoded 4096 budget with `CHAT_REPLY_MAX_TOKENS = 12000` for all chat reply paths.

## Notes for later verification

- Direct Hypium runtime execution was not available without entering verification/build territory; the next phase should execute the module test/build path and T043-T044.
