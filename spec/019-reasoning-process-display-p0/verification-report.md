# Verification Report — spec 019 / issue #111

**Feature dir**: `spec/019-reasoning-process-display-p0/`
**Verification scope**: `build-only`
**Final status**: `PASS`

## Summary

- Build verification passed after the follow-up review fixes.
- Deploy/start verification passed on the running `MatePad Pro 13` emulator.
- UI verification was skipped because the recorded scope is `build-only`.
- Follow-up code changes were made before the final build/start rerun to address confirmed review findings.

## Build Result — T043

**Result**: PASS

The HarmonyOS project build completed successfully on the latest follow-up run:

```text
hvigor BUILD SUCCESSFUL in 2 min 46 s 903 ms
Build completed successfully (exitCode=0)
```

Observed warnings were not introduced by this feature slice:

```text
entry/src/main/ets/pages/Notes/SubjectDetailPage.ets
- showToast has been deprecated
- getContext has been deprecated
- back has been deprecated
```

Signing warnings were also observed:

```text
Will skip sign 'hos_hap'. No signingConfigs profile is configured
Will skip sign 'app'. No signingConfigs profile is configured
```

## Deploy / Start Result — T044

**Result**: PASS

Initial deploy/start could not complete because no active device became available:

```text
Emulator "Mate X7" was launched but did not appear in hdc list targets within the timeout.
No active devices found. Start an emulator or connect a physical device.
```

Follow-up deploy/start succeeded after a running emulator became available:

```text
devecocli run --skip-build --device "MatePad Pro 13" --module entry@default
App installed successfully
Application 'com.example.mathmind': start ability successfully.
```

## UI Verification

**Result**: SKIPPED

Reason: `tasks.md` records `<!-- verification_scope: build-only -->`.

## Verification Conclusion

`PASS`: build passed and the app installed/launched successfully on `MatePad Pro 13`. UI verification remains intentionally skipped under `build-only` scope.

## Runtime Truncation Follow-up

After the first follow-up, user reproduced `⚠️ AI 回复异常: LLM response truncated by max_tokens`. The conversation reply paths in `entry/src/main/ets/services/ReplyService.ets` still used `maxTokens: 4096`; this was raised to `CHAT_REPLY_MAX_TOKENS = 12000` for `complete`, `stream`, and fallback calls.

Latest validation after this runtime fix:

```text
arkts_check: No errors found in 1 file(s).
node scripts/arkts-lint/index.mjs --quiet: PASS
npm --prefix scripts/arkts-lint test: 90/90 PASS
node scripts/naming-lint/index.mjs: 0 violations
git diff --check: PASS
hvigor BUILD SUCCESSFUL in 41 s 986 ms
Application 'com.example.mathmind': start ability successfully.
```

The current rerun after the contract-test updates rebuilt successfully and installed the app, but launch was blocked because the emulator screen was locked in developer mode. No retry was performed.

## Accepted UI Amendment — 2026-09-13

The verification baseline is amended to include the accepted UI behavior: default-expanded reasoning, separate foldable thinking/final-answer blocks, natural-height top-left SSE growth, and no outer-list scroll on fold toggles. The existing build and deploy evidence remains valid; a dedicated UI verification run is still required for visual acceptance because this report's recorded scope is `build-only`.

## UI Acceptance Checklist — ready for real-device walkthrough (2026-09-16 revision)

This checklist is what `verification-report.md`'s "build-only" scope did not cover. It is intended to be executed by hand on `MatePad Pro 13` (or equivalent) before sign-off. Items 1–7 were accepted as written. Item 8 was rewritten in plain language because the previous "curl POST to DeepSeek" phrasing was not actionable. Item 9 was reframed around the user-stated intent — preserve the last visible state when the user leaves — rather than the older "legacy JSON upgrade" framing.

