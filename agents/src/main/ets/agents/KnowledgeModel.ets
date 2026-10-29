/**
 * KnowledgeModel.ets — 保持外部 Interface 的兼容 facade
 *
 * 路径: agents/src/main/ets/agents/KnowledgeModel.ets
 * 职责: 组装 CaptureStructurer 与三个生成路线 Module，并转发既有 Capture / 生成入口。
 * 依赖: CaptureStructurer、DraftComposer、DeepDraftComposer、IncrementalPatchComposer、common
 *
 * 数据流:
 *   Dispatcher → KnowledgeModel → CaptureStructurer / 各生成路线 Module
 *
 * 第一阶段保留 facade；生成业务是否脱离外部 Interface 留待后续阶段裁决。
 */
import type {
  CaptureProvenance,
  ClassificationResult,
  KnowledgeUnit,
  LlmCaller,
  NoteDraftDocument,
  NoteGenerationRequest,
  NoteGenerationStandardResult,
  NoteGenerationDeepResult,
  NoteGenerationProgressSink,
  IncrementalPlan,
  IncrementalSection,
  IncrementalPatchResponse,
  SourceFragment,
  CancellationToken,
} from 'common/src/main/ets/Index';

import { CaptureStructurer } from './CaptureStructurer';
import { DraftComposer } from './DraftComposer';
import { DeepDraftComposer } from './DeepDraftComposer';
import { IncrementalPatchComposer } from './IncrementalPatchComposer';

export class KnowledgeModel {
  private readonly captureStructurer: CaptureStructurer;
  private readonly draftComposer: DraftComposer;
  private readonly deepDraftComposer: DeepDraftComposer;
  private readonly incrementalPatchComposer: IncrementalPatchComposer;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    this.captureStructurer = new CaptureStructurer(llm, cancellationToken);
    this.draftComposer = new DraftComposer(llm, cancellationToken);
    this.deepDraftComposer = new DeepDraftComposer(llm, cancellationToken);
    this.incrementalPatchComposer = new IncrementalPatchComposer(llm, cancellationToken);
  }

  async structure(
    ocrText: string,
    type?: string,
    subject?: string,
    chapter: string = '',
    source: string = 'camera_capture',
    provenance?: CaptureProvenance,
    knownSubjects: string[] = [],
  ): Promise<KnowledgeUnit> {
    return await this.captureStructurer.structure(ocrText, type, subject, chapter, source, provenance, knownSubjects);
  }

  async structureWithClassification(
    ocrText: string,
    classification: ClassificationResult,
    source: string = 'camera_capture',
    provenance?: CaptureProvenance,
    knownSubjects: string[] = [],
  ): Promise<KnowledgeUnit> {
    return await this.captureStructurer.structureWithClassification(
      ocrText, classification, source, provenance, knownSubjects);
  }

  async structureLightDraft(request: NoteGenerationRequest): Promise<NoteDraftDocument> {
    return await this.draftComposer.structureLightDraft(request);
  }

  async structureStandardDraft(
    request: NoteGenerationRequest,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteGenerationStandardResult> {
    return await this.draftComposer.structureStandardDraft(request, progressSink);
  }

  async structureDeepDraft(
    request: NoteGenerationRequest,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteGenerationDeepResult> {
    return await this.deepDraftComposer.compose(request, progressSink);
  }

  async repairIncrementalSections(
    request: NoteGenerationRequest,
    plan: IncrementalPlan,
    sections: IncrementalSection[],
    sources: SourceFragment[],
  ): Promise<IncrementalPatchResponse> {
    return await this.incrementalPatchComposer.compose(request, plan, sections, sources);
  }

  draftToKnowledgeUnit(
    document: NoteDraftDocument,
    source: string,
    provenance?: CaptureProvenance,
  ): KnowledgeUnit {
    return this.captureStructurer.draftToKnowledgeUnit(document, source, provenance);
  }
}
