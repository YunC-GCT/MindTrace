// 路径: scripts/arkts-lint/tests/tool-loop-streaming.test.mjs
// 职责: 流式工具循环契约——SSE tool_calls 解析、结果预算裁剪、两轮流式执行。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const parser = loadNoteReviewEtsModule('common/src/main/ets/llm/LlmStreamParser.ets');
const budget = loadNoteReviewEtsModule('common/src/main/ets/workflow/tool-calling/ToolResultBudget.ets');
const workflowModule = loadNoteReviewEtsModule(
  'common/src/main/ets/workflow/tool-calling/ToolCallingStreamingWorkflow.ets');
const registryModule = loadNoteReviewEtsModule('common/src/main/ets/tools/ToolRegistry.ets');

const { parseStreamEventsFromSseData } = parser;
const { fitToolResult } = budget;
const { ToolCallingStreamingWorkflow } = workflowModule;
const { ToolRegistry } = registryModule;

test('SSE chunk 中的 tool_calls 增量被解析成 tool_call 事件', () => {
  const events = parseStreamEventsFromSseData(JSON.stringify({
    choices: [{
      index: 0,
      delta: {
        tool_calls: [{
          index: 0,
          id: 'call_1',
          function: { name: 'note_query_rag', arguments: '{"query":' },
        }],
      },
      finish_reason: null,
    }],
  }));
  assert.equal(events.length, 1);
  assert.equal(events[0].type, 'tool_call');
  assert.equal(events[0].toolName, 'note_query_rag');
  assert.equal(events[0].argumentsJson, '{"query":');
  assert.equal(events[0].index, 0);
});

test('文本与思考增量仍按原语义解析', () => {
  const events = parseStreamEventsFromSseData(JSON.stringify({
    choices: [{ index: 0, delta: { content: '你好', reasoning_content: '想' }, finish_reason: null }],
  }));
  assert.equal(events[0].type, 'thinking');
  assert.equal(events[1].type, 'text');
  assert.equal(events[1].delta, '你好');
});

test('JSON 结果超预算时保留结构，只丢尾部 hits', () => {
  const payload = { hits: [] };
  for (let i = 0; i < 10; i += 1) {
    payload.hits.push({ id: 'n' + i, excerpt: '内'.repeat(100) });
  }
  const fitted = fitToolResult(JSON.stringify(payload), 400);
  assert.equal(fitted.truncated, true);
  assert.ok(fitted.dropped > 0);
  const parsed = JSON.parse(fitted.content);
  assert.equal(parsed.truncated, true);
  assert.ok(parsed.hits.length < 10);
  assert.equal(parsed.count, parsed.hits.length);
});

test('非 JSON 结果退回字符截断', () => {
  const fitted = fitToolResult('x'.repeat(500), 100);
  assert.equal(fitted.truncated, true);
  assert.ok(fitted.content.length <= 100 + '…[truncated]'.length);
});

test('顶层数组结果（note_query）按条丢弃，仍是合法 JSON', () => {
  const rows = [];
  for (let i = 0; i < 6; i += 1) {
    rows.push({ id: 'n' + i, content: 'x'.repeat(200) });
  }
  const fitted = fitToolResult(JSON.stringify(rows), 500);
  assert.equal(fitted.truncated, true);
  assert.ok(fitted.dropped > 0);
  const parsed = JSON.parse(fitted.content);
  assert.ok(Array.isArray(parsed));
  assert.ok(parsed.length < 6);
});

test('无数组字段时缩短超长字符串，JSON 保持可解析', () => {
  const fitted = fitToolResult(JSON.stringify({ answer: 'x'.repeat(600) }), 500);
  assert.equal(fitted.truncated, true);
  const parsed = JSON.parse(fitted.content);
  assert.ok(parsed.answer.length <= 401);
});

test('流式工具循环：第一轮调工具，第二轮逐字输出最终回答', async () => {
  let round = 0;
  const requests = [];
  const llm = {
    call: async (request) => {
      requests.push(request);
      round += 1;
      if (round === 1) {
        return {
          streamed: true,
          text: '',
          toolCalls: [{
            id: 'c1', type: 'function', function: { name: 'echo', arguments: '{"q":"连续性"}' },
          }],
        };
      }
      request.onDelta({ type: 'text', delta: '答案' });
      request.onDelta({ type: 'text', delta: '来了' });
      return { streamed: true, text: '答案来了' };
    },
  };
  const executed = [];
  const tool = {
    name: 'echo',
    description: 'echo',
    parameters: {},
    execute: async (args) => {
      executed.push(args);
      return { ok: true, content: '{"hits":[]}' };
    },
  };
  const registry = new ToolRegistry();
  registry.register(tool);
  const workflow = new ToolCallingStreamingWorkflow(llm, registry);
  const deltas = [];
  const result = await workflow.run([{ role: 'user', content: '查笔记' }], {},
    (event) => {
      if (event.type === 'text') {
        deltas.push(event.delta);
      }
    });
  assert.deepEqual(deltas, ['答案', '来了']);
  assert.equal(result.text, '答案来了');
  assert.equal(requests.length, 2);
  assert.equal(executed.length, 1);
  assert.equal(requests[0].tools.length, 1);
  assert.equal(requests[1].messages[requests[1].messages.length - 1].role, 'tool');
});
