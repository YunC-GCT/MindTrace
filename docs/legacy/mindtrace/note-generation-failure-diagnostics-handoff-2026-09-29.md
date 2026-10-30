# Note generation failure diagnostics handoff

> Date: 2026-09-29  
> Scope: conversation-triggered note generation failures, especially `VERIFIER_UNAVAILABLE` / `verifier_unavailable`  
> Branch at handoff: `bugfix/verifier-unavailable-diagnostics`  
> Related fix: `c8a66f0 fix(agents): accept legacy verifier status alias`

## 1. Purpose

Use this document when a note fails to generate and another session needs to determine whether the failure comes from the LLM request, verifier response contract, local artifact validation, or UI error propagation.

The current code can reliably identify the failed stage and stable stop reason. It cannot yet recover the original exception hidden by the independent verifier's catch block. Do not infer an HTTP error, timeout, or schema error from `VERIFIER_UNAVAILABLE` alone.

The investigation is complete only when the session records:

- the reproduction time window and `runId`, if available;
- route, `stopReason`, and issue code;
- the relevant `LlmClient`, `KnowledgeModel`, and `Dispatcher` logs;
- the matching automated-test result;
- whether the failure is an already-covered response-contract case or a new case.

Do not record API keys, authorization headers, full prompts, or full user note contents. Prefer model name, timestamps, response length, field names, issue codes, and redacted excerpts.

## 2. Current known fix

The previously reproduced failure was caused by a verifier response using the legacy top-level field `overallStatus` instead of the canonical `status`:

```json
{
  "overallStatus": "supported",
  "issues": [],
  "evidenceStatuses": []
}
```

The canonical contract is:

```json
{
  "status": "supported",
  "issues": [],
  "evidenceStatuses": []
}
```

Commit `c8a66f0` changed `agents/src/main/ets/agents/KnowledgeModel.ets` so that:

1. `status` is read first.
2. `overallStatus` is accepted only when `status` is absent (`undefined`).
3. An explicitly present but invalid canonical value, such as `"status": null`, is not replaced by the alias.
4. The verifier prompt explicitly requests `status`, `issues`, and `evidenceStatuses`, and forbids aliases.

The relevant methods are:

- `KnowledgeModel.callIndependentVerifier()`
- `KnowledgeModel.readVerifierStatusValue()`
- `KnowledgeModel.parseVerification()`
- `KnowledgeModel.validateIndependentVerifierJson()`

This compatibility fix prevents a known false failure. It does not prove that every future `VERIFIER_UNAVAILABLE` has the same cause.

## 3. What `VERIFIER_UNAVAILABLE` currently means

`KnowledgeModel.callIndependentVerifier()` catches every exception raised while requesting, parsing, and validating the independent verifier result, then emits this stable issue:

```text
stage=verifier
code=VERIFIER_UNAVAILABLE
severity=hard
message=independent verifier did not return a complete result
repairable=false
```

Possible underlying causes include:

- network or HTTP failure;
- request timeout;
- empty or truncated response;
- invalid JSON;
- invalid response schema;
- invalid `status`;
- malformed `issues` or `evidenceStatuses`;
- exhausted JSON/schema retries.

`agents/src/main/ets/core/Dispatcher.ets` maps this issue to:

```text
stopReason=verifier_unavailable
```

The user-facing diagnostic normally has this shape:

```text
standard generation failed: stop=verifier_unavailable; [VERIFIER_UNAVAILABLE] stage=verifier independent verifier did not return a complete result
```

### Stop-reason decision table

| Observed value | Meaning | Next inspection |
|---|---|---|
| `verifier_unavailable` | The verifier call or response contract did not complete | Inspect the same time window in `LlmClient`; determine whether the model returned data; then inspect response field shape if safely reproducible |
| `content_verification_failed` | The verifier completed but reported contradiction/ambiguity, or another verifier-stage hard issue exists | Inspect `generation.issues` and evidence decisions; do not treat this as transport failure |
| `artifact_validation_failed` | Local outline, draft, evidence, reference, or coverage validation failed | Inspect validator issue codes and the generated artifact structure |
| `initial_generation_failed` | Standard-route draft generation failed before verifier completion | Inspect the initial LLM call and standard artifact parsing |
| `initial_deep_generation_failed` | Deep-route draft generation failed | Inspect Dispatcher deep-route diagnostics and the deep generation call |

## 4. Automated tests to use