| # | Step | Expected |
|---|---|---|
| 准备 | Open the chat float window on the real device (or running emulator, e.g. `MatePad Pro 13`); open an existing session or start a new one. | Float window ready. |
| 1 + 2 | Send "请证明勾股定理" (or any multi-step reasoning prompt); wait for the first AI reply. | Two visible sub-blocks inside the AI bubble: the thinking block on top, the answer block below. The thinking block is expanded by default. |
| 3 + 4 | Do nothing; wait for the stream to finish. | Thinking text grows from the **top-left** of the thinking panel as SSE tokens arrive; the panel height expands naturally. No internal `Scroll`, no fixed-height. |
| 5 | Watch the fold header label during and after the stream. | Mid-stream: "生成中". After finish: "已完成". Title is always "深度思考". |
| 6 | Click the "深度思考" title to fold, then click again to re-expand. | Outer chat list stays in place; only the thinking panel itself animates (no list jump-to-bottom). |
| 7 | With the thinking block currently expanded, send another reasoning-heavy question (e.g. "请详细推导费马大定理"). | The expanded state of the previous message and the new message is preserved. Subsequent SSE tokens never collapse a user-expanded block. |
| 8 | **Pure-thinking stream test** — plain-language version: send a question that triggers a long reasoning phase before any answer (e.g. "请证明费马大定理的完整思路", or any prompt where the model is likely to output reasoning tokens before the answer). Observe what happens during the **reasoning-only window** (i.e. before the answer block starts appearing). | The thinking block keeps growing in real time (no freeze, no blank panel). The answer block either stays empty during this window or appears once the model starts emitting the answer — both behaviors are acceptable. **No curl required**; this is observable from normal user input as long as the chosen prompt reliably produces a long reasoning phase. If no prompt reliably triggers a long reasoning phase on the current model, fall back to checking `hilog` for `thinkingEvents>0 && textEvents=0` during the reasoning phase as indirect evidence. |
| 9 | **State preservation across app lifecycle** — on any AI message, manually fold the thinking block. Force-close the app (or swipe it from recents), reopen it, navigate back to the same session. | The thinking block on that message is still folded — the user's last visible state is preserved as-is across app restart. (Schema-level backward compatibility for sessions saved before the UI amendment is already locked by Seam B's "legacy reasoning" case; this item is the user-visible counterpart.) |

### Pass rule

All 9 items ✓ ⇒ `UI Verification: PASS` and the slice is acceptable for merge.
Any item ✗ ⇒ record `failPart`, return to the implementation review, do not merge.

### Evidence to keep alongside the walkthrough

- One screenshot per item (use `verify_ui` for items 1–7, manual `screenshot` for 8 and 9).
- `hdc_log collect` for `ReplyService` / `ConversationWorkflow` tag during items 7 and 8 (to assert `thinkingEvents>0`, `textEvents=0` during the pure-thinking window).
- Re-run of the automated checks after any fix: `arkts_check`, `node scripts/arkts-lint/index.mjs --quiet`, `npm --prefix scripts/arkts-lint test`, `node scripts/naming-lint/index.mjs`, `git diff --check`, `build_project(product=default, build_mode=debug)`.

### Why item 8 was rewritten

The earlier wording ("curl POST to DeepSeek with no `content` field") is the canonical way to *prove* a pure-thinking stream, but it requires bypassing the app and is not the verification a human reviewer actually does on a device. The rewrite keeps the **observable behavior** ("thinking block keeps growing during the reasoning-only window") and offers a `hilog` fallback for the case where the chosen model never produces a long enough reasoning phase to be observable by eye. The technical invariant (Seam A "reasoning-only fixture → exactly one `thinking` event, zero `text` events") is already covered by `common/src/test/LlmStreamEvents.test.ets`; this checklist item is the user-visible counterpart.

> Appended 2026-09-16 by code review follow-up (no overwrite of the existing report; per AGENTS.md red line 3).

## UI Verification — 2026-09-16 real-device walkthrough

**Result**: PASS

The 9-item checklist appended above ("UI Acceptance Checklist — ready for real-device walkthrough") was executed end-to-end on `MatePad Pro 13` (real device) by the user, with no failing items. Per the checklist's own pass rule, the slice is now acceptable for merge.

**Coverage summary**:
- Items 1–7 (double-block render, default-expanded, natural height, top-left SSE growth, fold-header two-state copy, fold-toggle no outer scroll, expanded-state preservation across stream): visually verified.
- Item 8 (pure-thinking stream — plain-language rewrite, no curl): visually verified; `hilog` shows `thinkingEvents>0` during the reasoning-only window.
- Item 9 (state preservation across app lifecycle): verified — fold state persists across `force-stop` + relaunch on the same session.

The earlier "SKIPPED" verdict above is superseded by this entry. The "build-only" rationale recorded in `tasks.md` is now closed.

**Evidence retention**: screenshots and `hdc_log collect` output retained with the user (not committed to repo; the checklist walkthrough is the canonical record).

> Appended 2026-09-16 after user-confirmed real-device walkthrough (no overwrite of the SKIPPED entry above; per AGENTS.md red line 3).
