import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');
// a2a-smoke 自己不带 node_modules：复用 arkts-lint 里已安装的 typescript 做 transpile。
const requireFromLint = createRequire(resolve(root, 'scripts/arkts-lint/package.json'));
const ts = requireFromLint('typescript');

const snapshot = read('entry/src/main/ets/agentextability/TaskSnapshot.ets');
const ability = read('entry/src/main/ets/agentextability/AgentExtAbility.ets');

async function loadTaskSnapshot() {
  const js = ts.transpileModule(snapshot, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
  return await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}

const snapshotModule = await loadTaskSnapshot();

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
  assert.match(ability, /import \{ buildTaskSnapshot, unicodeCharCount, utf8ByteLength \} from '\.\/TaskSnapshot'/);
  assert.match(ability, /buildTaskSnapshot\(this\.lastRequestId, finalTaskId, text\)/);
  // 单帧契约只能由 TaskSnapshot 拼，AgentExtAbility 里不得再内联 task 报文
  assert.doesNotMatch(ability, /"result":\{"task"/);
});

test('utf8ByteLength counts ASCII, CJK, emoji and lone surrogates as UTF-8', () => {
  const { utf8ByteLength } = snapshotModule;
  assert.equal(utf8ByteLength(''), 0);
  assert.equal(utf8ByteLength('abc'), 3);
  assert.equal(utf8ByteLength('中文'), 6);
  // 普通汉字：1 字符 3 字节
  assert.equal(utf8ByteLength('中'), 3);
  // emoji 代理对：1 字符 4 字节
  assert.equal(utf8ByteLength('😀'), 4);
  // 孤立代理按替换字符 U+FFFD 记 3 字节
  assert.equal(utf8ByteLength('\uD83D'), 3);
  assert.equal(utf8ByteLength('\uDE00'), 3);
  assert.equal(utf8ByteLength('a中😀\uD83D'), 1 + 3 + 4 + 3);
});

test('unicodeCharCount counts code points, so a surrogate pair is one character', () => {
  const { unicodeCharCount } = snapshotModule;
  assert.equal(unicodeCharCount(''), 0);
  assert.equal(unicodeCharCount('abc'), 3);
  assert.equal(unicodeCharCount('中文'), 2);
  // 中文 1 字符 3 字节；emoji 1 字符 4 字节
  assert.equal(unicodeCharCount('中'), 1);
  assert.equal(unicodeCharCount('😀'), 1);
  // 孤立代理仍然算 1 个 code point
  assert.equal(unicodeCharCount('\uD83D'), 1);
  assert.equal(unicodeCharCount('\uDE00'), 1);
  assert.equal(unicodeCharCount('a中😀\uD83D'), 4);
});

test('buildTaskSnapshot round-trips the exact answer text (dollars, backslashes, newlines, quotes)', () => {
  const text = '行内公式 $x^2$，块 $$a ≥ 0$$。\n'
    + '第二行：\\frac{1}{2}、\\sqrt{a} 与 "双引号"、\'单引号\'。\r\n'
    + '第三行 😀 和零宽\u200B占位';
  const parsed = JSON.parse(snapshotModule.buildTaskSnapshot('req-1', 'task-1', text));
  const part = parsed.result.task.artifacts[0].parts[0];
  assert.equal(part.text, text);
  assert.equal(part.mediaType, 'text/plain');
});
