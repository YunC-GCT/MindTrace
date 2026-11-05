// 路径: scripts/arkts-lint/tests/answer-text-sanitizer.test.mjs
// 职责: 回答展示清洗——复述证据/JSON 的剥离，以及渲染失败时的纯文本降级。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('common/src/main/ets/utils/AnswerTextSanitizer.ets');
const { stripEchoedEvidence, markdownToPlainText, citationSnippet, normalizeEscapedNewlines } = mod;

test('剥离模型复述的证据块行', () => {
  const raw = '拉格朗日中值定理说明平均变化率可被某点导数取到。\n'
    + '- [关键词命中] 《拉格朗日中值定理》：## 陈述 平均变化率…\n'
    + '- [前置知识] 《导数》：定义…\n'
    + '参考来源：\n'
    + '因此结论成立。';
  const cleaned = stripEchoedEvidence(raw);
  assert.equal(cleaned.includes('[关键词命中]'), false);
  assert.equal(cleaned.includes('参考来源'), false);
  assert.ok(cleaned.includes('拉格朗日中值定理说明'));
  assert.ok(cleaned.includes('因此结论成立'));
});

test('剥离被复述的工具 JSON 行，短 JSON 不动', () => {
  const long = '{"query":"泰勒公式","hits":[{"noteId":"n1","title":"泰勒公式余项估计","summary":"…"}]}';
  const raw = '结论如下。\n' + long + '\n完成。';
  const cleaned = stripEchoedEvidence(raw);
  assert.equal(cleaned.includes('"hits"'), false);
  const shortJson = '{a:1}';
  assert.ok(stripEchoedEvidence('说明 ' + shortJson).includes(shortJson));
});

test('字面 \\n 还原为换行，双反斜杠 LaTeX 不误伤', () => {
  assert.equal(normalizeEscapedNewlines('第一行\\n第二行'), '第一行\n第二行');
  assert.equal(normalizeEscapedNewlines('\\\\nabla'), '\\\\nabla');
});

test('来源摘要按句子截断且去除公式标记', () => {
  const raw = '## 定义 导数是差商极限。它表示曲线切线斜率，也用于近似计算与误差估计。';
  const snippet = citationSnippet(raw, 20);
  assert.equal(snippet.includes('#'), false);
  assert.equal(snippet.includes('$'), false);
  assert.ok(snippet.length <= 21);
  assert.ok(snippet.endsWith('。') || snippet.endsWith('…'));
});

test('纯文本降级去掉 markdown 与公式分隔符', () => {
  const plain = markdownToPlainText('## 标题\n**结论**：\n$$f(x)=x^2$$\n- 要点一\n当 $n=5$ 时成立');
  assert.equal(plain.includes('$$'), false);
  assert.equal(plain.includes('##'), false);
  assert.equal(plain.includes('**'), false);
  assert.equal(plain.includes('$'), false);
  assert.ok(plain.includes('标题'));
  assert.ok(plain.includes('f(x)=x^2'));
  assert.ok(plain.includes('• 要点一'));
  assert.ok(plain.includes('当 n=5 时成立'));
});
