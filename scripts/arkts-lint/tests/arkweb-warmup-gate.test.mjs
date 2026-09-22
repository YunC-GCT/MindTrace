// scripts/arkts-lint/tests/arkweb-warmup-gate.test.mjs
//
// Issue #119 / spec/restore-arkweb-warmup:
//   Regression gate for the ArkWeb startup warmup, fixed SINGLE mode,
//   public baseline precondition state, and protected no-migration scope.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const servicePath = 'entry/src/main/ets/services/ArkWebWarmupService.ets';
const entryAbilityPath = 'entry/src/main/ets/entryability/EntryAbility.ets';
const hypiumTestPath = 'entry/src/test/ArkWebWarmupService.test.ets';
const service = read(servicePath);
const entryAbility = read(entryAbilityPath);
const hypiumTest = read(hypiumTestPath);

test('ArkWeb warmup adapter uses supported APIs and the frozen SINGLE mode', () => {
  assert.match(service, /from ['"]@ohos\.web\.webview['"]/);
  assert.match(service, /setRenderProcessMode\(webview\.RenderProcessMode\.SINGLE\)/);
  assert.match(service, /initializeWebEngine\(\)/);
  assert.match(service, /export interface ArkWebPlatformAdapter/);
  assert.match(service, /export interface WarmupResult/);
  assert.match(service, /recoverable: boolean/);
});

test('EntryAbility runs the warmup gate before page content loading', () => {
  assert.match(entryAbility, /ArkWebWarmupService/);
  const warmupCall = entryAbility.indexOf('ArkWebWarmupService.warmup()');
  const contentLoad = entryAbility.indexOf("windowStage.loadContent('pages/Index'");
  assert.ok(warmupCall >= 0, 'startup must invoke ArkWebWarmupService.warmup()');
  assert.ok(contentLoad >= 0, 'startup must retain page content loading');
  assert.ok(warmupCall < contentLoad, 'warmup must precede page content loading');
});

test('BenchmarkBaselinePrecondition is publicly queryable for valid and invalid outcomes', () => {
  assert.match(service, /export interface BenchmarkBaselinePrecondition/);
  const preconditionInterface = service.match(/export interface BenchmarkBaselinePrecondition \{[\s\S]*?\n\}/);
  assert.ok(preconditionInterface, 'BenchmarkBaselinePrecondition interface must be exported');
  assert.match(service, /getBenchmarkBaselinePrecondition\(\)/);
  assert.match(service, /state: ['"]valid['"]/);
  assert.match(service, /state: ['"]invalid['"]/);
  assert.match(service, /setPlatformAdapterForTest/);
  assert.match(service, /resetForTest/);
  assert.match(service, /precondition = \{\s*state: 'valid'/s);
  assert.match(service, /precondition = \{\s*state: 'invalid'/s);
  assert.match(service, /return \{\s*state: precondition\.state/s);
  assert.doesNotMatch(preconditionInterface[0], /recoverable/);
  assert.match(service, /recoverable: false/);
  assert.match(service, /recoverable: true/);
});

test('Recoverable warmup failures are content-safe and non-blocking', () => {
  assert.match(service, /catch \(e\)/);
  assert.doesNotMatch(service, /e\.message/);
  assert.doesNotMatch(service, /JSON\.stringify\(e\)/);
  assert.match(service, /SUCCESS_DIAGNOSTIC/);
  assert.match(service, /FAILURE_DIAGNOSTIC/);
  assert.match(service, /buildFailureDiagnostic\(e\)/);
  assert.match(service, /errorName=/);
  assert.match(service, /errorCode=/);
  assert.match(service, /sanitizeMetadata/);
  assert.doesNotMatch(service, /errorType=/);
  assert.doesNotMatch(service, /recoverable-platform-error/);
  assert.match(service, /success: false/);
  assert.match(service, /recoverable: true/);
  assert.match(service, /diagnostic: diagnostic/);
  assert.match(entryAbility, /warmupResult\.success/);
  assert.match(entryAbility, /hilog\.(info|warn)/);
});

test('Hypium behavior test executes the public adapter and precondition seam', () => {
  assert.match(hypiumTest, /implements ArkWebPlatformAdapter/);
  assert.match(hypiumTest, /setPlatformAdapterForTest\(adapter\)/);
  assert.match(hypiumTest, /ArkWebWarmupService\.warmup\(\)/);
  assert.match(hypiumTest, /getBenchmarkBaselinePrecondition\(\)/);
  assert.match(hypiumTest, /webview\.RenderProcessMode\.SINGLE/);
  assert.match(hypiumTest, /assertEqual\('valid'\)/);
  assert.match(hypiumTest, /assertEqual\('invalid'\)/);
  assert.match(hypiumTest, /errorName=/);
  assert.match(hypiumTest, /errorCode=/);
  assert.doesNotMatch(hypiumTest, /errorType=/);
  assert.match(hypiumTest, /indexOf\('user content'\) < 0/);
  assert.match(hypiumTest, /resetForTest\(\)/);
  assert.match(hypiumTest, /is_idempotent_after_success_without_repeating_platform_calls/);
  assert.match(hypiumTest, /renderProcessModeCalls\).assertEqual\(1\)/);
  assert.match(hypiumTest, /initializeCalls\).assertEqual\(1\)/);
});

test('EntryAbility keeps startup work after a recoverable warmup result', () => {
  const warmupBlock = entryAbility.match(/const warmupResult = ArkWebWarmupService\.warmup\(\);[\s\S]*?\/\/ 初始化 LLM 配置/);
  assert.ok(warmupBlock, 'warmup integration must be contained in onCreate before existing startup work');
  assert.match(warmupBlock[0], /if \(warmupResult\.success\)/);
  assert.match(warmupBlock[0], /else/);
  assert.doesNotMatch(warmupBlock[0], /throw /);
  assert.match(entryAbility, /LlmConfig\.getInstance\(\)\.init/);
  assert.match(entryAbility, /DatabaseHelper\.init/);
});

test('Issue 119 preserves the existing chat rendering and persistence paths', () => {
  const chatSession = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets');
  const chatHistoryPersistence = read('entry/src/main/ets/services/ChatHistoryPersistence.ets');
  const markdownRenderer = read('entry/src/main/ets/shared/molecules/MarkdownRenderer.ets');
  const formulaRenderer = read('entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets');
  assert.doesNotMatch(service + entryAbility, /StreamingReplyDocument/);
  assert.match(chatSession + chatHistoryPersistence, /chat_history/);
  assert.match(chatSession, /preferences\.getPreferences/);
  assert.match(markdownRenderer, /export struct MarkdownRenderer/);
  assert.match(formulaRenderer, /export struct FormulaSplitRenderer/);
});

test('Issue 141 chat history persistence diagnostics and stream boundaries stay wired', () => {
  const chatSession = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets');
  const chatHistoryPersistence = read('entry/src/main/ets/services/ChatHistoryPersistence.ets');
  const chatPersistenceWorker = read('entry/src/main/ets/workers/ChatPersistenceWorker.ets');
  const agentFloatWindow = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.match(chatHistoryPersistence, /schemaVersion=/);
  assert.match(chatHistoryPersistence, /ts=/);
  assert.match(chatHistoryPersistence, /pendingMigrationFrom/);
  assert.match(chatHistoryPersistence, /reasoningExpanded/);
  assert.match(chatPersistenceWorker, /schemaVersion: number/);
  assert.match(chatPersistenceWorker, /diagnostic\('VERIFY', 'verified=true'\)/);
  assert.match(chatSession, /getLastSaveResult\(\)/);
  assert.match(agentFloatWindow, /finishCurrentStreamingMessage\(\)/);
  assert.match(agentFloatWindow, /inputVm\.bind\([\s\S]*finishCurrentStreamingMessage\(\)/);
});
