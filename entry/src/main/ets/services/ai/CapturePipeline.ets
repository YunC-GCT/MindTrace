/**
 * CapturePipeline.ets — 拍照 / 文本 / 批量采集链路（从 AiService 抽出）
 *
 * 路径: entry/src/main/ets/services/ai/CapturePipeline.ets
 * 职责: 图片准备 → 命令式 dispatch（capture/analysisOnly/批量 set）→ completed 终态 → 文搜图索引；
 *       以及文本/A2A 入库（ingestText / ingestTextOutcome）与批量回执适配。
 * 依赖: Dispatcher.dispatchCommand/dispatchSetCommand / AiServicePorts / CaptureTiming。
 *
 * 拆出原因（2026-10-31）：AiService 拆分切片 6（最后一片）；AiService 收敛为纯 facade。
 */
// ============================================================================
//  services/AiService.ets — 拍照→AI 整链入口
//  ----------------------------------------------------------------------------
//  职责: 拍照/选图入口与对话笔记草稿、确认编排。
//
//  接口约定:
//    - capture(imageUri, userText?): Promise<KnowledgeUnit>
//        拍照/相册的入口。绝不只走 LLM 对话,必须进入 capture pipeline:
//        Dispatcher -> image/OCR/MCP 识别 -> 分类 -> 知识结构化 -> 入库。
//
//  UI 端约束: 凡是发图的,都必须调 capture() 而不是 LLM 对话。
//
//  整链调用链:
//    ImageUriResolver.resolve(uri)  // file:// URI 复制到沙箱
//    -> Dispatcher.dispatch(payload)  // 调度中枢
//      -> TypeClassifier.classify()   // OCR + DeepSeek 3×3 分类
//        -> OcrTool.recognize()       // 本地 FastAPI HTTP OCR
//      -> KnowledgeModel.structure()  // 模板填充 + 真值检验
//    -> KnowledgeUnitWriteService.create(unit) // KnowledgeUnit + revision 事务持久化
//  ============================================================================

import {
  KnowledgeUnit,
  ClassificationResult,
  BranchRequest,
  DispatchPayload,
  Logger,
  ImageSearchIndexRegistry,
  NoteDraftReadyEvent,
  NoteGenerationRequest,
  NoteGenerationRoute,
  NoteGenerationProgressSink,
  PreparedCandidate,
  NoteGenerationCheckpoint,
  NoteGenerationResult,
  NoteGenerationRun,
  NoteGenerationRepository as NoteGenerationRepositoryContract,
  SourceFragment,
  SourceBundle,
  NoteContextClarification,
  NoteTopicCandidate,
  NoteGenerationRecovery,
  sourceFingerprint,
  IncrementalManifest,
  IncrementalSection,
  parseIncrementalSections,
  buildIncrementalManifest,
  CaptureSetResult,
  CaptureSetItemResult,
  TextPayload,
} from 'common';
import type { NoteBatchOutcome, NoteCommand, NoteOutcome } from 'common';
import { Dispatcher, NoteDaoInterface, planCaptureSet } from 'agents';
import type { PlannedProblem, SetImageText, SetPlan } from 'agents';
import { common } from '@kit.AbilityKit';
import { ImageUriResolver, ResolvedImageFile } from '../ImageUriResolver';
import { OcrService } from '../OcrService';
import { SubjectVocabularyService } from '../SubjectVocabularyService';
import { ConversationRunIdPolicy, SessionIdPolicy } from '../ConversationIdentity';
import { NoteGenerationRepositoryFactory } from '../NoteGenerationRepositoryFactory';
import { AgentMemoryService } from '../AgentMemoryService';
import { NoteGenerationContextBuilder } from '../NoteGenerationContextBuilder';
import { CaptureTiming } from './CaptureTiming';
import { AiServicePorts } from './AiServicePorts';
import { ClarificationRegistry } from './ClarificationRegistry';
import { DraftCommitService } from './DraftCommitService';
import { DraftPipeline } from './DraftPipeline';
import { ClarificationPipeline } from './ClarificationPipeline';
import { CancellationToken } from 'common';


const log: Logger = new Logger('CapturePipeline');

export class CapturePipeline {
  private readonly context: common.Context | undefined;
  private readonly includeUiEffects: boolean;

  constructor(context: common.Context | undefined, includeUiEffects: boolean) {
    this.context = context;
    this.includeUiEffects = includeUiEffects;
  }

