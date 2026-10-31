import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const root = path.resolve(import.meta.dirname, '..', '..', '..')
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')

test('Issue 104 keeps incremental regeneration behind the four agreed seams', () => {
  const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets')
  // 2026-10-31：增量分支抽到 IncrementalBranch，Dispatcher 只留路由委托。
  const incrementalBranch = read('agents/src/main/ets/core/dispatch/IncrementalBranch.ets')
  const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets')
  const facade = read('entry/src/main/ets/services/AgentChatService.ets')
  const repository = read('entry/src/main/ets/database/NoteGenerationRepository.ets')
  const writer = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets')
  const model = read('agents/src/main/ets/agents/KnowledgeModel.ets')
  const models = read('common/src/main/ets/models/NoteGenerationModels.ets')

  assert.match(dispatcher, /IncrementalBranch\.dispatchIncrementalGeneration/)
  assert.match(incrementalBranch, /dispatchIncrementalGeneration/)
  assert.match(incrementalBranch, /NOTE_ID_REQUIRED/)
  assert.match(incrementalBranch, /VERSION_CONFLICT/)
  assert.match(incrementalBranch, /mergeIncrementalPatches/)
  assert.match(workflow, /regenerateNote/)
  assert.match(workflow, /请先选择要修改的明确笔记/)
  assert.doesNotMatch(facade, /requestRegeneration/)
  assert.match(workflow, /requestRegeneration/)
  assert.match(repository, /getRegenerationBase/)
  assert.match(repository, /queryLatestGeneratedRevision/)
  assert.match(writer, /updateWithCommitKey/)
  assert.match(model, /repairIncrementalSections/)
  assert.match(model, /this\.incrementalPatchComposer\.compose\(request, plan, sections, sources\)/)
  assert.match(read('agents/src/main/ets/agents/IncrementalPatchComposer.ets'), /never return a full document/)
  assert.match(models, /IncrementalManifest/)
  assert.match(models, /LOCKED_SECTION_CHANGED/)
})

test('Issue 104 does not add a second persistence owner', () => {
  const repository = read('entry/src/main/ets/database/NoteGenerationRepository.ets')
  const adapter = read('entry/src/main/ets/adapters/NoteDaoAdapter.ets')
  assert.doesNotMatch(repository, /knowledge_unit/)
  assert.match(adapter, /service\.updateWithCommitKey/)
})

test('incremental regeneration uses the same coarse progress contract', () => {
  const incrementalBranch = read('agents/src/main/ets/core/dispatch/IncrementalBranch.ets')
  const incremental = incrementalBranch.slice(
    incrementalBranch.indexOf('static async dispatchIncrementalGeneration'),
    incrementalBranch.indexOf('static incrementalResult'),
  )

  assert.match(incremental, /activity: 'collect_sources'/)
  assert.match(incremental, /activity: 'repair_draft'/)
  assert.match(incremental, /activity: 'check_accuracy'/)
  assert.match(incremental, /state: 'success'/)
})
