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
import { Dispatcher, NoteDaoInterface } from 'agents';
import { common } from '@kit.AbilityKit';
import { ImageUriResolver, ResolvedImageFile } from './ImageUriResolver';
import { SubjectVocabularyService } from './SubjectVocabularyService';
import { ConversationRunIdPolicy, SessionIdPolicy } from './ConversationIdentity';
import { NoteGenerationRepositoryFactory } from './NoteGenerationRepositoryFactory';
import { AgentMemoryService } from './AgentMemoryService';
import { NoteGenerationContextBuilder } from './NoteGenerationContextBuilder';
import { CaptureTiming } from './ai/CaptureTiming';
import { AiServicePorts } from './ai/AiServicePorts';
import { ClarificationRegistry } from './ai/ClarificationRegistry';
import { DraftCommitService } from './ai/DraftCommitService';
import { DraftPipeline } from './ai/DraftPipeline';
import { ClarificationPipeline } from './ai/ClarificationPipeline';
import { CapturePipeline } from './ai/CapturePipeline';
import { CancellationToken } from 'common';

const log: Logger = new Logger('AiService');
export class AiService {

  // UIAbilityContext 引用,capture() 准备图片文件时用
  private context?: common.Context;
  /** 卡片刷新等 UI 副作用是否启用：扩展进程（小艺）里没有 UI，必须关掉。 */
  private includeUiEffects: boolean = true;

  constructor(context?: common.Context, includeUiEffects: boolean = true) {
    this.context = context;
    this.includeUiEffects = includeUiEffects;
  }

  // 拍照/相册入口:把图片处理成 KnowledgeUnit 并持久化
  // ===== 采集链路（实现已拆到 services/ai/CapturePipeline，AiService 拆分切片 6；本类只留 facade）=====
  async capture(imageUri: string, userText?: string): Promise<KnowledgeUnit> {
    return await new CapturePipeline(this.context, this.includeUiEffects).capture(imageUri, userText);
  }

  async ingestText(text: string): Promise<KnowledgeUnit> {
    return await new CapturePipeline(this.context, this.includeUiEffects).ingestText(text);
  }

  async ingestTextOutcome(text: string): Promise<NoteOutcome> {
    return await new CapturePipeline(this.context, this.includeUiEffects).ingestTextOutcome(text);
  }

  async captureSet(imageUris: string[], userText?: string, token?: CancellationToken,
    onItem?: (item: CaptureSetItemResult) => void): Promise<CaptureSetResult> {
    return await new CapturePipeline(this.context, this.includeUiEffects).captureSet(imageUris, userText, token, onItem);
  }

  async analyzeImage(imageUri: string, userText?: string, cancellationToken?: CancellationToken): Promise<ClassificationResult> {
    return await new CapturePipeline(this.context, this.includeUiEffects).analyzeImage(imageUri, userText, cancellationToken);
  }

  /**
   * 文本入口：小艺侧排进队列的原文（用户手输/粘贴的题目文字）直接走同一条
   * 「结构化 → 持久化」链路，不经过图片与 OCR。
   *
   * 与 capture() 的差别只有输入形态：这里没有图片要准备、没有文搜图索引要建。
   */

  /**
   * A3d：文本/A2A 入口的命令终态版本。
   * committed 时 unit 可用；failed 带 code/retryable；cancelled 带 committed(是否已落库)。
   * A2A 回执直接消费本方法，不再靠抛错文本判断。
   */

  // spec 036 阶段 1：一次整理 = 用户选中的 1..N 张图。
  // 与 capture() 的差别只有三处：准备 N 张图 → 走 dispatchSet（一个 set 一个 run，
  // 共享预算与取消）→ 返回逐项回执。单张时语义与 capture() 等价。
  // 切题与跨图合并不在这里（阶段 2/3），本方法只保证「N 张图是一次整理，不是 N 个任务」。

  /** A3d：批量终态 NoteOutcome → UI 回执 CaptureSetItemResult（迁移适配，字段口径保持不变）。 */

  /** 把已落库的图片写进 textSearchImage 索引；端口未安装时静默跳过。 */

  // 图片识别入口: 只 OCR + 分类，返回识别内容，不生成笔记、不入库