  async capture(imageUri: string, userText?: string): Promise<KnowledgeUnit> {
    const startedAt: number = Date.now();
    const seq: number = CaptureTiming.nextSeq();
    let resolveMs: number = 0;
    let outcome: string = 'ok';
    const nodeTotals: Map<string, number> = new Map<string, number>();
    const nodeVisits: Map<string, number> = new Map<string, number>();
    const onNodeTiming = (step: string, elapsedMs: number): void => {
      nodeTotals.set(step, (nodeTotals.get(step) ?? 0) + elapsedMs);
      nodeVisits.set(step, (nodeVisits.get(step) ?? 0) + 1);
    };
    log.info('capture start, imageUri=' + imageUri);
    try {
      if (this.context === undefined) {
        throw new Error('CapturePipeline.capture 需要 UIAbilityContext 来准备图片文件');
      }

      // 1) 把 file:// URI 复制到沙箱(本地路径,OCR/Dao 都能访问)
      const resolveStartedAt: number = Date.now();
      const resolved: ResolvedImageFile = await new ImageUriResolver(this.context as common.UIAbilityContext).resolve(imageUri);
      resolveMs = Date.now() - resolveStartedAt;
      log.info('capture 图片已准备,本地路径=' + resolved.localPath);

      // 2) 走整链
      const unit: KnowledgeUnit = await this.processAndPersist({
        kind: 'image',
        imageUri: resolved.localPath,
        userText: userText,
      }, onNodeTiming);

      // 3) 落库后再建文搜图索引：索引失败不影响笔记本身，只记日志
      await this.indexForSearch(resolved.localPath, unit.id);
      return unit;
    } catch (error) {
      outcome = 'error';
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(String(error));
    } finally {
      const totalMs: number = Date.now() - startedAt;
      CaptureTiming.logCapture(seq, outcome, resolveMs, nodeTotals, nodeVisits, totalMs);
    }
  }

  async ingestText(text: string): Promise<KnowledgeUnit> {
    const body: string = text.trim();
    if (body.length === 0) {
      throw new Error('CapturePipeline.ingestText 需要非空文本');
    }
    const payload: TextPayload = { kind: 'text', text: body };
    return await this.processAndPersist(payload);
  }

  async ingestTextOutcome(text: string): Promise<NoteOutcome> {
    const body: string = text.trim();
    if (body.length === 0) {
      throw new Error('CapturePipeline.ingestText 需要非空文本');
    }
    const payload: TextPayload = { kind: 'text', text: body };
    return await this.processAndPersistOutcome(payload);
  }

