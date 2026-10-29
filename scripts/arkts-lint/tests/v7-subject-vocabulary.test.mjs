import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// 学科词表接线守卫：分类 agent 必须先复用库里已有的学科，只有确实没见过才新建。
// 任何一个环节断了，词表就静默失效（模型重新发明学科名），所以逐段盯住。

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('PromptBuilder turns the known subjects into a closed vocabulary', () => {
  const prompt = read('agents/src/main/ets/agents/PromptBuilder.ets');
  assert.match(prompt, /buildPrompt\(ocrText: string, knownSubjects: string\[\] = \[\]\): string/);
  assert.match(prompt, /knownSubjects\.join\(' \/ '\)/);
  assert.match(prompt, /必须从这里选/);
  // 词表为空时不能把「必须从这里选：」这种半句话塞给模型
  assert.match(prompt, /knownSubjects\.length > 0/);
});

test('the vocabulary travels from the dispatcher down to the prompt', () => {
  const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');
  const state = read('agents/src/main/ets/graph/AgentState.ets');
  const node = read('agents/src/main/ets/graph/nodes/StructureNode.ets');
  const model = read('agents/src/main/ets/agents/KnowledgeModel.ets');
  const structurer = read('agents/src/main/ets/agents/CaptureStructurer.ets');

  assert.match(dispatcher, /subjectVocabulary\?: string\[\];/);
  assert.match(dispatcher, /subjectVocabulary: options\.subjectVocabulary \?\? \[\]/);
  assert.match(state, /subjectVocabulary\?: string\[\];/);
  assert.match(state, /copied\.subjectVocabulary = input\.subjectVocabulary/);
  assert.match(node, /input\.subjectVocabulary \?\? \[\]/);
  assert.match(model, /knownSubjects: string\[\] = \[\]/);
  assert.match(structurer, /buildPrompt\(ocrText, knownSubjects\)/);
});

test('the entry side reads the vocabulary through a read-only seam, not the write path', () => {
  const ai = read('entry/src/main/ets/services/AiService.ets');
  const vocabulary = read('entry/src/main/ets/services/SubjectVocabularyService.ets');

  assert.match(ai, /SubjectVocabularyService\.list\(\)/);
  assert.doesNotMatch(ai, /new NoteDao\(|from ['"]\.\.\/database\/NoteDao['"]/);
  assert.match(vocabulary, /queryAllMetadata\(\)/);
  assert.match(vocabulary, /subjects\.indexOf\(subject\) < 0/);
});
