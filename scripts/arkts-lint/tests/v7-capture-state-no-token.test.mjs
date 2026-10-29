// #243 步骤 5：取消只走 RunContext，不得回流到 AgentState。
// 静态守卫：读真实 .ets 源文件，防止有人把 cancellationToken 塞回图状态。
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

// tests/ -> arkts-lint/ -> scripts/ -> repo root
const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));
const readSource = (relativePath) => readFileSync(join(repoRoot, relativePath), 'utf8');

const agentStatePath = 'agents/src/main/ets/graph/AgentState.ets';
const stateGraphPath = 'common/src/main/ets/workflow/StateGraph.ets';
const nodePaths = [
  'agents/src/main/ets/graph/nodes/OcrNode.ets',
  'agents/src/main/ets/graph/nodes/ClassifyNode.ets',
  'agents/src/main/ets/graph/nodes/StructureNode.ets',
  'agents/src/main/ets/graph/nodes/TruthCheckNode.ets',
  'agents/src/main/ets/graph/nodes/PersistNode.ets',
];

test('AgentState has no cancellationToken field', () => {
  const source = readSource(agentStatePath);
  assert.doesNotMatch(source, /cancellationToken/,
    'cancellation is a runtime concern; AgentState must not carry a token');
});

test('CaptureNode takes RunContext as its second argument', () => {
  const source = readSource(agentStatePath);
  assert.match(
    source,
    /export type CaptureNode\s*=\s*\(\s*state:\s*AgentState\s*,\s*context\?:\s*RunContext\s*\|\s*null\s*\)\s*=>\s*Promise<CaptureNodeResult>\s*;/,
    'CaptureNode must accept an optional RunContext',
  );
});

test('capture nodes never read a cancellation token from state', () => {
  for (const relativePath of nodePaths) {
    const source = readSource(relativePath);
    assert.doesNotMatch(source, /\.cancellationToken/,
      relativePath + ' must brake through RunContext, not state.cancellationToken');
  }
});

test('StateGraphNode takes context and run() forwards it', () => {
  const source = readSource(stateGraphPath);
  assert.match(
    source,
    /export type StateGraphNode<State>\s*=\s*\(\s*state:\s*State\s*,\s*context\?:\s*RunContext\s*\|\s*null\s*\)\s*=>\s*Promise<State>\s*;/,
    'StateGraphNode must accept an optional RunContext',
  );
  assert.match(
    source,
    /state\s*=\s*await\s+node\(state,\s*context\)\s*;/,
    'run() must pass context to each node',
  );
});