  async captureSet(imageUris: string[], userText?: string, token?: CancellationToken,
    onItem?: (item: CaptureSetItemResult) => void): Promise<CaptureSetResult> {
    const startedAt: number = Date.now();
    const seq: number = CaptureTiming.nextSeq();
    const context: common.UIAbilityContext = AiServicePorts.requireContext(this.context);
    const resolver: ImageUriResolver = new ImageUriResolver(context);

    // 1) 逐张把 file:// URI 复制到沙箱（单张失败不拖垮整批）
    const localPaths: string[] = [];
    const preFailed: CaptureSetItemResult[] = [];
    for (let i = 0; i < imageUris.length; i++) {
      try {
        const resolved: ResolvedImageFile = await resolver.resolve(imageUris[i]);
        localPaths[i] = resolved.localPath;
      } catch (error) {
        localPaths[i] = '';
        preFailed.push({
          index: i,
          kind: 'image',
          success: false,
          cancelled: false,
          errorMessage: (error as Error).message,
          durationMs: 0,
        });
      }
    }

    // 2) 036 阶段 2/3 Stage A：逐图 OCR → 切题；Stage B：跨图合并
    const imageTexts: SetImageText[] = [];
    for (let i = 0; i < imageUris.length; i++) {
      if (localPaths[i].length === 0) {
        continue;
      }
      try {
        const text: string = await OcrService.recognizeUri(localPaths[i]);
        imageTexts.push({ imageIndex: i, text: text });
      } catch (error) {
        preFailed.push({
          index: i,
          kind: 'image',
          success: false,
          cancelled: false,
          errorMessage: 'OCR 失败：' + (error as Error).message,
          durationMs: Date.now() - startedAt,
        });
      }
    }
    const plan: SetPlan = planCaptureSet(imageTexts);
    for (let k = 0; k < plan.emptyImageIndexes.length; k++) {
      preFailed.push({
        index: plan.emptyImageIndexes[k],
        kind: 'image',
        success: false,
        cancelled: false,
        errorMessage: '这张图没有识别到文字',
        durationMs: Date.now() - startedAt,
      });
    }

    // 3) 按题下发 capture 命令（payload 已是 OCR 原文，不再二次 OCR）
    const dao: NoteDaoInterface = await AiServicePorts.buildNoteDao(AiServicePorts.requireContext(this.context), this.includeUiEffects);
    const dispatcher: Dispatcher = new Dispatcher();
    const problems: PlannedProblem[] = plan.problems;
    const commands: NoteCommand[] = [];
    for (let k = 0; k < problems.length; k++) {
      commands.push({
        kind: 'capture',
        operationId: 'capture-set-' + seq.toString() + '-p' + k.toString(),
        source: 'app',
        payload: { kind: 'text', text: problems[k].text },
      });
    }
    const canStreamItems: boolean = preFailed.length === 0;
    const batch: NoteBatchOutcome = await dispatcher.dispatchSetCommand(commands, {
      dao: dao,
      noteWritePort: await AiServicePorts.buildNoteWritePort(AiServicePorts.requireContext(this.context), this.includeUiEffects),
      cancellationToken: token,
      subjectVocabulary: await SubjectVocabularyService.list(),
      runEventSink: AiServicePorts.buildRunEventSinkIfReady(),
    }, (index: number, outcome: NoteOutcome): void => {
      if (canStreamItems && onItem !== undefined) {
        onItem(CapturePipeline.problemItemFromOutcome(index, problems, outcome));
      }
    });

    // 4) 合并逐题回执 + 图片级失败项
    const merged: CaptureSetItemResult[] = [];
    for (let k = 0; k < problems.length; k++) {
      merged.push(CapturePipeline.problemItemFromOutcome(k, problems, batch.items[k]));
    }
    for (let k = 0; k < preFailed.length; k++) {
      merged.push(preFailed[k]);
    }
    if (!canStreamItems && onItem !== undefined) {
      for (let i = 0; i < merged.length; i++) {
        onItem(merged[i]);
      }
    }

    // 5) 落库成功的题按来源图建文搜图索引（同一张图可对应多题）
    for (let k = 0; k < problems.length; k += 1) {
      const item: CaptureSetItemResult = merged[k];
      if (!item.success || item.noteId === undefined || item.noteId.length === 0) {
        continue;
      }
      const imageIndexes: number[] = item.sourceImageIndexes !== undefined ? item.sourceImageIndexes : [];
      for (let s = 0; s < imageIndexes.length; s += 1) {
        const imageIndex: number = imageIndexes[s];
        if (imageIndex >= 0 && imageIndex < localPaths.length && localPaths[imageIndex].length > 0) {
          await this.indexForSearch(localPaths[imageIndex], item.noteId);
        }
      }
    }

    const failed: number = batch.failed + preFailed.length;
    const result: CaptureSetResult = {
      total: problems.length + preFailed.length,
      done: batch.committed,
      failed: failed,
      cancelled: batch.cancelled,
      items: merged,
      durationMs: Date.now() - startedAt,
    };
    log.info('captureSet done, images=' + imageUris.length.toString()
      + ' problems=' + problems.length.toString()
      + ' done=' + result.done.toString() + ' failed=' + failed.toString()
      + ' cancelled=' + result.cancelled.toString()
      + (userText !== undefined && userText.length > 0 ? ' userTextLen=' + userText.length.toString() : ''));
    CaptureTiming.logCaptureSet(seq, result.total, result.done, failed, result.cancelled, result.durationMs);
    return result;
  }

  // 036 阶段 2/3：题目级回执（携带来源图片下标 / 题号 / 复核标记）
  static problemItemFromOutcome(
    index: number,
    problems: PlannedProblem[],
    outcome: NoteOutcome,
  ): CaptureSetItemResult {
    const problem: PlannedProblem = problems[index];
    const item: CaptureSetItemResult = {
      index: index,
      kind: 'problem',
      success: outcome.kind === 'committed',
      cancelled: outcome.kind === 'cancelled',
      durationMs: outcome.durationMs,
      sourceImageIndexes: problem.sourceImageIndexes,
      anchors: problem.anchors,
      needsReview: problem.needsReview,
    };
    if (outcome.noteId !== undefined) {
      item.noteId = outcome.noteId;
    }
    if (outcome.unit !== undefined) {
      item.title = outcome.unit.title;
    }
    if (outcome.classification !== undefined) {
      item.category = outcome.classification.type;
    }
    if (!item.success && outcome.kind !== 'cancelled') {
      if (outcome.message !== undefined) {
        item.errorMessage = outcome.message;
      } else if (outcome.reason !== undefined) {
        item.errorMessage = outcome.reason;
      }
      if (outcome.code !== undefined) {
        item.errorCode = outcome.code;
      }
    }
    return item;
  }

