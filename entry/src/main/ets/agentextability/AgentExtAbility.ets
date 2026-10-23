/**
 * AgentExtAbility.ets - 端 A2A Agent 扩展入口
 *
 * 路径: entry/src/main/ets/agentextability/AgentExtAbility.ets
 * 职责: 接收小艺端 A2A 的 JSON-RPC 2.0 请求（SendStreamingMessage / tasks/send），
 *       交给 handleTask() 执行，并用同一请求的 id 回一条 JSON-RPC 响应。
 * 依赖: @kit.AbilityKit (AgentExtensionAbility)、common (StateGraph)
 *
 * 数据流:
 *   onData(jsonrpc) -> handleTask(query) -> StateGraph(plan) -> 组装 task 结果 -> sendData(jsonrpc)
 *
 * 当前只跑一个 plan 节点（静态三步计划），后续把 plan 换成真实编排。
 */
import { AgentExtensionAbility, common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StateGraph } from 'common';

const TAG: string = 'MindTraceA2A';
const DOMAIN: number = 0xA2A0;

const METHOD_STREAM: string = 'SendStreamingMessage';
const METHOD_MESSAGE_SEND: string = 'SendMessage';
const METHOD_TASK_SEND: string = 'tasks/send';
const DEFAULT_CONTEXT_ID: string = 'mindtrace-context';

interface RpcPart {
  kind?: string;
  type?: string;
  text?: string;
}

interface RpcMessage {
  messageId?: string;
  contextId?: string;
  taskId?: string;
  role?: string;
  parts?: Array<RpcPart>;
}

interface RpcTask {
  id?: string;
  contextId?: string;
  query?: string;
}

interface RpcParams {
  message?: RpcMessage;
  task?: RpcTask;
}

interface RpcRequest {
  jsonrpc?: string;
  id?: string;
  method?: string;
  params?: RpcParams;
}

interface ResultPart {
  text: string;
  mediaType: string;
}

interface StatusBody {
  state: string;
}

interface StatusUpdateBody {
  taskId: string;
  contextId: string;
  status: StatusBody;
  final: boolean;
}

interface StatusUpdateResult {
  statusUpdate: StatusUpdateBody;
}

interface ArtifactBody {
  artifactId: string;
  parts: Array<ResultPart>;
}

interface ArtifactUpdateBody {
  taskId: string;
  contextId: string;
  artifact: ArtifactBody;
  append: boolean;
  lastChunk: boolean;
}

interface ArtifactUpdateResult {
  artifactUpdate: ArtifactUpdateBody;
}

interface TaskBody {
  id: string;
  contextId: string;
  status: StatusBody;
  artifacts: Array<ArtifactBody>;
}

interface TaskResult {
  task: TaskBody;
}

interface TaskResponse {
  jsonrpc: string;
  id: string;
  result: TaskResult;
}

interface StatusResponse {
  jsonrpc: string;
  id: string;
  result: StatusUpdateResult;
}

interface ArtifactResponse {
  jsonrpc: string;
  id: string;
  result: ArtifactUpdateResult;
}

interface RpcErrorBody {
  code: number;
  message: string;
}

interface RpcErrorResponse {
  jsonrpc: string;
  id: string;
  error: RpcErrorBody;
}

type PlanStep = 'start' | 'plan' | 'done';

interface PlanState {
  query: string;
  steps: string[];
}

/**
 * 最小图：start -> plan -> done。
 * plan 目前产出静态三步，接入批量生成后替换成真实编排。
 */
function buildPlanGraph(): StateGraph<PlanState, PlanStep> {
  const graph: StateGraph<PlanState, PlanStep> = new StateGraph<PlanState, PlanStep>('start', 'done');
  graph.addNode('plan', async (state: PlanState): Promise<PlanState> => {
    const steps: string[] = [
      '1. 从相册选图（Picker，最多 20 张）',
      '2. 逐张 OCR，抽取题干与知识点',
      '3. 生成结构化笔记，预览确认后写入本地库',
    ];
    const next: PlanState = { query: state.query, steps: steps };
    return next;
  });
  graph.addEdge('start', 'plan');
  graph.addEdge('plan', 'done');
  return graph;
}

/**
 * A2A 业务处理入口：把 query 交给图执行，返回可读的计划文本。
 *
 * @param query 用户输入
 * @returns 计划文本
 */
export async function handleTask(query: string): Promise<string> {
  const trimmed: string = query.trim();
  if (trimmed.length === 0) {
    return '没有收到内容，请再说一次要整理的题目范围。';
  }
  const state: PlanState = await buildPlanGraph().run({ query: trimmed, steps: [] });
  return '收到：' + state.query + '\n计划：\n' + state.steps.join('\n');
}

