# Note Generation Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use task-by-task execution with a failing test before each code change. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AI conversation note generation stable for light, standard, and deep routes by moving unreliable structural fields from model-only output to deterministic pipeline fallbacks.

**Architecture:** Keep the public generation flow unchanged: `ConversationWorkflow -> AiService -> Dispatcher -> KnowledgeModel`. Add small normalization helpers in `common/src/main/ets/models/NoteGenerationModels.ets` so generation routes call one deep module for draft and evidence repair instead of duplicating fallback logic across UI and dispatcher layers.

**Tech Stack:** HarmonyOS ArkTS 1.1, Hypium tests, MindTrace 5-module HAP/HSP structure, existing hvigor/DevEco validation.

**Spec:** Current bug reports from DevEco Studio emulator testing: `SECTION_EMPTY`, `standard generation requires additional input`, `deep generation requires additional input`, and route pollution from conversation history.

## Global Constraints

- Do not commit or push without explicit user permission.
- Keep changes surgical; do not redesign the whole note-generation workflow.
- Follow ArkTS 1.1 strict rules in `docs/style/arkts-1.1.md`.
- Repository documentation links must remain relative paths.
- Each implementation task must have an independently runnable test or a clear manual verification step.

---

## File Structure

- `common/src/main/ets/models/NoteGenerationModels.ets`: owns typed note-generation contracts and deterministic normalization helpers.
- `common/src/main/ets/Index.ets`: exports new helpers for tests and agents module consumers.
- `agents/src/main/ets/agents/KnowledgeModel.ets`: calls normalization helpers after model JSON parsing.
- `agents/src/main/ets/agents/TruthCheckService.ets`: fixes integral differential detection.
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`: prefers inline material for explicit save requests to reduce context pollution.
- `common/src/test/NoteGenerationModels.test.ets`: regression tests for light fallback and pipeline evidence.
- `agents/src/test/TruthCheckNode.test.ets`: regression test for `du` integral differential.

## Task 1: Light Draft Fallback

**Files:**
- Modify: `common/src/main/ets/models/NoteGenerationModels.ets`
- Modify: `common/src/main/ets/Index.ets`
- Modify: `agents/src/main/ets/agents/KnowledgeModel.ets`
- Test: `common/src/test/NoteGenerationModels.test.ets`

**Interfaces:**
- Produces: `normalizeLightDraft(document: NoteDraftDocument, bundle: SourceBundle): NoteDraftDocument`
- Consumes: `NOTE_DRAFT_SCHEMA_VERSION`, `normalizeDraftCategory`, `SourceBundle`

- [ ] Write a test where a light draft section has empty `id`, `content`, and `sourceIds`.
- [ ] Verify the test fails before implementation.
- [ ] Implement `normalizeLightDraft` so it fills schema, category, section id, label, source ids, and empty content from source text.
- [ ] Call `normalizeLightDraft` inside `KnowledgeModel.structureLightDraft`.
- [ ] Run common note-generation model tests.

## Task 2: Standard Pipeline Evidence Fallback

**Files:**
- Modify: `common/src/main/ets/models/NoteGenerationModels.ets`
- Modify: `common/src/main/ets/Index.ets`
- Modify: `agents/src/main/ets/agents/KnowledgeModel.ets`
- Test: `common/src/test/NoteGenerationModels.test.ets`

**Interfaces:**
- Produces: `buildPipelineEvidence(outline: NoteGenerationOutline, bundle: SourceBundle): NoteGenerationEvidenceItem[]`
- Consumes: normalized outline section source ids.

- [ ] Write a test where an outline has one section and evidence is empty.
- [ ] Verify pipeline evidence contains `origin='pipeline'`, a valid source id, and an excerpt from the source.
- [ ] Implement `buildPipelineEvidence`.
- [ ] In `normalizeStandardResult`, if normalized evidence is empty, replace it with pipeline evidence.
- [ ] Run common note-generation model tests.

## Task 3: Truth Check Differential Detection

**Files:**
- Modify: `agents/src/main/ets/agents/TruthCheckService.ets`
- Test: `agents/src/test/TruthCheckNode.test.ets`

**Interfaces:**
- Keeps existing `TruthCheckService.truthCheck(input: string): MvpTruthCheckResult`.

- [ ] Add a test for `\int ... \varphi(u)\,du=1`.
- [ ] Verify it fails before implementation.
- [ ] Replace `dx`-only detection with a local helper that accepts `dx`, `du`, `dt`, `dy`, and other ASCII-letter differentials.
- [ ] Run truth check tests.

## Task 4: Conversation Inline Material Preference

**Files:**
- Modify: `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`
- Test: focused manual emulator verification.

**Interfaces:**
- Private helper: `preferInlineNoteMaterial(userInstruction: string): string`

- [ ] Add a conservative helper in `ConversationWorkflow`: when the current message contains material after `:` / `：` / newline and that material is at least 8 characters, use it before historical memory.
- [ ] Keep existing memory fallback for messages like `保存这条笔记`.
- [ ] Manually verify that a one-message light test does not include AI assistant history.

## Task 5: Verification

- [ ] Run `node scripts/arkts-lint/index.mjs --quiet`.
- [ ] Run available Hypium/unit tests for changed modules when the local environment supports them.
- [ ] If DevEco emulator is available, verify:
  - light: short concept material produces draft preview.
  - standard: one-formula material produces draft preview or a specific non-evidence error.
  - deep: short proof material no longer fails due to standard evidence or `du` truth check regression.

## Self-Review

- Spec coverage: covers all reported symptoms and keeps OCR untouched.
- Placeholder scan: no task depends on unspecified files or unnamed helpers.
- Type consistency: helper names and signatures are repeated exactly where consumed.
