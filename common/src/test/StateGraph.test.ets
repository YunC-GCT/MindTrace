import { describe, expect, it } from '@ohos/hypium';
import { StateGraph, StateGraphError } from '../main/ets/Index';

type ProbeStep = 'START' | 'append_a' | 'append_b' | 'loop' | 'END';

interface ProbeState {
  text: string;
  count: number;
  halt: boolean;
}

function probeState(): ProbeState {
  const state: ProbeState = {
    text: '',
    count: 0,
    halt: false,
  };
  return state;
}

async function appendA(input: ProbeState): Promise<ProbeState> {
  const state: ProbeState = {
    text: input.text + 'A',
    count: input.count,
    halt: input.halt,
  };
  return state;
}

async function appendB(input: ProbeState): Promise<ProbeState> {
  const state: ProbeState = {
    text: input.text + 'B',
    count: input.count,
    halt: input.halt,
  };
  return state;
}

async function increment(input: ProbeState): Promise<ProbeState> {
  const state: ProbeState = {
    text: input.text,
    count: input.count + 1,
    halt: input.halt,
  };
  return state;
}

async function halt(input: ProbeState): Promise<ProbeState> {
  const state: ProbeState = {
    text: input.text,
    count: input.count,
    halt: true,
  };
  return state;
}

export default function stateGraphTest(): void {
  describe('StateGraph.workflow_runtime', () => {
    it('runs_linear_nodes_from_start_to_end', 0, async () => {
      const graph: StateGraph<ProbeState, ProbeStep> =
        new StateGraph<ProbeState, ProbeStep>('START', 'END');
      graph.addNode('append_a', appendA);
      graph.addNode('append_b', appendB);
      graph.addEdge('START', 'append_a');
      graph.addEdge('append_a', 'append_b');
      graph.addEdge('append_b', 'END');
      const result: ProbeState = await graph.run(probeState());
      expect(result.text).assertEqual('AB');
    });

    it('routes_conditionally_and_supports_bounded_cycles', 0, async () => {
      const graph: StateGraph<ProbeState, ProbeStep> =
        new StateGraph<ProbeState, ProbeStep>('START', 'END');
      graph.addNode('loop', increment);
      graph.addEdge('START', 'loop');
      graph.addConditionalEdge('loop', (state: ProbeState): ProbeStep => state.count < 3 ? 'loop' : 'END');
      const result: ProbeState = await graph.run(probeState());
      expect(result.count).assertEqual(3);
    });

    it('halts_on_domain_state_before_missing_edge', 0, async () => {
      const graph: StateGraph<ProbeState, ProbeStep> =
        new StateGraph<ProbeState, ProbeStep>('START', 'END', (state: ProbeState): boolean => state.halt);
      graph.addNode('append_a', halt);
      graph.addEdge('START', 'append_a');
      const result: ProbeState = await graph.run(probeState());
      expect(result.halt).assertTrue();
    });

    it('rejects_invalid_graph_and_runaway_cycle', 0, async () => {
      const missingEdge: StateGraph<ProbeState, ProbeStep> =
        new StateGraph<ProbeState, ProbeStep>('START', 'END');
      let invalidKind: string = '';
      try {
        await missingEdge.run(probeState());
      } catch (e) {
        invalidKind = (e as StateGraphError).kind;
      }
      expect(invalidKind).assertEqual('INVALID_GRAPH');

      const cycle: StateGraph<ProbeState, ProbeStep> =
        new StateGraph<ProbeState, ProbeStep>('START', 'END');
      cycle.addNode('loop', increment);
      cycle.addEdge('START', 'loop');
      cycle.addConditionalEdge('loop', (state: ProbeState): ProbeStep => 'loop');
      let limitKind: string = '';
      try {
        await cycle.run(probeState(), 2);
      } catch (e) {
        limitKind = (e as StateGraphError).kind;
      }
      expect(limitKind).assertEqual('MAX_NODE_RUNS');
    });
  });
}
