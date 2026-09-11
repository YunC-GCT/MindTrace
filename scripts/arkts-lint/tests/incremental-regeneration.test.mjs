import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const root = path.resolve(import.meta.dirname, '..', '..', '..')
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')

test('Issue 104 keeps incremental regeneration behind the four agreed seams', () => {
  const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets')
  const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets')
  const facade = read('entry/src/main/ets/services/AgentChatService.ets')
  const repository = read('entry/src/main/ets/database/NoteGenerationRepository.ets')
  const writer = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets')
  const model = read('agents/src/main/ets/agents/KnowledgeModel.ets')
  const models = read('common/src/main/ets/models/NoteGenerationModels.ets')

  assert.match(dispatcher, /dispatchIncrementalGeneration/)
  assert.match(dispatcher, /NOTE_ID_REQUIRED/)
  assert.match(dispatcher, /VERSION_CONFLICT/)
  assert.match(dispatcher, /mergeIncrementalPatches/)
  assert.match(workflow, /regenerateNote/)
  assert.match(workflow, /请先选择要修改的明确笔记/)
  assert.match(facade, /requestRegeneration/)
  assert.match(repository, /getRegenerationBase/)
  assert.match(repository, /queryLatestGeneratedRevision/)
  assert.match(writer, /updateWithCommitKey/)
  assert.match(model, /repairIncrementalSections/)
  assert.match(model, /never return a full document/)
  assert.match(models, /IncrementalManifest/)
  assert.match(models, /LOCKED_SECTION_CHANGED/)
})

test('Issue 104 does not add a second persistence owner', () => {
  const repository = read('entry/src/main/ets/database/NoteGenerationRepository.ets')
  const adapter = read('entry/src/main/ets/adapters/NoteDaoAdapter.ets')
  assert.doesNotMatch(repository, /knowledge_unit/)
  assert.match(adapter, /service\.updateWithCommitKey/)
})
