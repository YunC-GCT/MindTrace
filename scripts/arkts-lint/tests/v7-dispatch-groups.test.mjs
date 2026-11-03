// 路径: scripts/arkts-lint/tests/v7-dispatch-groups.test.mjs
// 职责: DispatchOptions 五组契约、group 纯函数行为，以及 WorkflowContext 的收窄。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('DispatchOptions 按五组定义', () => {
  const src = read('agents/src/main/ets/core/dispatch/DispatchOptions.ets');
  for (const group of ['WritePorts', 'Observability', 'RunControl', 'DispatchMode', 'DispatchDomain']) {
    assert.match(src, new RegExp('export interface ' + group + ' \\{'));
  }
  assert.match(src, /export interface DispatchOptions\s+extends WritePorts, Observability, RunControl, DispatchMode, DispatchDomain/);
  assert.match(src, /export function groupDispatchOptions\(/);
  assert.doesNotMatch(src, /flattenDispatchOptions/);
});

test('groupDispatchOptions 保持字段引用', () => {
  const mod = loadNoteReviewEtsModule('agents/src/main/ets/core/dispatch/DispatchOptions.ets');
  const token = { isCancelled: () => false };
  const dao = { insert: async () => 1, queryById: async () => null };
  const sink = { emit: async () => {}, settle: async () => {} };
  const timing = () => {};
  const options = {
    persist: true,
    includeRawText: true,
    analysisOnly: false,
    skipLlmClassification: true,
    dao,
    cancellationToken: token,
    onNodeTiming: timing,
    subjectVocabulary: ['数学'],
    runEventSink: sink,
  };
  const groups = mod.groupDispatchOptions(options);
  assert.equal(groups.mode.persist, true);
  assert.equal(groups.mode.includeRawText, true);
  assert.equal(groups.mode.analysisOnly, false);
  assert.equal(groups.mode.skipLlmClassification, true);
  assert.equal(groups.writePorts.dao, dao);
  assert.equal(groups.runControl.cancellationToken, token);
  assert.equal(groups.observability.onNodeTiming, timing);
  assert.equal(groups.observability.runEventSink, sink);
  assert.deepEqual(Array.from(groups.domain.subjectVocabulary), ['数学']);
  assert.equal(mod.flattenDispatchOptions, undefined);
});

test('WorkflowContext 只暴露分组；四个 workflow 按组消费', () => {
  const ctx = read('agents/src/main/ets/workflows/WorkflowContext.ets');
  assert.match(ctx, /writePorts: WritePorts/);
  assert.match(ctx, /observability: Observability/);
  assert.match(ctx, /runControl: RunControl/);
  assert.match(ctx, /mode: DispatchMode/);
  assert.match(ctx, /domain: DispatchDomain/);
  assert.doesNotMatch(ctx, /options: DispatchOptions/);
  const files = [
    'NoteCaptureWorkflow',
    'NoteGenerationWorkflow',
    'NotePreparedWorkflow',
    'NoteRegenerateWorkflow',
  ];
  for (const file of files) {
    const src = read('agents/src/main/ets/workflows/' + file + '.ets');
    assert.doesNotMatch(src, /flattenDispatchOptions/);
    assert.doesNotMatch(src, /context\.options/);
    assert.match(src, /context\.writePorts/);
  }
  const generation = read('agents/src/main/ets/workflows/NoteGenerationWorkflow.ets');
  assert.match(generation, /context\.domain/);
  assert.match(generation, /context\.mode/);
  assert.match(generation, /context\.runControl/);
  const executor = read('agents/src/main/ets/core/CommandExecutor.ets');
  assert.match(executor, /groupDispatchOptions\(effective\)/);
});
