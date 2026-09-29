// MindTrace - CaptureGraph 最小 LangGraph 风格编排
// 2026-09-05 · D2 Ticket #12

import {
  AgentState,
  CaptureGraphError,
  CaptureNode,
  CaptureNodeResult,
  CaptureStep,
  copyAgentState,
} from './AgentState';
import { StateGraph, StateGraphError, StateGraphNode } from 'common';

type GraphRoute = (state: AgentState) => CaptureStep;

export class CaptureGraph {
  private readonly graph: StateGraph<AgentState, CaptureStep>;

  constructor() {
    this.graph = new StateGraph<AgentState, CaptureStep>(
      'START',
      'END',
      (state: AgentState): boolean => state.error !== undefined,
    );
  }

  addNode(step: CaptureStep, node: CaptureNode): void {
    const workflowNode: StateGraphNode<AgentState> = async (input: AgentState): Promise<AgentState> => {
      const nodeInput: AgentState = this.copyState(input, input.persist, step);
      try {
        nodeInput.cancellationToken?.throwIfCancelled();
        const result: CaptureNodeResult = await node(nodeInput);
        result.state.cancellationToken?.throwIfCancelled();
        return result.state;
      } catch (e) {
        const message: string = e instanceof Error ? e.message : String(e);
        return this.withError(nodeInput, 'NODE_ERROR', message, step, false);
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

  async run(initialState: AgentState): Promise<AgentState> {
    let state: AgentState = this.copyState(initialState, initialState.persist, 'START');
    try {
      state = await this.graph.run(state);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      const step: CaptureStep = e instanceof StateGraphError ? this.captureStep(e.step) : state.currentStep;
      return this.withError(state, 'INVALID_GRAPH', message, step, false);
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
    const error: CaptureGraphError = cause === undefined
      ? { kind, message, step, retriable }
      : { kind, message, step, retriable, cause };
    return this.copyStateWithError(state, error);
  }

  private copyStateWithError(state: AgentState, error: CaptureGraphError): AgentState {
    const copied: AgentState = copyAgentState(state);
    copied.currentStep = 'END';
    copied.error = error;
    return copied;
  }
}
