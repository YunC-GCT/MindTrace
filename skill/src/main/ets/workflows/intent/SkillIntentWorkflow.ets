import { StateGraph, ToolRegistry, ToolResult } from 'common';
import { SkillIntentRequest, SkillIntentResult, SkillIntentState, SkillIntentStep } from './SkillIntentState';

export class SkillIntentWorkflow {
  private readonly registry: ToolRegistry;

  constructor(registry: ToolRegistry) {
    this.registry = registry;
  }

  async run(request: SkillIntentRequest): Promise<SkillIntentResult> {
    const initial: SkillIntentState = {
      request: request,
      currentStep: 'START',
    };
    const graph: StateGraph<SkillIntentState, SkillIntentStep> = this.buildGraph();
    const finalState: SkillIntentState = await graph.run(initial);
    if (finalState.result === undefined) {
      const missing: SkillIntentResult = {
        ok: false,
        content: 'Skill intent workflow produced no result',
        errorKind: 'TOOL_ERROR',
      };
      return missing;
    }
    return finalState.result;
  }

  private buildGraph(): StateGraph<SkillIntentState, SkillIntentStep> {
    const graph: StateGraph<SkillIntentState, SkillIntentStep> =
      new StateGraph<SkillIntentState, SkillIntentStep>('START', 'END');
    graph.addNode('route_action', async (input: SkillIntentState): Promise<SkillIntentState> => {
      return SkillIntentWorkflow.copyState(input, 'route_action');
    });
    graph.addNode('execute_search', async (input: SkillIntentState): Promise<SkillIntentState> => {
      let result: SkillIntentResult;
      try {
        const toolResult: ToolResult = await this.registry.execute('note_query', input.request.argsJson);
        result = {
          ok: toolResult.ok,
          content: toolResult.content,
        };
        if (!toolResult.ok) {
          result.errorKind = 'TOOL_ERROR';
        }
      } catch (e) {
        result = {
          ok: false,
          content: e instanceof Error ? e.message : String(e),
          errorKind: 'TOOL_ERROR',
        };
      }
      const next: SkillIntentState = SkillIntentWorkflow.copyState(input, 'execute_search');
      next.result = result;
      return next;
    });
    graph.addNode('unsupported', async (input: SkillIntentState): Promise<SkillIntentState> => {
      const result: SkillIntentResult = {
        ok: false,
        content: 'Unsupported skill intent: ' + input.request.action,
        errorKind: 'UNSUPPORTED_INTENT',
      };
      const next: SkillIntentState = SkillIntentWorkflow.copyState(input, 'unsupported');
      next.result = result;
      return next;
    });
    graph.addEdge('START', 'route_action');
    graph.addConditionalEdge('route_action', (state: SkillIntentState): SkillIntentStep => {
      return state.request.target === 'search_note' ? 'execute_search' : 'unsupported';
    });
    graph.addEdge('execute_search', 'END');
    graph.addEdge('unsupported', 'END');
    return graph;
  }

  private static copyState(input: SkillIntentState, step: SkillIntentStep): SkillIntentState {
    const next: SkillIntentState = {
      request: input.request,
      currentStep: step,
    };
    if (input.result !== undefined) {
      next.result = input.result;
    }
    return next;
  }
}
