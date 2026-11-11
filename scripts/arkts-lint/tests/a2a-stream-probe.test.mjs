// 路径: scripts/arkts-lint/tests/a2a-stream-probe.test.mjs
// 职责: 端A2A 流式探针的帧构造与控制面——WORKING / artifactUpdate(append,lastChunk) / COMPLETED(final)。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const snapshot = loadNoteReviewEtsModule('entry/src/main/ets/agentextability/TaskSnapshot.ets');

test('流式探针帧：WORKING → artifactUpdate 分块 → COMPLETED(final)', () => {
  const start = JSON.parse(snapshot.buildTaskStreamStart('req-1', 'task-1'));
  assert.equal(start.result.task.id, 'task-1');
  assert.equal(start.result.task.contextId, 'mindtrace-context');
  assert.equal(start.result.task.status.state, 'TASK_STATE_WORKING');

  const first = JSON.parse(snapshot.buildArtifactUpdate('req-1', 'task-1', '第一段', false, false));
  assert.equal(first.result.artifactUpdate.taskId, 'task-1');
  assert.equal(first.result.artifactUpdate.artifact.artifactId, 'task-1-artifact');
  assert.equal(first.result.artifactUpdate.artifact.parts[0].text, '第一段');
  assert.equal(first.result.artifactUpdate.artifact.parts[0].mediaType, 'text/plain');
  assert.equal(first.result.artifactUpdate.append, false);
  assert.equal(first.result.artifactUpdate.lastChunk, false);

  const second = JSON.parse(snapshot.buildArtifactUpdate('req-1', 'task-1', '第二段', true, true));
  assert.equal(second.result.artifactUpdate.append, true);
  assert.equal(second.result.artifactUpdate.lastChunk, true);

  const end = JSON.parse(snapshot.buildTaskStreamEnd('req-1', 'task-1'));
  assert.equal(end.result.statusUpdate.taskId, 'task-1');
  assert.equal(end.result.statusUpdate.status.state, 'TASK_STATE_COMPLETED');
  assert.equal(end.result.statusUpdate.final, true);
});

test('探针接线：控制器只认「流式探针」，端口有 start/chunk/end，AgentCard 打开 streaming', () => {
  const controller = read('entry/src/main/ets/services/A2AController.ets');
  assert.match(controller, /text\.trim\(\) === '流式探针'/);
  assert.match(controller, /text\.trim\(\) === '分块探针'/);
  assert.match(controller, /runStreamProbe\(input\.taskId\)/);
  assert.match(controller, /sendStreamingAnswer\(input\.taskId, probeText\)/);
  assert.match(controller, /streamStart\(taskId: string\)/);
  assert.match(controller, /streamChunk\(taskId: string, text: string, append: boolean, lastChunk: boolean\)/);
  assert.match(controller, /streamEnd\(taskId: string\)/);
  assert.match(controller, /A2A_STREAM_PROBE begin/);
  const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');
  assert.match(ability, /A2A_STREAM_FRAME kind=/);
  assert.match(ability, /buildTaskStreamStart\(this\.lastRequestId, taskId\)/);
  assert.match(ability, /buildArtifactUpdate\(this\.lastRequestId, taskId, text, append, lastChunk\)/);
  assert.match(ability, /buildTaskStreamEnd\(this\.lastRequestId, taskId\)/);
  const card = JSON.parse(read('entry/src/main/resources/base/profile/agent_config.json'));
  assert.equal(card.agentCards[0].capabilities.streaming, true);
});
