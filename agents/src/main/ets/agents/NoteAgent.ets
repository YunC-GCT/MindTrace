// MindTrace - NoteAgent（笔记子 Agent 薄包装）· #241 切片 1
/**
 * NoteAgent.ets — 笔记子 Agent：持有 capture 子图，只装配不实现
 *
 * 路径: agents/src/main/ets/agents/NoteAgent.ets
 * 职责: 把 ocr / classify / structure / truth_check / persist 五个现有节点装配成 capture 子图并执行；
 *       不写 prompt、不改节点语义、不直接碰 RDB。
 *
 * 边界（#241 切片 1）:
 *   - 这一片只把「图装配」从 Dispatcher 搬出来，图仍由 CaptureGraph 承载；
 *   - 下一片才把它接成 Dispatcher 主图里的一个节点（§17.3 内核差距 1）。
 *   - 行为等价判据：#239 的 capture golden 快照，输出必须逐字段一致。
 */
import type { CancellationToken, RunContext } from 'common';
import {
  AgentState,
  CaptureGraphError,
  CaptureNodeResult,
  CaptureStep,
  copyAgentState,
} from '../graph/AgentState';
import { CaptureGraph } from '../graph/CaptureGraph';
import type { NodeTimingSink } from '../graph/CaptureGraph';
import { OcrNodeFactory } from '../graph/nodes/OcrNode';
import { ClassifyNodeFactory } from '../graph/nodes/ClassifyNode';
import { StructureNodeFactory } from '../graph/nodes/StructureNode';
import { TruthCheckNodeFactory } from '../graph/nodes/TruthCheckNode';
import { PersistNodeFactory } from '../graph/nodes/PersistNode';
import { NoteDaoInterface } from '../models/NoteDaoInterface';
import { TypeClassifier } from './TypeClassifier';
import { KnowledgeModel } from './KnowledgeModel';
import { TruthCheckService } from './TruthCheckService';

export interface NoteAgentOptions {
  dao?: NoteDaoInterface;
  cancellationToken?: CancellationToken;
  onNodeTiming?: (step: string, elapsedMs: number) => void;
}

export class NoteAgent {
  private readonly options: NoteAgentOptions;

  constructor(options: NoteAgentOptions) {
    this.options = options;
  }

  /** 跑一次 capture 子图；上下文（runId / deadline / 预算 / 取消）由调用方传入 */
  async run(initialState: AgentState, context: RunContext | null = null): Promise<AgentState> {
    const graph: CaptureGraph = this.buildGraph();
    return await graph.run(initialState, context);
  }

  private buildGraph(): CaptureGraph {
    const sink = this.options.onNodeTiming;
    const timing: NodeTimingSink | undefined = sink === undefined
      ? undefined
      : (step: CaptureStep, ms: number): void => sink(step, ms);
    const graph: CaptureGraph = new CaptureGraph(timing);
    const classifier: TypeClassifier = new TypeClassifier(this.options.cancellationToken);
    const structure: KnowledgeModel = new KnowledgeModel(undefined, this.options.cancellationToken);
    const truth: TruthCheckService = new TruthCheckService();
    graph.addNode('capture', OcrNodeFactory.create(classifier));
    graph.addNode('classify', ClassifyNodeFactory.create(classifier));
    graph.addNode('structure', StructureNodeFactory.create(structure));
    graph.addNode('truth_check', TruthCheckNodeFactory.create(truth));
    const dao: NoteDaoInterface | undefined = this.options.dao;
    if (dao !== undefined) {
      graph.addNode('persist', PersistNodeFactory.create(dao));
    } else {
      graph.addNode('persist', async (input: AgentState): Promise<CaptureNodeResult> => {
        const next: AgentState = copyAgentState(input);
        const error: CaptureGraphError = {
          kind: 'PERSIST_DAO_REQUIRED',
          message: 'persist requested but no NoteDaoInterface was provided',
          step: 'persist',
          retriable: false,
        };
        next.error = error;
        const result: CaptureNodeResult = { state: next };
        return result;
      });
    }
    graph.addEdge('START', 'capture');
    graph.addEdge('capture', 'classify');
    graph.addConditionalEdge('classify', (input: AgentState): CaptureStep => {
      return input.analysisOnly ? 'END' : 'structure';
    });
    graph.addEdge('structure', 'truth_check');
    graph.addConditionalEdge('truth_check', (input: AgentState): CaptureStep => input.persist ? 'persist' : 'END');
    graph.addEdge('persist', 'END');
    return graph;
  }
}