  // 内部: 把 entry 端 NoteDao 适配成 agents 端 NoteDaoInterface

  /**
   * #238 切片 A1：capture 持久化走 NoteWritePort（commitKey 幂等 / CAS / 结构化错误）。
   * 装配在 services 层工厂里完成，AiService 不直连 DAO（ownership 规则）。
   */

  // ===== 草稿生成 / 恢复 / 取消（实现已拆到 services/ai/DraftPipeline，AiService 拆分切片 4）=====
  async generateNoteDraft(runId: string, instruction: string, sourceText: string): Promise<NoteDraftReadyEvent> {
    return await new DraftPipeline(this.context, this.includeUiEffects).generateNoteDraft(runId, instruction, sourceText);
  }

  async generateNoteDraftWithSources(
    runId: string,
    instruction: string,
    sourceText: string,
    pendingSources: SourceFragment[],
    cancellationToken?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route: NoteGenerationRoute = 'standard',
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await new DraftPipeline(this.context, this.includeUiEffects).generateNoteDraftWithSources(
      runId, instruction, sourceText, pendingSources, cancellationToken,
      originSessionId, parentConversationRunId, route, progressSink);
  }

  async generateNoteDraftWithBundle(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    pendingSourceIds: string[],
    contextBudgetTokens: number,
    cancellationToken?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route: NoteGenerationRoute = 'standard',
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await new DraftPipeline(this.context, this.includeUiEffects).generateNoteDraftWithBundle(
      runId, instruction, bundle, pendingSourceIds, contextBudgetTokens, cancellationToken,
      originSessionId, parentConversationRunId, route, progressSink);
  }

  async regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    cancellationToken?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await new DraftPipeline(this.context, this.includeUiEffects).regenerateNoteDraft(
      runId, noteId, instruction, sourceText, cancellationToken,
      originSessionId, parentConversationRunId, progressSink);
  }

  async restoreDraft(runId: string): Promise<NoteDraftReadyEvent> {
    return await new DraftPipeline(this.context, this.includeUiEffects).restoreDraft(runId);
  }

  async cancelDraft(runId: string): Promise<void> {
    return await new DraftPipeline(this.context, this.includeUiEffects).cancelDraft(runId);
  }

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    return await new DraftPipeline(this.context, this.includeUiEffects).listRecoverableDrafts();
  }

  async cancelDraftsByParentRun(sessionId: string, parentConversationRunId: string): Promise<void> {
    return await new DraftPipeline(this.context, this.includeUiEffects).cancelDraftsByParentRun(sessionId, parentConversationRunId);
  }

  // ===== 澄清流程 / 重试（实现已拆到 services/ai/ClarificationPipeline，AiService 拆分切片 5）=====
  async resumeNoteContextClarification(
    runId: string,
    topicId: string,
    cancellationToken?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await new ClarificationPipeline(this.context, this.includeUiEffects)
      .resumeNoteContextClarification(runId, topicId, cancellationToken, progressSink);
  }

  async saveNoteContextClarification(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    topics: NoteTopicCandidate[],
    pendingSourceIds: string[],
    contextBudgetTokens: number,
    originSessionId?: string,
    parentConversationRunId?: string,
    route: NoteGenerationRoute = 'standard',
  ): Promise<NoteContextClarification> {
    return await new ClarificationPipeline(this.context, this.includeUiEffects).saveNoteContextClarification(
      runId, instruction, bundle, topics, pendingSourceIds, contextBudgetTokens,
      originSessionId, parentConversationRunId, route);
  }

  async retryDraft(runId: string): Promise<NoteDraftReadyEvent> {
    return await new ClarificationPipeline(this.context, this.includeUiEffects).retryDraft(runId);
  }

  /**
   * 确认草稿（A3 命令入口：preparedCandidate → committed）。
   * 实现已拆到 services/ai/DraftCommitService（AiService 拆分切片 3）。
   */
  async confirmDraft(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return await new DraftCommitService(this.context, this.includeUiEffects).confirmDraft(event, candidate);
  }

  // 内部: 调度 -> 校验 -> 入库（命令终态版本；A2A 回执直接消费它）

  // 内部: 调度 -> 校验 -> 入库（知识单元版本；旧调用方适配器）

}
