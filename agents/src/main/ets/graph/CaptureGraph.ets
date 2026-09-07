// MindTrace - CaptureGraph 最小 LangGraph 风格编排
// 2026-09-05 · D2 Ticket #12

import {
  AgentState,
  CaptureGraphError,
  CaptureNode,
  CaptureNodeResult,
  CaptureStep,
} from './AgentState';

export interface CaptureGraphOptions {
  persist?: boolean;
}

type ConditionalRouter = (state: AgentState) => CaptureStep;

export class CaptureGraph {
  private readonly nodes: Map<CaptureStep, CaptureNode> = new Map<CaptureStep, CaptureNode>();
  private readonly edges: Map<CaptureStep, CaptureStep> = new Map<CaptureStep, CaptureStep>();
  private readonly conditionalEdges: Map<CaptureStep, ConditionalRouter> = new Map<CaptureStep, ConditionalRouter>();

  addNode(step: CaptureStep, node: CaptureNode): void {
    this.nodes.set(step, node);
  }

  addEdge(from: CaptureStep, to: CaptureStep): void {
    this.edges.set(from, to);
  }

  addConditionalEdge(from: CaptureStep, router: ConditionalRouter): void {
    this.conditionalEdges.set(from, router);
  }

  async run(initialState: AgentState, options: CaptureGraphOptions = {}): Promise<AgentState> {
    let state: AgentState = this.copyState(initialState, initialState.persist, 'START');
    let current: CaptureStep = 'START';
    let lastStep: CaptureStep = 'START';

    while (current !== 'END') {
      const node: CaptureNode | undefined = this.nodes.get(current);
      if (node === undefined) {
        return this.withError(state, 'INVALID_GRAPH', 'Missing graph node: ' + current, current, false);
      }

      lastStep = current;
      state = this.copyState(state, state.persist, current);
      const result: CaptureNodeResult = await node(state);
      state = result.state;

      if (state.error !== undefined) {
        state = this.copyState(state, state.persist, 'END');
        break;
      }

      const conditional: ConditionalRouter | undefined = this.conditionalEdges.get(current);
      if (conditional !== undefined) {
        current = conditional(state);
      } else {
        const next: CaptureStep | undefined = this.edges.get(current);
        if (next === undefined) {
          return this.withError(state, 'INVALID_GRAPH', 'Missing graph edge: ' + current, current, false);
        }
        current = next;
      }
    }

    const finalStep: CaptureStep = lastStep === 'persist' ? 'persist' : 'END';
    return this.copyState(state, options.persist ?? state.persist, finalStep);
  }

  private copyState(state: AgentState, persist: boolean, currentStep: CaptureStep): AgentState {
    const copied: AgentState = {
      captureText: state.captureText,
      currentStep: currentStep,
      persist: persist,
    };
    if (state.payload !== undefined) {
      copied.payload = state.payload;
    }
    if (state.classification !== undefined) {
      copied.classification = state.classification;
    }
    if (state.knowledgeUnit !== undefined) {
      copied.knowledgeUnit = state.knowledgeUnit;
    }
    if (state.truthCheck !== undefined) {
      copied.truthCheck = state.truthCheck;
    }
    if (state.error !== undefined) {
      copied.error = state.error;
    }
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
    const copied: AgentState = {
      captureText: state.captureText,
      currentStep: 'END',
      persist: state.persist,
      error: error,
    };
    if (state.classification !== undefined) {
      copied.classification = state.classification;
    }
    if (state.knowledgeUnit !== undefined) {
      copied.knowledgeUnit = state.knowledgeUnit;
    }
    if (state.truthCheck !== undefined) {
      copied.truthCheck = state.truthCheck;
    }
    return copied;
  }
}
