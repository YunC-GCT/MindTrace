/**
 * AgentExtAbility.ets - 端 A2A Agent 扩展入口
 *
 * 路径: entry/src/main/ets/agentextability/AgentExtAbility.ets
 * 职责: 接收小艺端 A2A tasks/send 请求，并返回最小 Artifact 响应。
 * 依赖: @kit.AbilityKit (AgentExtensionAbility)
 *
 * 数据流:
 *   AgentHostProxy.onData() -> handleTask() -> StateGraph(plan) -> AgentHostProxy.sendData()
 *
 * 当前只跑一个 plan 节点（静态三步计划），后续把 plan 换成真实编排。
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式请求、响应和代理接口，避免 any / unknown。
 *   - JSON.parse() 结果通过显式类型断言进入协议模型。
 */
import { AgentExtensionAbility, common } from '@kit.AbilityKit';
import { StateGraph } from 'common';

const TASK_SEND_METHOD: string = 'tasks/send';
const DEFAULT_CONTEXT_ID: string = 'mindtrace-context';
const DEFAULT_TASK_ID: string = 'mindtrace-task';

interface A2ATask {
  id?: string;
  contextId?: string;
  query: string;
}

interface A2ATaskSendParams {
  task: A2ATask;
}

interface A2ATaskSendRequest {
  method: string;
  params: A2ATaskSendParams;
}

interface A2AArtifactPart {
  type: string;
  text: string;
}

interface A2ATaskSendResponse {
  contextId: string;
  taskId: string;
  artifactId: string;
  parts: Array<A2AArtifactPart>;
}

interface A2AErrorResponse {
  error: string;
}

function isTaskSendRequest(request: A2ATaskSendRequest): boolean {
  const params: A2ATaskSendParams = request.params;
  const task: A2ATask = params.task;
  return request.method === TASK_SEND_METHOD && typeof task.query === 'string';
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

export default class AgentExtAbility extends AgentExtensionAbility {
  onData(proxy: common.AgentHostProxy, data: string): void {
    let request: A2ATaskSendRequest;
    try {
      request = JSON.parse(data) as A2ATaskSendRequest;
    } catch (error) {
      this.sendError(proxy, 'invalid_request');
      return;
    }

    if (request.method !== TASK_SEND_METHOD) {
      this.sendError(proxy, 'unsupported_method');
      return;
    }

    if (!isTaskSendRequest(request)) {
      this.sendError(proxy, 'invalid_task');
      return;
    }

    const task: A2ATask = request.params.task;
    handleTask(task.query)
      .then((text: string): void => {
        const response: A2ATaskSendResponse = this.buildResponse(task, text);
        proxy.sendData(JSON.stringify(response));
      })
      .catch((): void => {
        this.sendError(proxy, 'task_failed');
      });
  }

  private buildResponse(task: A2ATask, text: string): A2ATaskSendResponse {
    const taskId: string = task.id ?? DEFAULT_TASK_ID;
    const contextId: string = task.contextId ?? DEFAULT_CONTEXT_ID;
    const part: A2AArtifactPart = {
      type: 'text',
      text: text,
    };
    return {
      contextId: contextId,
      taskId: taskId,
      artifactId: taskId + '-artifact',
      parts: [part],
    };
  }

  private sendError(proxy: common.AgentHostProxy, error: string): void {
    const response: A2AErrorResponse = { error: error };
    proxy.sendData(JSON.stringify(response));
  }
}
