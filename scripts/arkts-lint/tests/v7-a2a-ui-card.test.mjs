// 路径: scripts/arkts-lint/tests/v7-a2a-ui-card.test.mjs
// 职责: 端A2A 官方 uiExtensionCard + jump 指令的契约测试。
//       被测的两个 .ets 都是纯字符串/pure 函数、不 import @kit.*，因此直接
//       typescript.transpileModule 后 import，跑真实代码而不是正则断言源码。
// 背景: docs/specs/031-xiaoyi-batch-capture-entry.md §4.9 —— 上一轮卡片缺
//       cardId / bundleName 触发 1011 start_ability_fail 与约 12 次/秒重试；
//       本轮必须补齐必填字段，且空卡片时快照逐字节等于旧的纯文本快照。
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');

async function loadModules() {
  const snapshot = readFileSync(
    resolve(root, 'entry/src/main/ets/agentextability/TaskSnapshot.ets'), 'utf8');
  const card = readFileSync(
    resolve(root, 'entry/src/main/ets/agentextability/A2AUiCard.ets'), 'utf8');
  // 纯函数契约：卡片构造层不允许把 Kit 依赖带进扩展进程
  assert.doesNotMatch(card, /^\s*import\b[^\n]*@kit\./m,
    'A2AUiCard.ets must not import any @kit.*');
  const js = ts.transpileModule(snapshot + '\n' + card, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ES2022,
    },
  }).outputText;
  return await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}

const modules = loadModules();

test('wantsPickCard: 拍题/选图命中，存笔记不命中', async () => {
  const mod = await modules;
  assert.equal(mod.wantsPickCard('我要拍题'), true);
  assert.equal(mod.wantsPickCard('存笔记：极限'), false);
  assert.equal(mod.wantsPickCard('帮我整理照片'), true);
  assert.equal(mod.wantsPickCard('从相册选图'), true);
  assert.equal(mod.wantsPickCard(''), false);
});

test('buildPickCardPartJson: 必填 cardId / bundleName 齐全', async () => {
  const mod = await modules;
  const part = JSON.parse(mod.buildPickCardPartJson('我要拍题'));
  const card = part.data.uiExtensionCard;
  assert.equal(card.cardId, 'mindtrace-pick');
  assert.equal(card.bundleName, 'com.example.mindtrace');
  assert.equal(card.moduleName, 'entry');
  assert.equal(card.abilityName, 'AgentUIExtAbility');
});

test('buildPickCardPartJson: payload 是字符串，二次解析还原原 query（含引号/换行）', async () => {
  const mod = await modules;
  const query = '拍题："极限"\n第二行\\反斜杠';
  const card = JSON.parse(mod.buildPickCardPartJson(query)).data.uiExtensionCard;
  assert.equal(typeof card.payload, 'string');
  const payload = JSON.parse(card.payload);
  assert.equal(payload.query, query);
  assert.equal(payload.source, 'xiaoyi');
  assert.equal(payload.v, 1);
});

test('buildTaskSnapshotWithCard: 空卡片逐字节等于 buildTaskSnapshot', async () => {
  const mod = await modules;
  const text = '回复正文\n第二行 "引号"';
  const plain = mod.buildTaskSnapshot('req-1', 'task-1', text);
  const withEmptyCard = mod.buildTaskSnapshotWithCard('req-1', 'task-1', text, '');
  assert.equal(withEmptyCard, plain);
});

test('buildTaskSnapshotWithCard: parts 顺序为 [text, card]，card part 带 data', async () => {
  const mod = await modules;
  const cardPartJson = mod.buildPickCardPartJson('整理图片');
  const snapshot = JSON.parse(
    mod.buildTaskSnapshotWithCard('req-2', 'task-2', '去应用选图', cardPartJson));
  const parts = snapshot.result.task.artifacts[0].parts;
  assert.equal(parts.length, 2);
  assert.equal(parts[0].mediaType, 'text/plain');
  assert.equal(parts[0].text, '去应用选图');
  // parts[1] 是卡片 part 本身；序列化后仍能解析出 data.uiExtensionCard
  const cardPart = JSON.parse(JSON.stringify(parts[1]));
  assert.ok(cardPart.data !== undefined, 'card part must carry data');
  assert.equal(cardPart.data.uiExtensionCard.cardId, 'mindtrace-pick');
  assert.equal(typeof cardPart.data.uiExtensionCard.payload, 'string');
});

test('buildJumpDirective: deepLink 兜底 + executeIntent 先执行', async () => {
  const mod = await modules;
  const jump = JSON.parse(mod.buildJumpDirective()).data.jump;
  assert.equal(jump.deepLink.url, 'mindtrace://pick');
  assert.equal(jump.deepLink.appPackage, 'com.example.mindtrace');
  assert.equal(jump.executeIntent.intentName, 'com.example.mindtrace.PICK');
  assert.equal(jump.executeIntent.bundleName, 'com.example.mindtrace');
  assert.equal(jump.executeIntent.executeMode, 'foreground');
});
