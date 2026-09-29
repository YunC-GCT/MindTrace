import { LlmCaller } from '../../llm/LlmGuard';
import { ChatMessage, LlmCallResult, LlmError } from '../../llm/LlmTypes';
import { ToolRegistry } from '../../tools/ToolRegistry';
import { StateGraph } from '../StateGraph';
import { ToolCallingState, ToolCallingStep, ToolLoopOptions } from './ToolCallingState';
import { CallModelNode } from './nodes/CallModelNode';
import { ExecuteToolsNode } from './nodes/ExecuteToolsNode';

const DEFAULT_MAX_STEPS: number = 4;

export class ToolCallingWorkflow {
  private readonly registry: ToolRegistry;
  private readonly callModelNode: CallModelNode;
  private readonly executeToolsNode: ExecuteToolsNode;

  constructor(llm: LlmCaller, registry: ToolRegistry) {
    this.registry = registry;
    this.callModelNode = new CallModelNode(llm);
    this.executeToolsNode = new ExecuteToolsNode(registry);
  }

  async run(messages: ChatMessage[], options?: ToolLoopOptions): Promise<LlmCallResult> {
    const maxSteps: number = options !== undefined && options.maxSteps !== undefined
      ? options.maxSteps
      : DEFAULT_MAX_STEPS;
    if (maxSteps <= 0) {
      throw new LlmError('tool loop exceeded maxSteps=' + maxSteps.toString(), 'TOOL_LOOP_MAX_STEPS');
    }
    const initial: ToolCallingState = {
      messages: messages.slice(0),
      definitions: this.registry.listDefinitions(),
      maxSteps: maxSteps,
      stepCount: 0,
      currentStep: 'START',
    };
    if (options !== undefined && options.callOptions !== undefined) {
      initial.callOptions = options.callOptions;
    }
    const graph: StateGraph<ToolCallingState, ToolCallingStep> = this.buildGraph();
    const finalState: ToolCallingState = await graph.run(initial, maxSteps * 3 + 4);
    if (finalState.lastResult === undefined) {
      throw new LlmError('tool workflow produced no result', 'EMPTY_RESPONSE');
    }
    return finalState.lastResult;
  }

  private buildGraph(): StateGraph<ToolCallingState, ToolCallingStep> {
    const graph: StateGraph<ToolCallingState, ToolCallingStep> =
      new StateGraph<ToolCallingState, ToolCallingStep>('START', 'END');
    graph.addNode('call_model', (input: ToolCallingState): Promise<ToolCallingState> => this.callModelNode.run(input));
    graph.addNode('execute_tools',
      (input: ToolCallingState): Promise<ToolCallingState> => this.executeToolsNode.run(input));
    graph.addNode('max_steps_error', async (input: ToolCallingState): Promise<ToolCallingState> => {
      throw new LlmError('tool loop exceeded maxSteps=' + input.maxSteps.toString(), 'TOOL_LOOP_MAX_STEPS');
    });
    graph.addEdge('START', 'call_model');
    graph.addConditionalEdge('call_model', (state: ToolCallingState): ToolCallingStep => {
      if (state.toolCalls === undefined || state.toolCalls.length === 0) {
        return 'END';
      }
      return 'execute_tools';
    });
    graph.addConditionalEdge('execute_tools', (state: ToolCallingState): ToolCallingStep => {
      return state.stepCount >= state.maxSteps ? 'max_steps_error' : 'call_model';
    });
    graph.addEdge('max_steps_error', 'END');
    return graph;
  }
}