### 4.1 Verifier behavior tests

The behavior tests live in `entry/src/test/DispatcherNoteGeneration.test.ets` and are registered by `entry/src/test/List.test.ets` through `dispatcherNoteGenerationTest()`.

The three most relevant cases are:

```text
stops before content repair when the independent verifier is unavailable
accepts the legacy overallStatus verifier alias when canonical status is absent
does not let the legacy overallStatus alias override an invalid canonical status
```

They establish the following contract:

- unavailable verifier result returns `success === false`;
- the stop reason is `verifier_unavailable`;
- the verifier is attempted three times by the JSON guard/retry path;
- content repair is not entered after verifier unavailability;
- a response containing only `overallStatus` can still produce a ready preview;
- `status: null` remains invalid even if `overallStatus` is valid.

Run the entry Hypium suite from DevEco Studio. Select the `entry` unit-test/Hypium configuration that executes `entry/src/test/List.test.ets`, then run it on the active emulator/device. Do not describe a Node source-structure test as proof that these ArkTS behaviors executed.

Completion condition:

- all three named cases are present in the run and pass; and
- no existing `dispatcherNoteGenerationTest` case regresses.

If only source inspection is available, record the result as **not device-verified** rather than “tests passed.”

### 4.2 Frontend error-propagation test

The Node test `scripts/arkts-lint/tests/conversation-workflow.test.mjs` contains:

```text
note generation failure delivers its actual reason to the frontend
```

Run only this file:

```powershell
node --test scripts/arkts-lint/tests/conversation-workflow.test.mjs
```

Run the full Node regression suite when finishing a code change:

```powershell
npm --prefix scripts/arkts-lint test
```

Completion condition:

- the targeted file reports zero failures; and
- before delivery, the full suite reports zero failures.

This test proves that `ConversationWorkflow` does not replace the actual note-generation failure with a generic message. It does not execute the verifier request or validate device networking.

## 5. Device log collection

First locate the SDK's `hdc.exe` on the current machine. Do not copy the previous machine's absolute SDK path into repository documentation or scripts. In PowerShell, bind the discovered executable for the current shell:

```powershell
$hdc = '<DevEco SDK>/openharmony/toolchains/hdc.exe'
& $hdc list targets
& $hdc shell hilog --help
```

Confirm that the intended emulator/device is listed before reproducing. Check `hilog --help` on that SDK version instead of assuming every option is supported.

If supported by the current device, clear old logs immediately before reproduction:

```powershell
& $hdc shell hilog -r
```

Start a filtered live capture, then reproduce exactly once:

```powershell
& $hdc shell hilog |
  Select-String -Pattern 'Dispatcher|KnowledgeModel|LlmClient|ConversationRun|verifier_unavailable|VERIFIER_UNAVAILABLE'
```

If the terminal needs a durable capture, redirect the filtered output to a file outside the repository or to an ignored diagnostics directory. Review and redact it before sharing.

Record these facts alongside the capture:

- local timestamp and timezone;
- application build/commit;
- device target and OS/API version;
- route (`standard` or `deep`);
- `runId`, when present;
- visible error message;
- whether the same input fails repeatedly;
- model/vendor identifiers, without credentials.

### Existing log tags and interpretation

| Tag/source | Existing signal | Interpretation |
|---|---|---|
| `[LlmClient]` | vendor/model, non-stream request, response choice/token counts, stream timeout, no-data fallback, stream errors | Establish whether a request started and whether any response arrived |
| `[KnowledgeModel]` | ordinary knowledge-structure calls, response length, and some structure failures | Useful for the main structure call; the independent verifier catch does not currently print its original exception |
| `Logger('Dispatcher')` | generation progress with run, round, stop, and rollback | Correlate the UI failure with one generation run |
| Dispatcher deep diagnostics | deep-route summary and individual issues | Available only when the deep route finishes with an error message |

Completion condition:

- the failing UI event has a matching Dispatcher `runId` or a narrow timestamp window; and
- the investigator can say whether the verifier request had no response, had a malformed/invalid response, or remains indistinguishable with current logging.

If the evidence remains indistinguishable, write “root exception unavailable in current logs”; do not guess.

## 6. Persistence records

`entry/src/main/ets/database/NoteGenerationRepository.ets` persists generation state in:

```text
note_generation_run
note_generation_log
note_generation_checkpoint
```

