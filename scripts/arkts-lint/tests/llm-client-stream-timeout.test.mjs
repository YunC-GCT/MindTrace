import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const llmClient = read('common/src/main/ets/llm/LlmClient.ets');
const replyService = read('entry/src/main/ets/services/ReplyService.ets');

test('LlmClient.callStreamInternal firstByteTimer tiers by thinking capability', () => {
  // issue #226: 关闭思考 / unsupported → 12s；开启思考 / always_on → 60s。
  // 旧规则「上限锁 30s」只对可关闭思考的模型成立，always_on 模型不能靠关思考换首字节。
  // 2026-10-29: 非思考档 30s → 12s，弱网下不再让用户干等半分钟。
  assert.match(
    llmClient,
    /const firstByteWatchdogMs: number = thinkingActive \? 60000 : 12000;/,
    'first-byte watchdog must pick 60000ms for thinking, 12000ms otherwise',
  );
  assert.match(
    llmClient,
    /firstByteTimer = setTimeout\([\s\S]*?firstByteWatchdogMs\s*\)/,
    'firstByteTimer must use the capability-tiered value',
  );
});

test('ReplyService stream circuit reopens after a cooldown instead of disabling SSE for the process', () => {
  assert.match(replyService, /const STREAM_CIRCUIT_COOLDOWN_MS: number = 5 \* 60 \* 1000;/);
  assert.match(
    replyService,
    /ReplyService\.streamDisabledUntilMs = Date\.now\(\) \+ STREAM_CIRCUIT_COOLDOWN_MS;/,
    'opening the circuit must stamp a cooldown deadline',
  );
  assert.match(
    replyService,
    /if \(Date\.now\(\) >= ReplyService\.streamDisabledUntilMs\) \{[\s\S]{0,220}?ReplyService\.streamDisabled = false;/,
    'stream() must half-open once the cooldown elapsed',
  );
});

test('ReplyService reply paths pin enableThinking to false instead of inheriting config', () => {
  // 2026-10-26: 默认思考现在来自 ModelSpec（DeepSeek 官方默认开启），
  // 聊天与小艺两条链路都按「不思考」的时延预算跑，必须显式钉死，不能继承配置。
  const pinned = (replyService.match(/enableThinking\s*:\s*false/g) ?? []).length;
  assert.equal(pinned, 2, 'both reply paths (JSON guarded + stream) must pass enableThinking: false');
});

test('LlmClient maps thinking switches through the shared ModelSpec builder', () => {
  // 2026-10-26: Qwen 的 enable_thinking / DeepSeek 的 thinking.type 都来自
  // ModelSpec.on/off, LlmClient 不再按 vendor 分支。
  assert.doesNotMatch(llmClient, /enable_thinking/, 'flat enable_thinking is now a FieldWrite');
  assert.doesNotMatch(llmClient, /vendorId === 'deepseek'/);
  assert.doesNotMatch(llmClient, /vendorId === 'tongyi'/);
  assert.doesNotMatch(llmClient, /chat_template_kwargs/);
  assert.match(llmClient, /planModelRequest\(resolved\.spec, selection\)/);
});

test('LlmClient requestInStream callback tolerates undefined status data', () => {
  assert.match(
    llmClient,
    /private streamCallbackCode\(data: number \| undefined\): string[\s\S]*?return data\.toString\(\)/,
    'requestInStream callback logging must stringify undefined status data safely',
  );
  assert.doesNotMatch(
    llmClient,
    /requestInStream cb err=[\s\S]*?data\.toString\(\)/,
    'requestInStream callback must not call data.toString() directly',
  );
});

test('LlmClient normalizes stream transport failures as network errors', () => {
  assert.match(
    llmClient,
    /'LLM stream request failed: ' \+ err\.message,[\s\S]*?'NETWORK_ERROR'/,
    'stream transport failures must use the shared network error kind',
  );
});

test('ReplyService fallback does not override enableThinking', () => {
  const fallbackMatch = replyService.match(/private async fallback[\s\S]*?\n  \}/);
  assert.ok(fallbackMatch !== null, 'ReplyService fallback call must exist');
  assert.match(fallbackMatch[0], /this\.guardedComplete\(context, 'chat answer fallback'\)/);
  assert.doesNotMatch(fallbackMatch[0], /client\.call/);
  assert.doesNotMatch(fallbackMatch[0], /fallback\.text/);
  assert.doesNotMatch(fallbackMatch[0], /enableThinking\s*:/);
});
