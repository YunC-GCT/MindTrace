import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const ROOT = path.resolve(import.meta.dirname, '..', '..', '..')
const read = (relativePath) => fs.readFileSync(path.join(ROOT, relativePath), 'utf8')

test('Issue 103 wires a real deep route through Dispatcher and KnowledgeModel', () => {
  const dispatcher = read('agents/src/main/ets/core/CommandExecutor.ets')
  // 2026-11-02：生成编排已迁入 NoteGenerationWorkflow。
  const branch = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets')
  const model = read('agents/src/main/ets/subagents/DeepDraftComposer.ets')
  const contracts = read('common/src/main/ets/models/NoteGenerationModels.ets')

  assert.match(branch, /route === 'deep'/)
  assert.match(branch, /dispatchDeepGeneration/)
  assert.match(branch, /structureDeepDraft/)
  assert.doesNotMatch(branch, /repairDeepDraft/)
  // 2026-10-31：deepMergeIssues 随评估逻辑抽到 GenerationEvaluator（Dispatcher 只留分支编排）。
  const evaluator = read('agents/src/main/ets/core/dispatch/GenerationEvaluator.ets')
  assert.match(evaluator, /deepMergeIssues/)
  assert.doesNotMatch(dispatcher, /DEEP_ROUTE_UNSUPPORTED/)
  const facade = read('agents/src/main/ets/subagents/KnowledgeModel.ets')
  assert.match(facade, /this\.deepDraftComposer\.compose\(request, progressSink\)/)
  assert.match(model, /segmentSourceBundle/)
  assert.match(model, /callDeepSectionDraft/)
  assert.match(model, /shared ledger/)
  assert.match(contracts, /interface NoteGenerationDeepResult/)
  assert.match(contracts, /maxSourceChars\?: number/)
})

test('Issue 103 deep source selection is semantic, not arbitrary truncation', () => {
  const models = read('common/src/main/ets/models/NoteGenerationModels.ets')
  const knowledgeModel = read('agents/src/main/ets/subagents/DeepDraftComposer.ets')

  assert.match(models, /boundary: 'message' \| 'ocr_page' \| 'heading'/)
  assert.match(models, /formula_block/)
  assert.match(models, /derivation/)
  assert.match(knowledgeModel, /outlineSection\.segmentIds\.includes\(segment\.id\)/)
  assert.doesNotMatch(knowledgeModel, /outlineSection\.sourceIds\.includes\(segment\.sourceId\)/)
})

test('deep generation reports real section and verification activity', () => {
  const dispatcher = read('agents/src/main/ets/core/CommandExecutor.ets')
  const model = read('agents/src/main/ets/subagents/DeepDraftComposer.ets')

  assert.match(model, /progressSink\?: NoteGenerationProgressSink/)
  assert.match(model, /activity: 'write_section'/)
  assert.match(model, /current: sectionIndex/)
  assert.match(model, /total: outline\.sections\.length/)
  assert.match(model, /activity: 'check_accuracy'/)
  assert.doesNotMatch(dispatcher, /repairDeepDraft/)
  const branchSrc = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets')
  assert.match(branchSrc, /structureDeepDraft\(budgetedRequest, context\.domain\.progressSink\)/)
  assert.match(model, /this\.verifier\.verify\(/)
  assert.match(read('agents/src/main/ets/subagents/NoteDraftVerifier.ets'), /evidenceStatuses/)
})

test('deep evidence never fabricates an empty source anchor when an excerpt cannot be located', () => {
  const model = read('agents/src/main/ets/subagents/DeepDraftComposer.ets')

  assert.match(model, /if \(located >= 0\) \{[\s\S]*?refs\.push\(/)
  assert.doesNotMatch(model, /refs\.push\(\{[\s\S]*?excerpt:\s*''/)
  assert.match(model, /sourceRefs: refs/)
})
