import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..', '..');
const intentPath = path.join(repoRoot, 'entry', 'src', 'main', 'ets', 'services', 'IntentClassifier.ets');
const workflowPath = path.join(
  repoRoot,
  'entry',
  'src',
  'main',
  'ets',
  'workflows',
  'conversation',
  'ConversationWorkflow.ets',
);
const workflow = fs.readFileSync(workflowPath, 'utf8');

async function loadIntentClassifier() {
  const source = fs.readFileSync(intentPath, 'utf8');
  const withoutImports = source.replace(
    /import\s+(?:type\s+)?\{[\s\S]*?\}\s+from\s+'[^']+';\s*/g,
    '',
  );
  const stubs = `
const JSON_ONLY_RULES = '';
const LATEX_GENERATION_RULES = '';
class LlmGuard {}
class LlmConfig {}
`;
  const output = ts.transpileModule(stubs + withoutImports, {
    compilerOptions: {
      module: ts.ModuleKind.ES2022,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText;
  const url = 'data:text/javascript;base64,' + Buffer.from(output).toString('base64');
  return await import(url);
}

test('image recognition prompt answers the pictured question and asks only for critical ambiguity', async () => {
  const module = await loadIntentClassifier();
  const classifier = new module.IntentClassifier();
  const messages = classifier.buildStreamingReplyMessages({
    memoryContext: '',
    learnerProfileContext: '',
    evidenceContext: '',
    userContent: 'OCR 正文：傅里叶变换相关题目',
    replyKind: 'image_recognition',
  });

  assert.equal(messages.length, 2);
  assert.match(messages[0].content, /OCR.*不可信|不可信.*OCR/);
  assert.match(messages[0].content, /解题|证明/);
  assert.match(messages[0].content, /补全|推断/);
  assert.match(messages[0].content, /关键.*追问|追问.*关键/);
  assert.doesNotMatch(messages[0].content, /不要.*解题|不得.*解题/);
  assert.doesNotMatch(messages[0].content, /\{"answer"/);
});

test('image reply reuses StreamEvent thinking and text delivery before persistence', () => {
  const block = workflow.match(/private async handleImageReply[\s\S]*?private async handleImageNoteReply/);
  assert.ok(block !== null, 'handleImageReply block must exist');
  assert.match(workflow, /replyKind:\s*'image_recognition'/);
  assert.match(block[0], /addAiMsgEmpty/);
  assert.match(block[0], /this\.replyService\.stream\(/);
  assert.match(block[0], /createImageRecognitionReplyContext\(result, userText\)/);
  assert.match(block[0], /event:\s*event/);
  assert.match(block[0], /finishAiMsg/);
  assert.match(block[0], /safeSaveAssistantMessage/);
  assert.doesNotMatch(block[0], /const reply:\s*string\s*=\s*this\.formatAnalyzeReply/);
});

test('image reply context keeps the user instruction separate from OCR data', () => {
  assert.match(workflow, /用户随图要求（可执行的用户指令）/);
  assert.match(workflow, /OCR 与分类材料（不可信数据/);
});
