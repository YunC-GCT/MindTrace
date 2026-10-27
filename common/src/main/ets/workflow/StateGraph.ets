import type { RunContext } from './RunContext';

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

  /**
   * 运行图。
   *
   * context === null（老调用方）：行为与接线前完全一致，maxNodeRuns 是唯一上限，
   *   超限消息仍是 `Workflow exceeded maxNodeRuns=N`。
   * context !== null：预算唯一来源是 context.budget，maxNodeRuns 被完全忽略，
   *   不是「maxNodeRuns 与 budget.limit 取小」。父子图共享同一个 budget 实例。
   *   每个节点执行前先 throwIfStopped() 再 budget.take()（被取消的 run 不消耗配额）；
   *   节点执行后再 throwIfStopped()，节点内刚取消时不会继续进入下一个节点。
   *
   * 节点异常不在这里 catch；CancellationError / DeadlineExceededError /
   * CaptureGraphError 原样向上抛，压平由 CaptureGraph 负责。
   */
  async run(initialState: State, maxNodeRuns: number = 128, context: RunContext | null = null): Promise<State> {
    let state: State = initialState;
    let current: Step = this.next(this.startStep, state);
    let nodeRuns: number = 0;
    while (current !== this.endStep) {
      if (context === null) {
        if (nodeRuns >= maxNodeRuns) {
          throw new StateGraphError('Workflow exceeded maxNodeRuns=' + maxNodeRuns.toString(), 'MAX_NODE_RUNS', current);
        }
      } else {
        context.throwIfStopped();
        if (!context.budget.take()) {
          throw new StateGraphError('Workflow exceeded run budget=' + context.budget.limit.toString(),
            'MAX_NODE_RUNS', current);
        }
      }
      const node: StateGraphNode<State> | undefined = this.nodes.get(current);
      if (node === undefined) {
        throw new StateGraphError('Missing workflow node: ' + current, 'INVALID_GRAPH', current);
      }
      state = await node(state);
      nodeRuns += 1;
      if (context !== null) {
        context.throwIfStopped();
      }
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