`note_generation_run` includes status, route, stop reason, issue count, timestamps, and source metadata. A `finished` lifecycle row in `note_generation_log` includes:

```text
run_id
event
checkpoint_id
issue_count
source_count
round
stop_reason
rollback
created_at
```

Use DevEco Studio's database inspection capability to inspect these tables on the reproduction device when available. Filter by the `runId` found in the Dispatcher log or by the narrow reproduction time window.

There is currently no public `listLifecycleLogs()` API on `NoteGenerationRepository`. Do not claim that the app already exposes lifecycle-log querying. If programmatic querying becomes necessary, add a minimal read-only diagnostic seam with tests; do not add a production mutation or dump complete source content.

Completion condition:

- the `note_generation_run.stop_reason` agrees with the UI/Dispatcher result; and
- the matching `finished` lifecycle row is present, or its absence is explicitly recorded as a separate persistence problem.

## 7. Recommended investigation order

1. Record the visible error, exact reproduction time, route, and repeatability.
2. Capture filtered `hilog` output while reproducing once.
3. Identify `runId`, `stopReason`, and issue code from Dispatcher/UI output.
4. Use the decision table in section 3 to select the failing stage.
5. For `verifier_unavailable`, correlate the same time window with `LlmClient` and determine whether a response arrived.
6. Inspect `note_generation_run` and `note_generation_log` by `runId` or timestamp.
7. Run the targeted Node error-propagation test.
8. Run the three Hypium verifier behavior cases on the active device.
9. Compare the observed response contract with the `status` / `overallStatus` cases already covered.
10. Only after the failure category is proven, write a new red test for the smallest missing behavior before changing production code.

The handoff is diagnosis-ready when the next session can answer all of these questions:

- Did the main draft generation finish?
- Did the independent verifier request start?
- Did it return any response?
- Was the response parseable and contract-valid?
- Which retry attempt failed?
- What stable issue code and stop reason reached the UI?
- Did the run and lifecycle records persist the same outcome?

## 8. Known diagnostic blind spots

### 8.1 Verifier root exception is folded

The catch in `KnowledgeModel.callIndependentVerifier()` converts every original verifier exception to `VERIFIER_UNAVAILABLE` without logging the original error. Therefore the current runtime cannot reliably distinguish HTTP failure, timeout, JSON parse failure, and schema rejection from that issue alone.

Recommended follow-up, if a new reproduction cannot be classified:

- add one red behavior test for safe diagnostic classification;
- log a sanitized reason category at the catch boundary, such as `transport`, `timeout`, `empty`, `json_parse`, or `schema`;
- include `runId` or another correlation identifier without logging prompt/source contents;
- preserve the public issue code and user-facing message unless a product decision changes them.

### 8.2 Standard-route diagnostics are less detailed

`Dispatcher.finishStandardGeneration()` emits detailed diagnostic summaries and individual issue logs only when `route === 'deep'` and an `errorMessage` exists. A standard-route `verifier_unavailable` therefore does not receive the same detailed Dispatcher diagnostics.

For the standard route, rely on:

- `generation.stopReason`;
- `generation.issues` and the propagated error message;
- generation progress logs;
- `note_generation_run` and `note_generation_log`;
- the correlated `LlmClient` time window.

If enhanced logging is implemented, first add a test that requires sanitized standard-route diagnostic metadata and explicitly rejects prompt, source-text, token, and credential leakage.

## 9. Report template for the next session

```text
Build/commit:
Device/API:
Reproduction time (Asia/Shanghai):
Input description (redacted):
Route:
Run ID:
Visible error:
Stop reason:
Issue codes:
LLM request observed: yes/no
LLM response observed: yes/no/unknown
Response contract category: valid/alias/invalid JSON/invalid schema/unknown
Verifier attempts observed:
RDB run row found: yes/no
RDB finished lifecycle row found: yes/no
Targeted Node test:
Hypium verifier tests:
Conclusion:
Missing evidence / next red test:
```

## 10. Files to inspect first

- `agents/src/main/ets/agents/KnowledgeModel.ets`
- `agents/src/main/ets/core/Dispatcher.ets`
- `entry/src/main/ets/database/NoteGenerationRepository.ets`
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`
- `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets`
- `entry/src/test/DispatcherNoteGeneration.test.ets`
- `entry/src/test/List.test.ets`
- `scripts/arkts-lint/tests/conversation-workflow.test.mjs`

