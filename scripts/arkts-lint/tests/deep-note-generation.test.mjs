import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const ROOT = path.resolve(import.meta.dirname, '..', '..', '..')
const read = (relativePath) => fs.readFileSync(path.join(ROOT, relativePath), 'utf8')

test('Issue 103 wires a real deep route through Dispatcher and KnowledgeModel', () => {
  const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets')
  const model = read('agents/src/main/ets/agents/KnowledgeModel.ets')
  const contracts = read('common/src/main/ets/models/NoteGenerationModels.ets')

  assert.match(dispatcher, /route === 'deep'/)
  assert.match(dispatcher, /dispatchDeepGeneration/)
  assert.match(dispatcher, /structureDeepDraft/)
  assert.match(dispatcher, /repairDeepDraft/)
  assert.match(dispatcher, /deepMergeIssues/)
  assert.doesNotMatch(dispatcher, /DEEP_ROUTE_UNSUPPORTED/)
  assert.match(model, /segmentSourceBundle/)
  assert.match(model, /callDeepSectionDraft/)
  assert.match(model, /shared ledger/)
  assert.match(contracts, /interface NoteGenerationDeepResult/)
  assert.match(contracts, /maxSourceChars\?: number/)
})

test('Issue 103 deep source selection is semantic, not arbitrary truncation', () => {
  const models = read('common/src/main/ets/models/NoteGenerationModels.ets')
  const knowledgeModel = read('agents/src/main/ets/agents/KnowledgeModel.ets')

  assert.match(models, /boundary: 'message' \| 'ocr_page' \| 'heading'/)
  assert.match(models, /formula_block/)
  assert.match(models, /derivation/)
  assert.match(knowledgeModel, /outlineSection\.segmentIds\.includes\(segment\.id\)/)
  assert.doesNotMatch(knowledgeModel, /outlineSection\.sourceIds\.includes\(segment\.sourceId\)/)
})
