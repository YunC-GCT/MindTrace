import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const statePath = resolve(root, 'skill/src/main/ets/workflows/intent/SkillIntentState.ets');
const workflowPath = resolve(root, 'skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets');
const routerPath = resolve(root, 'skill/src/main/ets/workflows/intent/IntentRouter.ets');

test('Skill intent uses a typed workflow state and shared StateGraph runtime', () => {
  assert.ok(existsSync(statePath));
  assert.ok(existsSync(workflowPath));
  const state = read('skill/src/main/ets/workflows/intent/SkillIntentState.ets');
  const workflow = read('skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets');
  assert.match(state, /interface SkillIntentState/);
  assert.match(state, /interface SkillIntentRequest/);
  assert.match(state, /interface SkillIntentResult/);
  assert.match(workflow, /StateGraph<SkillIntentState, SkillIntentStep>/);
  assert.match(workflow, /addConditionalEdge\('route_action'/);
});

test('SearchNote reuses the unique note_query tool and other actions reject explicitly', () => {
  const workflow = read('skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets');
  assert.match(workflow, /registry\.execute\('note_query', input\.request\.argsJson\)/);
  assert.match(workflow, /UNSUPPORTED_INTENT/);
  assert.doesNotMatch(workflow, /new NoteDao|new Dispatcher|new LlmClient/);
  assert.doesNotMatch(workflow, /new NoteQueryTool|new ToolRegistry/);
});

test('IntentRouter normalizes only SearchNote parameters without guessing other actions', () => {
  assert.ok(existsSync(routerPath));
  const router = read('skill/src/main/ets/workflows/intent/IntentRouter.ets');
  assert.match(router, /ohos\.intent\.action\.SearchNote/);
  assert.match(router, /keyword/);
  assert.match(router, /subject/);
  assert.match(router, /reviewStatus/);
  assert.match(router, /target: 'search_note'/);
  assert.match(router, /target: 'unsupported'/);
});

test('SkillAbility delegates to the workflow and returns a typed result', () => {
  const ability = read('skill/src/main/ets/skillability/SkillAbility.ets');
  assert.match(ability, /DatabaseHelper\.init\(this\.context\)/);
  assert.match(ability, /new IntentRouter\(\)\.fromWant\(want\)/);
  assert.match(ability, /ToolCatalog\.createReadOnlyRegistry\(\)/);
  assert.match(ability, /new SkillIntentWorkflow\(registry\)/);
  assert.match(ability, /terminateSelfWithResult/);
  assert.doesNotMatch(ability, /TODO|placeholder/);
});

test('skill workflow never imports entry implementation', () => {
  const files = [
    read('skill/src/main/ets/skillability/SkillAbility.ets'),
    read('skill/src/main/ets/workflows/intent/SkillIntentState.ets'),
    read('skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets'),
    read('skill/src/main/ets/workflows/intent/IntentRouter.ets'),
  ];
  for (const source of files) {
    assert.doesNotMatch(source, /from ['"][^'"]*entry/);
  }
});
