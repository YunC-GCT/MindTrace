// 路径: scripts/arkts-lint/tests/v7-app-intent.test.mjs
// 职责: App 内 agent 统一意图契约——多意图规则、否定/指代不明、低置信追问、Workflow 接线。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const rules = loadNoteReviewEtsModule('agents/src/main/ets/chat/AppIntentRules.ets');
const local = (text, hasImage = false) => rules.classifyAppIntentLocal(text, hasImage);

test('显式「存笔记/整理成笔记」→ note_generate；「不要存」→ chat', () => {
  assert.equal(local('存笔记：矩阵的秩等于行秩').kind, 'note_generate');
  assert.equal(local('帮我把这道题整理成笔记保存').kind, 'note_generate');
  assert.equal(local('不要整理，直接给我讲讲洛必达法则').kind, 'chat');
  assert.equal(local('别存，我只想知道答案').kind, 'chat');
});

test('复习/查询意图不再落到 chat', () => {
  assert.equal(local('今天该复习什么？').kind, 'review');
  assert.equal(local('考考我二次函数').kind, 'review');
  assert.equal(local('把我之前记的极限题找出来').kind, 'note_query');
  assert.equal(local('笔记里有没有泰勒公式').kind, 'note_query');
});

test('图片意图：无文字追问、讲解 vs 整理区分', () => {
  assert.equal(local('', true).kind, 'clarify');
  assert.equal(local('[图片]', true).kind, 'clarify');
  assert.equal(local('这题怎么做', true).kind, 'image_explain');
  assert.equal(local('帮我把这张图整理成笔记', true).kind, 'image_note');
  assert.equal(local('帮我看看这个', true).kind, 'clarify');
});

test('指代不明/含糊请求 → clarify 追问，而不是猜', () => {
  assert.equal(local('帮我看看这个').kind, 'clarify');
  assert.equal(local('整理一下').kind, 'clarify');
});

test('普通问答应交给 LLM 兜底（local undefined），低置信转 clarify', () => {
  assert.equal(local('洛必达法则为什么能把极限算出来？'), undefined);
  assert.equal(local('证明根号2是无理数'), undefined);
  const low = rules.parseAppIntentJson({ intent: 'note_generate', confidence: 0.4, reason: 'maybe' });
  assert.equal(low.kind, 'clarify');
  const high = rules.parseAppIntentJson({ intent: 'review', confidence: 0.9, reason: 'review' });
  assert.equal(high.kind, 'review');
  assert.match(rules.buildAppIntentPrompt(), /clarify/);
  assert.match(rules.buildAppIntentPrompt(), /image_note/);
});

test('Workflow 接线：统一意图 + clarify 节点 + 状态透传', () => {
  const workflow = read('agents/src/main/ets/conversation/ConversationWorkflow.ets');
  assert.match(workflow, /appIntentRouter\.classify\(/);
  assert.match(workflow, /graph\.addNode\('clarify_reply'/);
  assert.match(workflow, /appIntentClarify === true/);
  assert.match(workflow, /clarifyPrompt\(hasImage\)/);
  const state = read('agents/src/main/ets/conversation/ConversationState.ets');
  assert.match(state, /appIntent\?: string/);
  assert.match(state, /appIntentClarify\?: boolean/);
  const router = read('agents/src/main/ets/chat/AppIntentRouter.ets');
  assert.match(router, /AppIntentRouter\.trace\(decision, hasImage\)/);
  assert.match(router, /kind: 'chat', source: 'fallback'/);
});
