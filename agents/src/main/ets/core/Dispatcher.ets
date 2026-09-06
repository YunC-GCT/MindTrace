// MindTrace - Dispatcher (主 Agent 调度中枢) · D2 CaptureGraph host
// 2026-09-05 · D2 Ticket #6: 唯一最终公共入口 dispatch()
import { TypeClassifier } from '../agents/TypeClassifier';
import { KnowledgeModel } from '../agents/KnowledgeModel';
import { TruthCheckService } from '../agents/TruthCheckService';
import { Logger, KnowledgeUnit, DispatchRequest, DispatchResult } from 'common';
import type { DispatchPayload } from 'common';
import { AgentState, CaptureGraphError, CaptureStep } from '../graph/AgentState';
import { CaptureGraph } from '../graph/CaptureGraph';
import { OcrNodeFactory } from '../graph/nodes/OcrNode';
import { ClassifyNodeFactory } from '../graph/nodes/ClassifyNode';
import { StructureNodeFactory } from '../graph/nodes/StructureNode';
import { TruthCheckNodeFactory } from '../graph/nodes/TruthCheckNode';
import { PersistNodeFactory } from '../graph/nodes/PersistNode';
import { NoteDaoInterface } from '../models/NoteDaoInterface';

const log = new Logger('Dispatcher');

export interface DispatchOptions {
  persist?: boolean;
  includeRawText?: boolean;
  dao?: NoteDaoInterface;
}

export class Dispatcher {
  private static sourceFromPayload(payload: DispatchPayload): string {
    if (payload.kind === 'image') { return 'camera_capture'; }
    if (payload.kind === 'text') { return 'manual'; }
    return 'file_import';
  }

  // D2 唯一最终公共入口: 跑 CaptureGraph, 失败返回结构化错误。
  async dispatch(req: DispatchRequest, context?: Context, options: DispatchOptions = {}): Promise<DispatchResult> {
    return await this.dispatchRequest(req, options);
  }

  private async dispatchRequest(req: DispatchRequest, options: DispatchOptions): Promise<DispatchResult> {
    const t0: number = Date.now();
    log.info('dispatch enter, source=' + req.source + ', payload.kind=' + req.payload.kind);
    const initial: AgentState = {
      captureText: '',
      currentStep: 'START',
      persist: options.persist !== false,
    };
    const graph: CaptureGraph = this.buildGraph(req, options);
    const finalState: AgentState = await graph.run(initial, { persist: options.persist !== false });
    const error: CaptureGraphError | undefined = finalState.error;
    if (error !== undefined) {
      log.error('capture graph failed: ' + error.kind + ' step=' + error.step + ' msg=' + error.message);
      return {
        success: false,
        route: 'D1',
        errorMessage: error.message,
        durationMs: Date.now() - t0,
      };
    }
    const unit: KnowledgeUnit | undefined = finalState.knowledgeUnit;
    if (unit === undefined) {
      return {
        success: false,
        route: 'D1',
        errorMessage: 'capture graph did not produce a knowledge unit',
        durationMs: Date.now() - t0,
      };
    }
    return {
      success: true,
      route: 'D1',
      data: unit,
      durationMs: Date.now() - t0,
    };
  }

  buildGraph(req: DispatchRequest, options: DispatchOptions = {}): CaptureGraph {
    const graph: CaptureGraph = new CaptureGraph();
    const classifier: TypeClassifier = new TypeClassifier();
    const structure: KnowledgeModel = new KnowledgeModel();
    const truth: TruthCheckService = new TruthCheckService();
    graph.addNode('START', async (input: AgentState) => {
      const seed: AgentState = {
        captureText: this.seedText(req),
        currentStep: input.currentStep,
        persist: input.persist,
      };
      return { state: seed };
    });
    graph.addNode('capture', OcrNodeFactory.create(classifier));
    graph.addNode('classify', ClassifyNodeFactory.create(classifier));
    graph.addNode('structure', StructureNodeFactory.create(structure));
    graph.addNode('truth_check', TruthCheckNodeFactory.create(truth));
    if (options.dao !== undefined) {
      graph.addNode('persist', PersistNodeFactory.create(options.dao));
    } else {
      graph.addNode('persist', async (input: AgentState) => ({ state: input }));
    }
    graph.addEdge('START', 'capture');
    graph.addEdge('capture', 'classify');
    graph.addEdge('classify', 'structure');
    graph.addEdge('structure', 'truth_check');
    graph.addConditionalEdge('truth_check', (input: AgentState): CaptureStep => input.persist ? 'persist' : 'END');
    return graph;
  }

  private seedText(req: DispatchRequest): string {
    if (req.payload.kind === 'text') {
      return req.payload.text;
    }
    return '';
  }
}