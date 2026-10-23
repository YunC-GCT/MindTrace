import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const snapshot = read('entry/src/main/ets/agentextability/TaskSnapshot.ets');
const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');

test('TaskSnapshot exposes the pure single-frame builder signature', () => {
  assert.match(
    snapshot,
    /export function buildTaskSnapshot\(requestId: string, taskId: string, text: string\): string/,
  );
});

test('TaskSnapshot encodes the verified single-frame contract', () => {
  assert.match(snapshot, /TASK_STATE_COMPLETED/);
  assert.match(snapshot, /text\/plain/);
  assert.match(snapshot, /JSON\.stringify/);
  assert.match(snapshot, /artifactId/);
  assert.match(snapshot, /mindtrace-context/);
});

test('TaskSnapshot stays a Kit-free pure function', () => {
  assert.doesNotMatch(snapshot, /@kit\./);
  assert.doesNotMatch(snapshot, /\bfrom\s+['"][^'"]+['"]/);
});

test('AgentExtAbility delegates snapshot assembly to buildTaskSnapshot', () => {
  assert.match(ability, /import \{ buildTaskSnapshot \} from '\.\/TaskSnapshot'/);
  assert.match(ability, /buildTaskSnapshot\(this\.lastRequestId, finalTaskId, text\)/);
  // 单帧契约只能由 TaskSnapshot 拼，AgentExtAbility 里不得再内联 task 报文
  assert.doesNotMatch(ability, /"result":\{"task"/);
});