/** 从 message.parts 里拼出纯文本，兼容 kind=text 与 type=text 两种写法。 */
function extractText(message: RpcMessage | undefined): string {
  if (message === undefined || message.parts === undefined) {
    return '';
  }
  const chunks: string[] = [];
  const parts: Array<RpcPart> = message.parts;
  for (let i = 0; i < parts.length; i++) {
    const part: RpcPart = parts[i];
    // proto-JSON 的 parts 只有 mediaType + text，没有 kind/type；有 text 就当文本收
    if (typeof part.text === 'string' && part.text.length > 0) {
      chunks.push(part.text);
    }
  }
  return chunks.join('\n').trim();
}

function nextId(prefix: string): string {
  return prefix + '-' + Date.now().toString();
}

export default class AgentExtAbility extends AgentExtensionAbility {
  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate: 扩展被拉起');
  }

  onConnect(want: Want, proxy: common.AgentHostProxy): void {
    hilog.info(DOMAIN, TAG, 'onConnect: 小艺已连接');
  }

  onDisconnect(want: Want, proxy: common.AgentHostProxy): void {
    hilog.info(DOMAIN, TAG, 'onDisconnect');
  }

  onData(proxy: common.AgentHostProxy, data: string): void {
    hilog.info(DOMAIN, TAG, 'onData 收到 %{public}d 字节: %{public}s', data.length, data.substring(0, 1500));

    let request: RpcRequest;
    try {
      request = JSON.parse(data) as RpcRequest;
    } catch (error) {
      this.sendError(proxy, '', -32700, 'parse_error');
      return;
    }

    const id: string = request.id ?? '';
    const method: string = request.method ?? '';
    const params: RpcParams = request.params ?? {};

    if (method === METHOD_STREAM || method === METHOD_MESSAGE_SEND) {
      const message: RpcMessage | undefined = params.message;
      const query: string = extractText(message);
      const taskId: string = message?.taskId ?? message?.messageId ?? nextId('task');
      const contextId: string = message?.contextId ?? DEFAULT_CONTEXT_ID;
      hilog.info(DOMAIN, TAG, 'method=%{public}s taskId=%{public}s query=%{public}s', method, taskId, query);
      this.runAndReply(proxy, id, taskId, contextId, query);
      return;
    }

    if (method === METHOD_TASK_SEND) {
      const task: RpcTask | undefined = params.task;
      const query: string = task?.query ?? '';
      const taskId: string = task?.id ?? nextId('task');
      const contextId: string = task?.contextId ?? DEFAULT_CONTEXT_ID;
      hilog.info(DOMAIN, TAG, 'method=tasks/send taskId=%{public}s', taskId);
      this.runAndReply(proxy, id, taskId, contextId, query);
      return;
    }

    hilog.warn(DOMAIN, TAG, 'unsupported method=%{public}s', method);
    this.sendError(proxy, id, -32601, 'unsupported_method: ' + method);
  }

  private runAndReply(proxy: common.AgentHostProxy, rpcId: string, taskId: string,
    contextId: string, query: string): void {
    handleTask(query)
      .then((text: string): void => {
        const part: ResultPart = { text: text, mediaType: 'text/plain' };
        const artifact: ArtifactBody = { artifactId: taskId + '-artifact', parts: [part] };
        const task: TaskBody = {
          id: taskId,
          contextId: contextId,
          status: { state: 'TASK_STATE_COMPLETED' },
          artifacts: [artifact],
        };
        const response: TaskResponse = { jsonrpc: '2.0', id: rpcId, result: { task: task } };
        this.send(proxy, JSON.stringify(response));
      })
      .catch((): void => {
        this.sendError(proxy, rpcId, -32603, 'task_failed');
      });
  }

  private send(proxy: common.AgentHostProxy, payload: string): void {
    hilog.info(DOMAIN, TAG, 'sendData %{public}d 字节: %{public}s', payload.length, payload.substring(0, 300));
    proxy.sendData(payload);
  }

  private sendError(proxy: common.AgentHostProxy, rpcId: string, code: number, message: string): void {
    hilog.warn(DOMAIN, TAG, 'sendError code=%{public}d msg=%{public}s', code, message);
    const body: RpcErrorBody = { code: code, message: message };
    const response: RpcErrorResponse = { jsonrpc: '2.0', id: rpcId, error: body };
    proxy.sendData(JSON.stringify(response));
  }
}
