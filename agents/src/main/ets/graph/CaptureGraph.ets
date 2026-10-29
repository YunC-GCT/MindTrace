// MindTrace - CaptureGraph 最小 LangGraph 风格编排
// 2026-09-05 · D2 Ticket #12

import {
  AgentState,
  CaptureGraphError,
  CaptureNode,
  CaptureNodeResult,
  CaptureStep,
  copyAgentState,
  isCaptureGraphError,
} from './AgentState';
import {
  StateGraph,
  StateGraphError,
  StateGraphNode,
  isCancellationError,
  isDeadlineExceededError,
} from 'common';
import type { RunContext } from 'common';

type GraphRoute = (state: AgentState) => CaptureStep;

export type NodeTimingSink = (step: CaptureStep, elapsedMs: number) => void;

export class CaptureGraph {
  private readonly graph: StateGraph<AgentState, CaptureStep>;
  private readonly onNodeTiming?: NodeTimingSink;

  constructor(onNodeTiming?: NodeTimingSink) {
    this.onNodeTiming = onNodeTiming;
    this.graph = new StateGraph<AgentState, CaptureStep>(
      'START',
      'END',
      (state: AgentState): boolean => state.error !== undefined,
    );
  }

  addNode(step: CaptureStep, node: CaptureNode): void {
    const workflowNode: StateGraphNode<AgentState> = async (input: AgentState,
      context?: RunContext | null): Promise<AgentState> => {
      const startedAt: number = Date.now();
      let nodeInput: AgentState = input;
      try {
        nodeInput = this.copyState(input, input.persist, step);
        context?.throwIfStopped();
        const result: CaptureNodeResult = await node(nodeInput, context);
        context?.throwIfStopped();
        return result.state;
      } catch (e) {
        if (isCancellationError(e as Object)
          || isDeadlineExceededError(e as Object)
          || isCaptureGraphError(e as Object)
          || e instanceof StateGraphError) {
          // 原样越过 CaptureGraph 边界，不改写 kind / step / retriable。
          // arkts-limited-throw 只允许 `throw new ...`，这里用 Promise.reject
          // 保留同一个错误实例（async 包装器的语义仍是 rethrow）。
          return Promise.reject(e);
        }
        const message: string = e instanceof Error ? e.message : String(e);
        return this.withError(nodeInput, 'NODE_ERROR', message, step, false);
      } finally {
        if (this.onNodeTiming !== undefined) {
          this.onNodeTiming(step, Date.now() - startedAt);
        }
      }
    };
    this.graph.addNode(step, workflowNode);
  }

  addEdge(from: CaptureStep, to: CaptureStep): void {
    this.graph.addEdge(from, to);
  }

  addConditionalEdge(from: CaptureStep, router: GraphRoute): void {
    this.graph.addConditionalEdge(from, router);
  }

  async run(initialState: AgentState, context: RunContext | null = null): Promise<AgentState> {
    let state: AgentState = this.copyState(initialState, initialState.persist, 'START');
    try {
      state = await this.graph.run(state, 128, context);
    } catch (e) {
      if (isCancellationError(e as Object)) {
        const message: string = (e as Error).message;
        return this.withError(state, 'CANCELLED', message, state.currentStep, false);
      }
      if (isDeadlineExceededError(e as Object)) {
        const message: string = (e as Error).message;
        return this.withError(state, 'DEADLINE_EXCEEDED', message, state.currentStep, false);
      }
      if (isCaptureGraphError(e as Object)) {
        // 原样搬进 state.error：kind / message / step / retriable / cause 都不改写。
        return this.copyStateWithError(state, e as CaptureGraphError);
      }
      if (e instanceof StateGraphError) {
        const graphError: StateGraphError = e as StateGraphError;
        return this.withError(state, graphError.kind, graphError.message,
          this.captureStep(graphError.step), false);
      }
      const message: string = e instanceof Error ? e.message : String(e);
      return this.withError(state, 'INVALID_GRAPH', message, state.currentStep, false);
    }
    const finalStep: CaptureStep = state.error === undefined && state.currentStep === 'persist' ? 'persist' : 'END';
    return this.copyState(state, state.persist, finalStep);
  }

  private captureStep(value: string): CaptureStep {
    if (value === 'capture') { return 'capture'; }
    if (value === 'classify') { return 'classify'; }
    if (value === 'structure') { return 'structure'; }
    if (value === 'truth_check') { return 'truth_check'; }
    if (value === 'persist') { return 'persist'; }
    if (value === 'END') { return 'END'; }
    return 'START';
  }

  private copyState(state: AgentState, persist: boolean, currentStep: CaptureStep): AgentState {
    const copied: AgentState = copyAgentState(state);
    copied.currentStep = currentStep;
    copied.persist = persist;
    return copied;
  }

  private withError(
    state: AgentState,
    kind: string,
    message: string,
    step: CaptureStep,
    retriable: boolean,
    cause?: string,
  ): AgentState {
    const error: CaptureGraphError = {
      kind: kind,
      message: message,
      step: step,
      retriable: retriable,
      cause: cause,
    };
    return this.copyStateWithError(state, error);
  }

  private copyStateWithError(state: AgentState, error: CaptureGraphError): AgentState {
    const copied: AgentState = copyAgentState(state);
    copied.currentStep = 'END';
    copied.error = error;
    return copied;
  }
}