  static captureItemFromOutcome(
    index: number,
    payload: DispatchPayload,
    outcome: NoteOutcome,
  ): CaptureSetItemResult {
    const item: CaptureSetItemResult = {
      index: index,
      kind: payload.kind,
      success: outcome.kind === 'committed',
      cancelled: outcome.kind === 'cancelled',
      durationMs: outcome.durationMs,
    };
    if (outcome.noteId !== undefined) {
      item.noteId = outcome.noteId;
    }
    if (outcome.unit !== undefined) {
      item.title = outcome.unit.title;
    }
    if (outcome.classification !== undefined) {
      item.category = outcome.classification.type;
    }
    if (!item.success && outcome.kind !== 'cancelled') {
      if (outcome.message !== undefined) {
        item.errorMessage = outcome.message;
      } else if (outcome.reason !== undefined) {
        item.errorMessage = outcome.reason;
      }
      if (outcome.code !== undefined) {
        item.errorCode = outcome.code;
      }
    }
    return item;
  }

  private async indexForSearch(localPath: string, unitId: string): Promise<void> {
    if (!ImageSearchIndexRegistry.isInstalled()) {
      log.warn('capture 跳过文搜图索引: 端口未安装');
      return;
    }
    const startedAt: number = Date.now();
    try {
      const ok: boolean = await ImageSearchIndexRegistry.require().insert(localPath);
      log.info('capture 建索引 unitId=' + unitId + ' ok=' + (ok ? '1' : '0')
        + ' ms=' + (Date.now() - startedAt).toString());
    } catch (e) {
      const err: Error = e as Error;
      log.warn('capture 建索引失败 unitId=' + unitId + ' err=' + err.message);
    }
  }

  async analyzeImage(imageUri: string, userText?: string, cancellationToken?: CancellationToken): Promise<ClassificationResult> {
    cancellationToken?.throwIfCancelled();
    log.info('analyzeImage start, imageUri=' + imageUri);
    if (this.context === undefined) {
      throw new Error('CapturePipeline.analyzeImage 需要 UIAbilityContext 来准备图片文件');
    }

    const resolved: ResolvedImageFile = await new ImageUriResolver(this.context as common.UIAbilityContext).resolve(imageUri);

    const dispatcher: Dispatcher = new Dispatcher();
    // A3c：分析入口也走命令 seam；analysisOnly 的终态是 readyPreview（不落库）。
    const command: NoteCommand = {
      kind: 'analysisOnly',
      operationId: 'analyze-' + Date.now().toString() + '-' + CaptureTiming.nextSeq().toString(),
      source: 'app',
      payload: { kind: 'image', imageUri: resolved.localPath, userText: userText },
      includeRawText: true,
    };
    const outcome: NoteOutcome = await dispatcher.dispatchCommand(command, {
      cancellationToken: cancellationToken,
    });
    if (outcome.kind !== 'readyPreview' || outcome.classification === undefined) {
      const message: string = outcome.message !== undefined ? outcome.message
        : (outcome.reason !== undefined ? outcome.reason : '识别失败');
      throw new Error(message);
    }
    return outcome.classification;
  }

  private async processAndPersistOutcome(
    payload: DispatchPayload,
    onNodeTiming?: (step: string, elapsedMs: number) => void,
  ): Promise<NoteOutcome> {
    const operationId: string = 'capture-' + Date.now().toString() + '-' + CaptureTiming.nextSeq().toString();
    const command: NoteCommand = {
      kind: 'capture',
      operationId: operationId,
      source: 'app',
      payload: payload,
    };
    const dao: NoteDaoInterface = await AiServicePorts.buildNoteDao(AiServicePorts.requireContext(this.context), this.includeUiEffects);
    const dispatcher: Dispatcher = new Dispatcher();
    return await dispatcher.dispatchCommand(command, {
      dao: dao,
      noteWritePort: await AiServicePorts.buildNoteWritePort(AiServicePorts.requireContext(this.context), this.includeUiEffects),
      subjectVocabulary: await SubjectVocabularyService.list(),
      onNodeTiming: onNodeTiming,
      runEventSink: AiServicePorts.buildRunEventSinkIfReady(),
    });
  }

  private async processAndPersist(
    payload: DispatchPayload,
    onNodeTiming?: (step: string, elapsedMs: number) => void,
  ): Promise<KnowledgeUnit> {
    const outcome: NoteOutcome = await this.processAndPersistOutcome(payload, onNodeTiming);
    if (outcome.kind !== 'committed' || outcome.unit === undefined) {
      const message: string = outcome.message !== undefined ? outcome.message : 'Capture workflow failed';
      throw new Error('处理失败: ' + message);
    }
    const unit: KnowledgeUnit = outcome.unit;

    // 4) Only metadata is logged; note content never enters production logs.
    log.info('done, noteId=' + unit.id + ', category=' + unit.category);

    return unit;
  }
}
