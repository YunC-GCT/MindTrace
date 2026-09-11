export type StateGraphNode<State> = (state: State) => Promise<State>;
export type StateGraphRoute<State, Step extends string> = (state: State) => Step;
export type StateGraphHalt<State> = (state: State) => boolean;

export type StateGraphErrorKind = 'INVALID_GRAPH' | 'MAX_NODE_RUNS';

export class StateGraphError extends Error {
  kind: StateGraphErrorKind;
  step: string;

  constructor(message: string, kind: StateGraphErrorKind, step: string) {
    super(message);
    this.name = 'StateGraphError';
    this.kind = kind;
    this.step = step;
  }
}

export class StateGraph<State, Step extends string> {
  private readonly startStep: Step;
  private readonly endStep: Step;
  private readonly haltWhen?: StateGraphHalt<State>;
  private readonly nodes: Map<Step, StateGraphNode<State>> = new Map<Step, StateGraphNode<State>>();
  private readonly edges: Map<Step, Step> = new Map<Step, Step>();
  private readonly conditionalEdges: Map<Step, StateGraphRoute<State, Step>> =
    new Map<Step, StateGraphRoute<State, Step>>();

  constructor(startStep: Step, endStep: Step, haltWhen?: StateGraphHalt<State>) {
    this.startStep = startStep;
    this.endStep = endStep;
    this.haltWhen = haltWhen;
  }

  addNode(step: Step, node: StateGraphNode<State>): void {
    if (step === this.startStep || step === this.endStep || this.nodes.has(step)) {
      throw new StateGraphError('Invalid workflow node: ' + step, 'INVALID_GRAPH', step);
    }
    this.nodes.set(step, node);
  }

  addEdge(from: Step, to: Step): void {
    if (from === this.endStep || this.edges.has(from) || this.conditionalEdges.has(from)) {
      throw new StateGraphError('Invalid workflow edge from: ' + from, 'INVALID_GRAPH', from);
    }
    this.edges.set(from, to);
  }

  addConditionalEdge(from: Step, route: StateGraphRoute<State, Step>): void {
    if (from === this.endStep || this.edges.has(from) || this.conditionalEdges.has(from)) {
      throw new StateGraphError('Invalid conditional edge from: ' + from, 'INVALID_GRAPH', from);
    }
    this.conditionalEdges.set(from, route);
  }

  async run(initialState: State, maxNodeRuns: number = 128): Promise<State> {
    let state: State = initialState;
    let current: Step = this.next(this.startStep, state);
    let nodeRuns: number = 0;
    while (current !== this.endStep) {
      if (nodeRuns >= maxNodeRuns) {
        throw new StateGraphError('Workflow exceeded maxNodeRuns=' + maxNodeRuns.toString(), 'MAX_NODE_RUNS', current);
      }
      const node: StateGraphNode<State> | undefined = this.nodes.get(current);
      if (node === undefined) {
        throw new StateGraphError('Missing workflow node: ' + current, 'INVALID_GRAPH', current);
      }
      state = await node(state);
      nodeRuns += 1;
      if (this.haltWhen !== undefined && this.haltWhen(state)) {
        return state;
      }
      current = this.next(current, state);
    }
    return state;
  }

  private next(from: Step, state: State): Step {
    const route: StateGraphRoute<State, Step> | undefined = this.conditionalEdges.get(from);
    const nextStep: Step | undefined = route !== undefined ? route(state) : this.edges.get(from);
    if (nextStep === undefined) {
      throw new StateGraphError('Missing workflow edge: ' + from, 'INVALID_GRAPH', from);
    }
    if (nextStep !== this.endStep && !this.nodes.has(nextStep)) {
      throw new StateGraphError('Missing workflow node: ' + nextStep, 'INVALID_GRAPH', nextStep);
    }
    return nextStep;
  }
}
