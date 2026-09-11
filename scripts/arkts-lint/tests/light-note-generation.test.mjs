import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const ROOT = path.resolve(import.meta.dirname, '..', '..', '..')

const read = (relativePath) => fs.readFileSync(path.join(ROOT, relativePath), 'utf8')

test('Issue 98 exposes typed light generation through Dispatcher.dispatch', () => {
  const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets')
  const models = read('common/src/main/ets/models/NoteGenerationModels.ets')

  assert.match(models, /interface NoteGenerationRequest/)
  assert.match(models, /interface SourceFragment/)
  assert.match(models, /interface NoteDraftDocument/)
  assert.match(models, /interface NoteGenerationCheckpoint/)
  assert.match(models, /interface NoteGenerationResult/)
  assert.match(dispatcher, /NoteGenerationRequest/)
  assert.match(dispatcher, /persist:\s*false/)
  assert.doesNotMatch(dispatcher, /NoteGenerationRepositoryImpl/)
})

test('Issue 98 repository persists recoverable artifacts without a second note DAO', () => {
  const repository = read('entry/src/main/ets/database/NoteGenerationRepository.ets')
  const database = read('common/src/main/ets/DatabaseHelper.ets')

  assert.match(repository, /implements NoteGenerationRepository/)
  assert.match(repository, /saveRun/)
  assert.match(repository, /saveCheckpoint/)
  assert.match(repository, /restore/)
  assert.match(repository, /note_generation_source/)
  assert.match(database, /note_generation_run/)
  assert.match(database, /note_generation_source/)
  assert.match(database, /note_generation_checkpoint/)
  assert.doesNotMatch(repository, /knowledge_unit/)
})

test('Issue 98 keeps provider adaptation in the single LlmClient transport', () => {
  const knowledgeModel = read('agents/src/main/ets/agents/KnowledgeModel.ets')
  const llmClient = read('common/src/main/ets/llm/LlmClient.ets')
  const providers = read('common/src/main/ets/llm/providers.ets')

  assert.match(knowledgeModel, /structureLightDraft/)
  assert.match(knowledgeModel, /\.call\(/)
  assert.match(llmClient, /responseFormat/)
  assert.match(providers, /strictStructuredOutput/)
  assert.match(providers, /strictStructuredOutput\?: boolean/)
})
