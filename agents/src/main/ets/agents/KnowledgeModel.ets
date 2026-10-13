/**
 * KnowledgeModel.ets — 保持外部 Interface 的兼容 facade
 *
 * 路径: agents/src/main/ets/agents/KnowledgeModel.ets
 * 职责: 组装 CaptureStructurer 与 DraftComposer，并转发既有 Capture / 生成入口。
 * 依赖: CaptureStructurer、DraftComposer、common/src/main/ets/Index
 *
 * 数据流:
 *   Dispatcher → KnowledgeModel → CaptureStructurer / DraftComposer
 *
 * 第一阶段保留 facade；生成业务是否脱离外部 Interface 留待后续阶段裁决。
 */
import type { KnowledgeCategory } from '../models/KnowledgeCategory';
import {
  KnowledgeUnitExt,
  createUnitExt,
  StructuredField,
  AiRawResponse,
} from '../models/KnowledgeUnitExt';
import {
  DifficultyLevel,
  ContentExcerptBuilder,
  ContentProtocol,
  isKnownNoteType,
  JSON_ONLY_RULES,
  LATEX_GENERATION_RULES,
  LlmError,
  LlmGuard,
  LlmClient,
  LlmConfig,
  normalizeNoteType,
  NOTE_TYPE_KEYS,
  ReviewStatus,
  normalizeOutline,
  normalizeDraftCategory,
  normalizeDraftSummary,
  normalizeLightDraft,
  normalizeDraftSectionLabel,
  normalizeDraftDifficulty,
  segmentSourceBundle,
  buildDeepOutline,
  buildPipelineEvidence,
  sourceFingerprint,
  validateSourceBundle,
  NoteGenerationArtifactValidator,
  buildNoteVerificationJsonSchema,
  NOTE_OUTLINE_SCHEMA_VERSION,
  NOTE_DRAFT_SCHEMA_VERSION,
  NOTE_STANDARD_JSON_SCHEMA,
} from 'common';
import type {
  ChatMessage,
  ClassificationResult,
  ContentValidationResult,
  KnowledgeUnit,
  LlmGuardJsonResult,
  LlmGuardJsonExtractionResult,
  LlmGuardJsonCandidate,
  LlmGuardValidationResult,
  LlmCaller,
  LlmJsonSchema,
  LlmResponseFormat,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationIssue,
  NoteGenerationRequest,
  NoteGenerationOutline,
  NoteGenerationOutlineSection,
  NoteGenerationEvidenceCandidate,
  EvidenceCandidateSourceRef,
  NoteGenerationEvidenceItem,
  EvidenceSourceRef,
  EvidenceItemType,
  EvidenceVerificationStatus,
  NoteGenerationEvidenceDecision,
  NoteGenerationStandardResult,
  NoteGenerationDeepResult,
  NoteGenerationSegment,
  NoteGenerationLedger,
  NoteGenerationLedgerEntry,
  NoteGenerationVerification,
  NoteGenerationProgressEvent,
  NoteGenerationProgressSink,
  SourceBundle,
  NoteGenerationRequirement,
  IncrementalPlan,
  IncrementalSection,
  IncrementalPatch,
  IncrementalPatchResponse,
  SourceFragment,
  CancellationToken,
} from 'common';
import { NOTE_DRAFT_JSON_SCHEMA, normalizeDeepSectionDraft, normalizeEvidenceItems, parseDirectStandardArtifacts, validateDraftDocument, validateDraftShape } from 'common';
import { TypeClassifier } from './TypeClassifier';
import { GenerationJsonCaller } from './GenerationJsonCaller';
import {
  KNOWLEDGE_CLASSIFY_HINT_TIMEOUT_MS,
  KNOWLEDGE_FALLBACK_CATEGORY,
  KNOWLEDGE_FALLBACK_SUBJECT,
  KNOWLEDGE_HINT_CONFIDENCE_MIN,
  KNOWLEDGE_INPUT_LIMIT,
  KNOWLEDGE_MAX_TOKENS,
  KNOWLEDGE_TIMEOUT_MS,
  PromptBuilder,
} from './PromptBuilder';
import { CaptureStructurer } from './CaptureStructurer';
import { DraftComposer } from './DraftComposer';

export class KnowledgeModel {
  private readonly captureStructurer: CaptureStructurer;
  private readonly draftComposer: DraftComposer;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    this.captureStructurer = new CaptureStructurer(llm, cancellationToken);
    this.draftComposer = new DraftComposer(llm, cancellationToken);
  }

  async structure(
    ocrText: string,
    type?: string,
    subject?: string,
    chapter: string = '',
    source: string = 'camera_capture',
  ): Promise<KnowledgeUnit> {
    return await this.captureStructurer.structure(ocrText, type, subject, chapter, source);
  }

  async structureWithClassification(
    ocrText: string,
    classification: ClassificationResult,
    source: string = 'camera_capture',
  ): Promise<KnowledgeUnit> {
    return await this.captureStructurer.structureWithClassification(ocrText, classification, source);
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
    return await this.draftComposer.structureDeepDraft(request, progressSink);
  }

  async repairIncrementalSections(
    request: NoteGenerationRequest,
    plan: IncrementalPlan,
    sections: IncrementalSection[],
    sources: SourceFragment[],
  ): Promise<IncrementalPatchResponse> {
    return await this.draftComposer.repairIncrementalSections(request, plan, sections, sources);
  }

  draftToKnowledgeUnit(document: NoteDraftDocument, source: string): KnowledgeUnit {
    const fields: StructuredField[] = [];
    let index: number = 0;
    for (const section of document.sections) {
      fields.push({
        key: section.id,
        label: normalizeDraftSectionLabel(section.label, index),
        value: section.content,
      });
      index += 1;
    }
    const ext: KnowledgeUnitExt = createUnitExt(
      document.category as KnowledgeCategory,
      document.subject,
      document.title,
      document.summary,
    );
    ext.fields = fields;
    ext.tags = document.tags;
    ext.difficulty = document.difficulty;
    ext.source = source;
    ext.chapter = document.chapter;
    return this.captureStructurer.toKnowledgeUnit(ext, Date.now(), document.summary);
  }
}
