// LlmToolCalling.test.ets — ToolRegistry / ToolLoop 行为测试 (spec 014, Hypium)
// 运行: DevEco Studio → common 模块 Unit Test (on-device)
import { describe, it, expect } from '@ohos/hypium';
import { ToolRegistry, ToolLoop, LlmError } from '../main/ets/Index';
import type {
  AgentTool,
  ChatMessage,
  LlmCallRequest,
  LlmCallResult,
  LlmCaller,
  LlmFunctionCallNameArgs,
  LlmToolCall,
  ToolResult,
} from '../main/ets/Index';

// 脚本化 LLM: 按队列回放响应, 记录每次收到的 messages
class ScriptedLlm implements LlmCaller {
  public seenMessages: ChatMessage[][] = [];
  private responses: LlmCallResult[];
  private index: number = 0;

  constructor(responses: LlmCallResult[]) {
    this.responses = responses;
  }

  async call(request: LlmCallRequest): Promise<LlmCallResult> {
    this.seenMessages.push(request.messages.slice(0));
    if (this.index >= this.responses.length) {
      // 脚本耗尽后重复最后一条响应 (沿袭 LlmGuard FakeCaller 惯例) — maxSteps 触顶测试依赖它
      const last: LlmCallResult = this.responses[this.responses.length - 1];
      return last;
    }
    const response: LlmCallResult = this.responses[this.index];
    this.index += 1;
    return response;
  }
}

// 构造"模型请求工具"响应
function toolCallResult(id: string, name: string, argsJson: string): LlmCallResult {
  const fn: LlmFunctionCallNameArgs = { name: name, arguments: argsJson };
  const call: LlmToolCall = { id: id, type: 'function', function: fn };
  const result: LlmCallResult = { text: '', streamed: false };
  result.toolCalls = [call];
  return result;
}

function textResult(text: string): LlmCallResult {
  const result: LlmCallResult = { text: text, streamed: false };
  return result;
}

// 测试工具: 首次可失败(验证错误回喂恢复), 之后回显 payload
class EchoProbeTool implements AgentTool {
  public name: string = 'echo_probe';
  public description: string = 'echoes the payload for tests';
  public parameters: Record<string, Object> = {};
  public failFirst: boolean = false;
  private failedOnce: boolean = false;

  async execute(args: Record<string, Object>): Promise<ToolResult> {
    if (this.failFirst && !this.failedOnce) {
      this.failedOnce = true;
      const fail: ToolResult = { ok: false, content: 'transient failure' };
      return fail;
    }
    const payload: Object | undefined = args['payload'];
    const ok: ToolResult = { ok: true, content: 'echo:' + String(payload ?? '') };
    return ok;
  }
}

const USER_MSG: ChatMessage = { role: 'user', content: 'probe' };

export default function llmToolCallingTest(): void {
  describe('LlmToolCalling.spec014_test', () => {
    it('registry_registers_and_lists_wire_shape', 0, async () => {
      const registry: ToolRegistry = new ToolRegistry();
      const tool: EchoProbeTool = new EchoProbeTool();
      registry.register(tool);
      expect(registry.has('echo_probe')).assertTrue();
      const defs = registry.listDefinitions();
      expect(defs.length).assertEqual(1);
      expect(defs[0].type).assertEqual('function');
      expect(defs[0].function.name).assertEqual('echo_probe');
      expect(defs[0].function.description).assertEqual('echoes the payload for tests');
    });

    it('registry_rejects_duplicate_and_invalid_name', 0, async () => {
      const registry: ToolRegistry = new ToolRegistry();
      registry.register(new EchoProbeTool());
      let duplicateThrew: boolean = false;
      try {
        registry.register(new EchoProbeTool());
      } catch (e) {
        duplicateThrew = e instanceof LlmError;
      }
      expect(duplicateThrew).assertTrue();
      const badTool: EchoProbeTool = new EchoProbeTool();
      badTool.name = 'Bad-Name';
      let invalidThrew: boolean = false;
      try {
        registry.register(badTool);
      } catch (e) {
        invalidThrew = e instanceof LlmError;
      }
      expect(invalidThrew).assertTrue();
    });

    it('registry_tolerates_unknown_tool_and_bad_json_as_ok_false', 0, async () => {
      const registry: ToolRegistry = new ToolRegistry();
      registry.register(new EchoProbeTool());
      const unknown: ToolResult = await registry.execute('nope', '{}');
      expect(unknown.ok).assertFalse();
      expect(unknown.content).assertContain('unknown tool');
      const badJson: ToolResult = await registry.execute('echo_probe', 'not-json');
      expect(badJson.ok).assertFalse();
      expect(badJson.content).assertContain('invalid tool arguments');
    });

    it('loop_closes_single_tool_round_with_correct_message_shapes', 0, async () => {
      const llm: ScriptedLlm = new ScriptedLlm([
        toolCallResult('c1', 'echo_probe', '{"payload":"hi"}'),
        textResult('done'),
      ]);
      const registry: ToolRegistry = new ToolRegistry();
      registry.register(new EchoProbeTool());
      const loop: ToolLoop = new ToolLoop(llm);
      const final: LlmCallResult = await loop.run([USER_MSG], registry);
      expect(final.text).assertEqual('done');
      // 第二步收到的回喂序列: [user, assistant(tool_calls, content=''), tool(tool_call_id)]
      const fedBack: ChatMessage[] = llm.seenMessages[1];
      expect(fedBack.length).assertEqual(3);
      expect(fedBack[1].role).assertEqual('assistant');
      expect(fedBack[1].content).assertEqual('');
      expect(fedBack[1].tool_calls !== undefined).assertTrue();
      expect(fedBack[2].role).assertEqual('tool');
      expect(fedBack[2].tool_call_id).assertEqual('c1');
      expect(fedBack[2].content).assertEqual('echo:hi');
    });

    it('loop_throws_tool_loop_max_steps_on_runaway', 0, async () => {
      const llm: ScriptedLlm = new ScriptedLlm([
        toolCallResult('c1', 'echo_probe', '{"payload":"hi"}'),
      ]);
      const registry: ToolRegistry = new ToolRegistry();
      registry.register(new EchoProbeTool());
      const loop: ToolLoop = new ToolLoop(llm);
      let threw: boolean = false;
      let kind: string = '';
      try {
        await loop.run([USER_MSG], registry, { maxSteps: 2 });
      } catch (e) {
        threw = true;
        kind = (e as LlmError).kind;
      }
      expect(threw).assertTrue();
      expect(kind).assertEqual('TOOL_LOOP_MAX_STEPS');
    });

    it('loop_feeds_tool_error_back_and_model_recovers', 0, async () => {
      const tool: EchoProbeTool = new EchoProbeTool();
      tool.failFirst = true;
      const llm: ScriptedLlm = new ScriptedLlm([
        toolCallResult('c1', 'echo_probe', '{"payload":"hi"}'),
        toolCallResult('c2', 'echo_probe', '{"payload":"hi"}'),
        textResult('recovered'),
      ]);
      const registry: ToolRegistry = new ToolRegistry();
      registry.register(tool);
      const loop: ToolLoop = new ToolLoop(llm);
      const final: LlmCallResult = await loop.run([USER_MSG], registry);
      expect(final.text).assertEqual('recovered');
      // 第二轮回喂含失败说明, 第三轮含成功回显
      expect(llm.seenMessages[1][2].content).assertEqual('transient failure');
      expect(llm.seenMessages[2][4].content).assertEqual('echo:hi');
    });
  });
}
