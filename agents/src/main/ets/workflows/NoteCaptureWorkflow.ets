/**
 * NoteCaptureWorkflow.ets — capture / captureSet / analysisOnly 的 workflow（spec 039 S2）
 *
 * 路径: agents/src/main/ets/workflows/NoteCaptureWorkflow.ets
 * 职责: capture 命令的完整编排：装配 capture 子图（ocr → classify → structure → truth_check → persist）
 *       → 执行 → 把 AgentState 映射成 NoteOutcome 五终态（失败 / analysisOnly / 缺 unit / cancelled / committed）。
 *       取代原 NoteCaptureWorkflow 外壳与 NoteCaptureWorkflow 图装配器（spec 039 S2 收口，五层调用降为一层 workflow）。
 * 依赖: common（NoteCommand/NoteOutcome/BranchRequest/KnowledgeUnit/RunContext/NoteWritePort）、
 *       graph/AgentState + CaptureGraph + 五个节点工厂、agents/{TypeClassifier,KnowledgeModel,TruthCheckService}、
 *       core/dispatch/{DispatchOptions,UnitSupport}、WorkflowContext。
 * 数据流: CommandExecutor.dispatchCommand() → CommandRouter.resolve()=capture → 本 workflow.run()
 *       → buildGraph(options).run(initialState, runContext) → 终态映射 → NoteOutcome
 *
 * 边界:
 *   - 不发 run 级事件（run.started/terminal 由 CommandExecutor 统一发）；
 *   - 不直接碰 RDB：持久化由 PersistNode 经 NoteWritePort 完成（A1）；
 *   - 行为等价判据：#239 capture golden 快照（raw/ 零 diff）。
 */
import { Logger } from 'common';
import type {
  BranchRequest,
  KnowledgeUnit,
  NoteCommand,
  NoteOutcome,
  NoteWritePort,
  RunContext,
} from 'common';
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
import { TypeClassifier } from '../subagents/TypeClassifier';
import { KnowledgeModel } from '../subagents/KnowledgeModel';
import { TruthCheckService } from '../subagents/TruthCheckService';
import type { DispatchDomain, DispatchMode, Observability, RunControl, WritePorts } from '../core/dispatch/DispatchOptions';
import { seedTextFromRequest, sourceFromPayload } from '../core/dispatch/UnitSupport';
import type { NoteWorkflow, WorkflowContext } from './WorkflowContext';

const log = new Logger('NoteCaptureWorkflow');

export class NoteCaptureWorkflow implements NoteWorkflow {
  async run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome> {
    const req: BranchRequest = context.request;
    const writePorts: WritePorts = context.writePorts;
    const observability: Observability = context.observability;
    const runControl: RunControl = context.runControl;
    const mode: DispatchMode = context.mode;
    const domain: DispatchDomain = context.domain;
    const runContext: RunContext = context.runContext;
    const startedAt: number = context.startedAt;
    const operationId: string = req.operationId !== undefined ? req.operationId : 'legacy';
    const failedOutcome = (message: string, code: string, retryable: boolean): NoteOutcome => {
      const outcome: NoteOutcome = {
        kind: 'failed', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        code: code, message: message,
      };
      if (retryable) {
        outcome.retryable = true;
      }
      return outcome;
    };
    log.info('dispatch enter, source=' + req.source + ', payload.kind=' + req.payload.kind);
    const initial: AgentState = {
      captureText: seedTextFromRequest(req),
      source: sourceFromPayload(req.payload),
      payload: req.payload,
      currentStep: 'START',
      persist: mode.persist !== false,
      analysisOnly: mode.analysisOnly === true,
      subjectVocabulary: domain.subjectVocabulary ?? [],
      commitKey: req.commitKey,
      skipClassification: mode.skipLlmClassification === true,
      compactStructure: mode.compactStructure === true,
    };
    // 预算与取消是运行时属性，只走调用参数，不经 AgentState。
    const finalState: AgentState = await this.buildGraph(writePorts, observability, runControl).run(initial, runContext);
    const error: CaptureGraphError | undefined = finalState.error;
    const requestCancelled: boolean = runControl.cancellationToken !== undefined
      && runControl.cancellationToken.isCancelled();
    const cancelledTerminal: boolean = requestCancelled
      || (error !== undefined && error.kind === 'CANCELLED');
    if (cancelledTerminal) {
      // ADR-0019 (e)：先看事务结果，再看 token —— 已落库的写必须报 committed=true。
      return NoteCaptureWorkflow.cancelledResult(req, finalState, mode, startedAt);
    }
    if (error !== undefined) {
      log.error('capture graph failed: ' + error.kind + ' step=' + error.step + ' msg=' + error.message);
      const failed: NoteOutcome = failedOutcome(error.message, error.kind, error.retriable === true);
      if (finalState.classification !== undefined) {
        failed.classification = finalState.classification;
      }
      if (mode.includeRawText === true) {
        failed.recognizedText = finalState.captureText;
      }
      return failed;
    }
    if (finalState.analysisOnly) {
      if (finalState.classification === undefined) {
        log.info('dispatch analysis completed');
        return failedOutcome('capture workflow did not produce a classification', '', false);
      }
      const classificationOutcome: NoteOutcome = {
        kind: 'readyPreview', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        runId: '', checkpointId: '', classification: finalState.classification,
        recognizedText: mode.includeRawText === true ? finalState.captureText : undefined,
      };
      log.info('dispatch analysis completed');
      return classificationOutcome;
    }
    const unit: KnowledgeUnit | undefined = finalState.knowledgeUnit;
    if (unit === undefined) {
      const missing: NoteOutcome = failedOutcome('capture graph did not produce a knowledge unit', '', false);
      if (finalState.classification !== undefined) {
        missing.classification = finalState.classification;
      }
      if (mode.includeRawText === true) {
        missing.recognizedText = finalState.captureText;
      }
      return missing;
    }
    const success: NoteOutcome = {
      kind: 'committed', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
      noteId: unit.id, version: unit.version, unit: unit,
    };
    if (finalState.classification !== undefined) {
      success.classification = finalState.classification;
    }
    if (mode.includeRawText === true) {
      success.recognizedText = finalState.captureText;
    }
    log.info('dispatch completed persisted=' + finalState.persist.toString() + ' category=' + unit.category);
    return success;
  }

