import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const base = 'entry/src/main/ets/overlays/AgentFloatWindow/chat/';
const router = read(base + 'ChatBubble.ets');
const userBubble = read(base + 'UserMessageBubble.ets');
const aiBubble = read(base + 'AiMessageBubble.ets');
const runModels = read(base + 'AgentRunModels.ets');
const runPanel = read(base + 'AgentRunPanel.ets');
const thinkingStep = read(base + 'AgentThinkingStep.ets');
const toolStep = read(base + 'AgentToolStep.ets');
const answerStep = read(base + 'AgentAnswerStep.ets');
const statusStep = read(base + 'AgentStatusStep.ets');

test('ChatBubble remains the role router for isolated message renderers', () => {
  assert.match(router, /import \{ UserMessageBubble \}/);
  assert.match(router, /import \{ AiMessageBubble \}/);
  assert.match(router, /chatMessageRunParts/);
  assert.match(router, /this\.msg\.role === 'user'/);
  assert.doesNotMatch(router, /MarkdownRenderer|FormulaSplitRenderer|ContentProtocol|processOpen/);
});

test('AgentRunPanel frames process parts without owning a global disclosure', () => {
  assert.match(aiBubble, /AgentRunPanel/);
  assert.doesNotMatch(aiBubble, /MarkdownRenderer|FormulaSplitRenderer|ContentProtocol/);
  assert.match(runPanel, /ForEach\(this\.parts/);
  assert.match(runPanel, /AgentThinkingStep/);
  assert.match(runPanel, /AgentToolStep/);
  assert.match(runPanel, /AgentAnswerStep/);
  assert.match(runPanel, /AgentStatusStep/);
  assert.match(thinkingStep, /export struct AgentThinkingStep/);
  assert.match(toolStep, /export struct AgentToolStep/);
  assert.match(answerStep, /export struct AgentAnswerStep/);
  assert.match(statusStep, /export struct AgentStatusStep/);
  assert.match(runPanel, /this\.hasProcessParts\(\)/);
  assert.match(runPanel, /part\.kind !== 'answer'/);
  assert.match(runPanel, /border\(\{ width: 0\.5, color: BORDER \}\)/);
  assert.doesNotMatch(runPanel, /processOpen|执行过程|completedSummary|latestAgentRunActivity|onToggle/);
  assert.doesNotMatch(router + aiBubble, /processExpanded|onToggleProcess/);
});

test('run reducer reserves ordered thinking tool result and answer handling', () => {
  assert.match(runModels, /AgentRunPartKind = 'thinking' \| 'tool' \| 'answer' \| 'status' \| 'error'/);
  assert.match(runModels, /event\.type === 'thinking'/);
  assert.match(runModels, /event\.type === 'text'/);
  assert.match(runModels, /event\.type === 'tool_call'/);
  assert.match(runModels, /applyToolResult/);
  assert.match(runModels, /findToolPartIndex\(parts, callId\)/);
  assert.match(runModels, /projectLegacyAgentRun/);
  assert.match(runModels, /export function appendAgentRunStatus/);
  assert.match(runModels, /export function appendAgentRunError/);
});

test('thinking module independently owns collapsed streaming and completed summary behavior', () => {
  assert.match(thinkingStep, /@State detailOpen: boolean = false/);
  assert.doesNotMatch(thinkingStep, /Image\(/);
  assert.doesNotMatch(thinkingStep, /Circle\(\{/);
  assert.doesNotMatch(thinkingStep, /this\.detailOpen \? '⌃' : '⌄'/);
  assert.match(thinkingStep, /\.height\(20\)/);
  assert.doesNotMatch(thinkingStep, /\.borderRadius\(/);
  assert.doesNotMatch(thinkingStep, /\.backgroundColor\(/);
  assert.match(thinkingStep, /this\.status === 'running'/);
  assert.match(thinkingStep, /Marquee\(\{/);
  assert.match(thinkingStep, /src: this\.runningLine\(\)/);
  assert.match(thinkingStep, /layoutWeight\(1\)/);
  assert.match(thinkingStep, /MarqueeUpdateStrategy\.PRESERVE_POSITION/);
  assert.match(thinkingStep, /private completedSummary/);
  assert.match(thinkingStep, /normalized\.substring\(0, THINKING_SUMMARY_LIMIT\)/);
  assert.match(thinkingStep, /this\.detailOpen = !this\.detailOpen/);
  assert.match(thinkingStep, /if \(!this\.detailOpen\) \{/);
  assert.match(thinkingStep, /if \(this\.detailOpen\) \{/);
  assert.doesNotMatch(toolStep, /detailOpen.*thinking|processOpen/);
});

test('isolated presentation modules do not depend on business layers', () => {
  const presentation = [userBubble, aiBubble, runPanel, thinkingStep, toolStep, answerStep, statusStep].join('\n');
  assert.doesNotMatch(presentation, /services|viewmodels|workflows|database|LlmClient|AgentChatService|ToolRegistry/);
});