  /** 装配 capture 子图（原 NoteCaptureWorkflow.buildGraph；每次 run 按当次 options 装配）。 */
  private buildGraph(writePorts: WritePorts, observability: Observability, runControl: RunControl): CaptureGraph {
    const sink = observability.onNodeTiming;
    const timing: NodeTimingSink | undefined = sink === undefined
      ? undefined
      : (step: CaptureStep, ms: number): void => sink(step, ms);
    const graph: CaptureGraph = new CaptureGraph(timing);
    const classifier: TypeClassifier = new TypeClassifier(runControl.cancellationToken);
    const structure: KnowledgeModel = new KnowledgeModel(undefined, runControl.cancellationToken);
    const truth: TruthCheckService = new TruthCheckService();
    graph.addNode('capture', OcrNodeFactory.create(classifier));
    graph.addNode('classify', ClassifyNodeFactory.create(classifier));
    graph.addNode('structure', StructureNodeFactory.create(structure));
    graph.addNode('truth_check', TruthCheckNodeFactory.create(truth));
    const writePort: NoteWritePort | undefined = writePorts.noteWritePort;
    const dao: NoteDaoInterface | undefined = writePorts.dao;
    if (writePort !== undefined) {
      // #238 切片 A1：端口优先——幂等 / CAS / 结构化错误在端口层统一处理。
      graph.addNode('persist', PersistNodeFactory.createWithWritePort(writePort));
    } else if (dao !== undefined) {
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

  /**
   * ADR-0019 (e)：cancelled 终态。先读事务结果再读 token：
   * commitResult 存在 → committed=true 并带 noteId/version/commitKey；否则 committed=false。
   */
  private static cancelledResult(
    req: BranchRequest,
    finalState: AgentState,
    mode: DispatchMode,
    startedAt: number,
  ): NoteOutcome {
    const commitResult = finalState.commitResult;
    const cancelled: NoteOutcome = {
      kind: 'cancelled',
      operationId: req.operationId !== undefined ? req.operationId : 'legacy',
      route: 'D1',
      durationMs: Date.now() - startedAt,
      committed: commitResult !== undefined,
    };
    if (commitResult !== undefined) {
      cancelled.noteId = commitResult.noteId;
      cancelled.version = commitResult.version;
      cancelled.commitKey = commitResult.commitKey;
      if (finalState.knowledgeUnit !== undefined) {
        cancelled.unit = finalState.knowledgeUnit;
      }
    }
    if (finalState.classification !== undefined) {
      cancelled.classification = finalState.classification;
    }
    if (mode.includeRawText === true) {
      cancelled.recognizedText = finalState.captureText;
    }
    return cancelled;
  }
}
