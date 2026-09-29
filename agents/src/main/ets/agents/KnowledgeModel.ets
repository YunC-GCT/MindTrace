// MindTrace - KnowledgeModel
// ============================================================================
//  agents/KnowledgeModel.ets — 知识结构化编排 agent
//  ----------------------------------------------------------------------------
//  路径: agents/src/main/ets/agents/KnowledgeModel.ets
//  职责: structure() / structureWithClassification() 编排 — 组装提示词 (PromptBuilder)、
//        调用 LLM (callAi: LlmGuard JSON 校验重试, 即 ADR-0012 ToolLoop 的预留 seam)、
//        归一化字段、合并分类 hint、产出主线 KnowledgeUnit
//  依赖: common (LlmGuard / ContentProtocol / NOTE_TYPE_KEYS / models) ·
//        TypeClassifier · PromptBuilder
//  数据流: OCR 文本 → resolveClassificationHint → callAi (prompt + JSON_ONLY_RULES)
//          → validateAiJson → normalize* → toKnowledgeUnit
//          → KnowledgeUnit; TruthCheck 由 Capture workflow 独立节点负责
//  沿革: spec 015 (2026-09-06) 原地拆分 — 提示词/真值检查/常量拆为三个协作服务,
//        本类依用户命名裁决保留 KnowledgeModel 之名, 878 行 god class → 554 行
//  ============================================================================
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

/** deep ledger 单条 value 上限 (字符): 防止共享 ledger 随节数膨胀推高 prompt (P0-5) */
const DEEP_LEDGER_VALUE_MAX_CHARS: number = 160;

export class KnowledgeModel {
  private contentProtocol: ContentProtocol = new ContentProtocol();
  private contentExcerptBuilder: ContentExcerptBuilder = new ContentExcerptBuilder();
  private promptBuilder: PromptBuilder = new PromptBuilder();
  private llm: LlmCaller;
  private jsonCaller: GenerationJsonCaller;
  private readonly cancellationToken?: CancellationToken;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    this.llm = llm ?? new LlmClient();
    this.cancellationToken = cancellationToken;
    this.jsonCaller = new GenerationJsonCaller(this.llm, undefined, cancellationToken);
  }

  /**
   * 主入口：AI 自分词 + 结构化 + 真值检验，返回主线 KnowledgeUnit。
   *
   * TypeClassifier 负责 OCR/文本提取，也可提供五分类 hint。
   * type/subject 仍作为可选 hint 保留给兼容调用方；未传入时由 KnowledgeModel 短超时获取 hint 后自行结构化。
   */
  async structure(
    ocrText: string,
    type?: string,
    subject?: string,
    chapter: string = '',
    source: string = 'camera_capture',
  ): Promise<KnowledgeUnit> {
    this.cancellationToken?.throwIfCancelled();
    const startTime: number = Date.now();
    const classificationHint: ClassificationResult = await this.resolveClassificationHint(
      ocrText,
      type,
      subject,
      chapter,
    );
    const hasExternalType: boolean = type !== undefined && type.trim().length > 0;
    const hasNoExternalHint: boolean = type === undefined && subject === undefined && chapter.length === 0;
    const canUseClassifierType: boolean = hasNoExternalHint
      && classificationHint.confidence >= KNOWLEDGE_HINT_CONFIDENCE_MIN;
    const typeHint: string | undefined = hasExternalType || canUseClassifierType
      ? classificationHint.type
      : undefined;
    const subjectHint: string | undefined = classificationHint.subject !== KNOWLEDGE_FALLBACK_SUBJECT
      ? classificationHint.subject
      : undefined;
    const chapterHint: string = classificationHint.chapter ?? chapter;

    // D2 spec 011 §9: AI 失败时显式报错, 不再生成 fallback 占位笔记污染 RDB 与复习调度。
    // 上层 StructureNode 会把该异常转为图错误 (STRUCTURE_ERROR), 阻止持久化。
    let aiRaw: AiRawResponse;
    try {
      aiRaw = await this.callAi(
        ocrText,
        typeHint,
        subjectHint,
        chapterHint,
        classificationHint.confidence,
      );
    } catch (aiErr) {
      const errMsg: string = (aiErr as Error).message ?? String(aiErr);
      console.warn('[KnowledgeModel] AI structure failed: ' + errMsg);
      throw new Error('AI 结构化失败: ' + errMsg);
    }
    const ext: KnowledgeUnitExt = createUnitExt(aiRaw.category, aiRaw.subject, aiRaw.title, ocrText);
    ext.fields = aiRaw.fields;
    ext.tags = this.buildTags(aiRaw);
    ext.difficulty = aiRaw.difficulty;
    ext.importance = aiRaw.importance;
    ext.source = source;
    ext.chapter = aiRaw.chapter.length > 0 ? aiRaw.chapter : chapterHint;

    this.markNeedsUserInput(ext, aiRaw);

    const unit: KnowledgeUnit = this.toKnowledgeUnit(ext, startTime);
    console.info('[KnowledgeModel] structure done: noteId=' + unit.id
      + ' category=' + ext.type + ' aiFields=' + aiRaw.fields.length.toString());
    return unit;
  }

  async structureWithClassification(
    ocrText: string,
    classification: ClassificationResult,
    source: string = 'camera_capture',
  ): Promise<KnowledgeUnit> {
    return await this.structure(
      ocrText,
      classification.type,
      classification.subject,
      classification.chapter ?? '',
      source,
    );
  }

  async structureLightDraft(request: NoteGenerationRequest): Promise<NoteDraftDocument> {
    const sourceText: string = this.lightSourceText(request);
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Generate one schema-valid math note draft. Preserve the instruction exactly. '
        + 'If sourceIds are clear from the input, include them; otherwise leave them empty and let the pipeline map them from the original source fragments. '
        + 'Do not invent source IDs. Evidence is assembled by the pipeline when the first model pass does not provide it. Return JSON only.\n'
        + 'Original source fragments are authoritative; summaries never replace conflicting raw text.\n'
        + request.instruction + '\n' + NOTE_DRAFT_JSON_SCHEMA,
    };
    const userMessage: ChatMessage = { role: 'user', content: sourceText };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    const responseFormat = this.structuredResponseFormat();
    const parsed: Record<string, Object> = await this.jsonCaller.callJson(
      messages,
      {
        label: 'light draft',
        maxTokens: this.budgetedRequestTokens(request, 1200),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: responseFormat,
      },
      (json: Record<string, Object>): LlmGuardValidationResult => {
        const issues: string[] = validateDraftShape(json);
        return { ok: issues.length === 0, issues: issues };
      },
      (json: Record<string, Object>): string[] => {
        const document: NoteDraftDocument = normalizeLightDraft(this.parseDraftDocument(json), request.sources);
        const sourceIds: string[] = [];
        for (const fragment of request.sources.fragments) {
          sourceIds.push(fragment.id);
        }
        const issues: NoteGenerationIssue[] = validateDraftDocument(document, sourceIds);
        const codes: string[] = [];
        for (const issue of issues) {
          codes.push(issue.code);
        }
        return codes;
      },
    );
    return normalizeLightDraft(this.parseDraftDocument(parsed), request.sources);
  }

  async structureStandardDraft(
    request: NoteGenerationRequest,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteGenerationStandardResult> {
    const sourceIssues: NoteGenerationIssue[] = validateSourceBundle(request.sources);
    if (sourceIssues.length > 0) {
      throw new Error('standard source gate failed: ' + sourceIssues[0].code);
    }
    const requirement = request.requirement ?? {
      detailLevel: 'normal',
      mustInclude: [],
      mustAvoid: [],
      targetSectionIds: [],
      preserveUserEdits: true,
    };
    const extracted: NoteGenerationStandardResult = await this.callStandardArtifacts(request, requirement, '建立 Outline、Evidence 和 Draft');
    const normalized: NoteGenerationStandardResult = this.normalizeStandardResult(extracted, request.sources, request.instruction);
    this.emitProgress(progressSink, {
      phase: 'verify',
      state: 'running',
      activity: 'check_accuracy',
    });
    const verification: NoteGenerationVerification = await this.callIndependentVerifier(
      normalized,
      request.sources,
      requirement,
      request.tokenBudget,
    );
    const verified: NoteGenerationStandardResult = {
      outline: normalized.outline,
      evidence: normalized.evidence,
      draft: normalized.draft,
      verification: verification,
    };
    return verified;
  }

  async structureDeepDraft(
    request: NoteGenerationRequest,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteGenerationDeepResult> {
    const sourceIssues: NoteGenerationIssue[] = validateSourceBundle(request.sources);
    if (sourceIssues.length > 0) {
      throw new Error('deep source gate failed: ' + sourceIssues[0].code);
    }
    const requirement: NoteGenerationRequirement = request.requirement ?? {
      detailLevel: 'detailed',
      mustInclude: [],
      mustAvoid: [],
      targetSectionIds: [],
      preserveUserEdits: true,
    };
    const segments: NoteGenerationSegment[] = segmentSourceBundle(request.sources);
    if (segments.length === 0) {
      throw new Error('deep route requires semantic source segments');
    }
    const outline: NoteGenerationOutline = buildDeepOutline(segments, requirement);
    const ledger: NoteGenerationLedger = { formulas: [], terminology: [], conclusions: [] };
    const sections: NoteDraftSection[] = [];
    let title: string = '';
    let summary: string = '';
    let subject: string = '';
    let category: string = '概念';
    let chapter: string = '';
    let difficulty: number = 2;
    let tags: string[] = [];
    let sectionIndex: number = 0;
    for (const outlineSection of outline.sections) {
      sectionIndex += 1;
      this.emitProgress(progressSink, {
        phase: 'compose',
        state: 'running',
        activity: 'write_section',
        current: sectionIndex,
        total: outline.sections.length,
      });
      const sectionDraft: NoteDraftDocument = await this.callDeepSectionDraft(
        request,
        outlineSection,
        segments,
        ledger,
      );
      if (title.length === 0) {
        title = sectionDraft.title;
        summary = sectionDraft.summary;
        subject = sectionDraft.subject;
        category = sectionDraft.category;
        chapter = sectionDraft.chapter;
        difficulty = sectionDraft.difficulty;
        tags = sectionDraft.tags.slice(0);
      }
      const generated: NoteDraftSection | undefined = sectionDraft.sections[0];
      if (generated === undefined) {
        throw new Error('deep section draft is empty: ' + outlineSection.id);
      }
      sections.push({
        id: outlineSection.id,
        label: outlineSection.label,
        content: generated.content,
        sourceIds: outlineSection.sourceIds.slice(0),
        state: 'generated',
        baseHash: sourceFingerprint(generated.content),
      });
      this.updateDeepLedger(ledger, outlineSection, generated.content, segments);
    }
    const draft: NoteDraftDocument = {
      schemaVersion: NOTE_DRAFT_SCHEMA_VERSION,
      title: title.length === 0 ? '数学学习笔记' : title,
      summary: normalizeDraftSummary(summary),
      subject: subject.length === 0 ? '其它' : subject,
      category: category,
      chapter: chapter,
      difficulty: difficulty,
      tags: tags,
      sections: sections,
      instruction: request.instruction,
    };
    const evidence: NoteGenerationEvidenceItem[] = this.buildDeepEvidence(outline, sections, segments, request.sources);
    this.emitProgress(progressSink, {
      phase: 'verify',
      state: 'running',
      activity: 'check_accuracy',
    });
    const verificationInput: NoteGenerationStandardResult = {
      outline: outline,
      evidence: evidence,
      draft: draft,
      verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] },
    };
    const verification: NoteGenerationVerification = await this.callIndependentVerifier(
      verificationInput,
      request.sources,
      requirement,
      request.tokenBudget,
    );
    return {
      outline: outline,
      evidence: evidence,
      draft: draft,
      verification: verification,
      ledger: ledger,
      segments: segments,
    };
  }

  private emitProgress(progressSink: NoteGenerationProgressSink | undefined, event: NoteGenerationProgressEvent): void {
    if (progressSink !== undefined) {
      progressSink(event);
    }
  }

  async repairIncrementalSections(
    request: NoteGenerationRequest,
    plan: IncrementalPlan,
    sections: IncrementalSection[],
    sources: SourceFragment[],
  ): Promise<IncrementalPatchResponse> {
    const targetSections: IncrementalSection[] = [];
    for (const section of sections) {
      if (plan.targetSectionIds.includes(section.id)) {
        targetSections.push(section);
      }
    }
    const relevantSources: string[] = [];
    for (const source of sources) {
      if (plan.relevantSourceIds.includes(source.id)) {
        relevantSources.push('[source:' + source.id + '] ' + source.text);
      }
    }
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Return JSON only with patches. Repair only the requested target sections. '
        + 'Each patch must have sectionId, operation=replace, content and sourceIds. '
        + 'never return a full document, metadata, or an unplanned section. '
        + 'instruction=' + request.instruction + '\n'
        + 'targetSectionIds=' + plan.targetSectionIds.join(',') + '\n'
        + 'targets=' + JSON.stringify(targetSections) + '\n'
        + 'relevant sources=\n' + relevantSources.join('\n'),
    };
    const parsed: Record<string, Object> = await this.jsonCaller.callJson(
      [systemMessage, { role: 'user', content: 'Return section RepairPatch objects only.' }],
      {
        label: 'incremental repair',
        maxTokens: this.budgetedRequestTokens(request, 2400),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: { type: 'json_object' },
      },
      (json: Record<string, Object>): LlmGuardValidationResult => {
        const value: Object | undefined = this.readRecordValue(json, 'patches');
        if (value === undefined || !Array.isArray(value)) {
          return { ok: false, issues: ['patches must be an array'] };
        }
        return { ok: true, issues: [] };
      },
      (json: Record<string, Object>): string[] => {
        const value: Object | undefined = this.readRecordValue(json, 'patches');
        if (value === undefined || !Array.isArray(value)) {
          return ['patches must be an array'];
        }
        const issues: string[] = [];
        for (const item of value as Object[]) {
          const record: Record<string, Object> = item as Record<string, Object>;
          const sectionId: string = String(this.readRecordValue(record, 'sectionId') ?? '');
          if (!plan.targetSectionIds.includes(sectionId)
            || this.readRecordValue(record, 'operation') !== 'replace') {
            issues.push('incremental repair contains an unplanned patch: ' + sectionId);
          }
        }
        return issues;
      },
    );
    const patches: IncrementalPatch[] = [];
    const patchValue: Object | undefined = this.readRecordValue(parsed, 'patches');
    if (patchValue !== undefined && Array.isArray(patchValue)) {
      for (const item of patchValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        patches.push({
          sectionId: String(this.readRecordValue(record, 'sectionId') ?? ''),
          operation: 'replace',
          content: String(this.readRecordValue(record, 'content') ?? ''),
          sourceIds: this.readStringArray(this.readRecordValue(record, 'sourceIds')),
        });
      }
    }
    return { patches: patches };
  }

  private async callDeepSectionDraft(
    request: NoteGenerationRequest,
    outlineSection: NoteGenerationOutlineSection,
    segments: NoteGenerationSegment[],
    ledger: NoteGenerationLedger,
  ): Promise<NoteDraftDocument> {
    const relevantLines: string[] = [];
    for (const segment of segments) {
      if (outlineSection.segmentIds !== undefined && outlineSection.segmentIds.includes(segment.id)) {
        relevantLines.push('[segment:' + segment.id + '] [source:' + segment.sourceId + '] ' + segment.text);
      }
    }
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Generate exactly one schema-valid math note section as JSON. This is a sequential deep route. '
        + 'Use only the relevant original segments below and the shared ledger; never invent or read other sections. '
        + 'Preserve formulas, derivation steps and terminology exactly, and return one section with id '
        + outlineSection.id + '. '
        + 'Contract: sections[].sourceIds may be empty when the model cannot safely determine the mapping; '
        + 'when present, they must use the [source:X] ids from the relevant sources. The pipeline fills missing mappings from the outline and source bundle. '
        + 'category must be one of 概念/定理/公式/证明题/计算题; '
        + 'title must not contain math delimiters; summary may contain short inline math using $...$, '
        + 'but must be no longer than 60 characters and must not use display math. '
        + LATEX_GENERATION_RULES + '\n'
        + 'User instruction=' + request.instruction + '\n'
        + 'section label=' + outlineSection.label + '\n'
        + 'must include=' + outlineSection.mustInclude.join(',') + '\n'
        + 'shared ledger=' + JSON.stringify(ledger) + '\n'
        + 'relevant sources:\n' + relevantLines.join('\n') + '\n' + NOTE_DRAFT_JSON_SCHEMA,
    };
    const parsed: Record<string, Object> = await this.jsonCaller.callJson(
      [systemMessage, { role: 'user', content: 'Draft only this section in document JSON.' }],
      {
        label: 'deep section draft',
        maxTokens: this.budgetedRequestTokens(request, 4800),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: this.structuredResponseFormat(),
      },
      (json: Record<string, Object>): LlmGuardValidationResult => {
        const issues: string[] = validateDraftShape(json);
        return { ok: issues.length === 0, issues: issues };
      },
      (json: Record<string, Object>): string[] => {
        // P0-4 (2026-09-19): 先归一化再校验 — LLM 原始输出系统性缺 sourceIds /
        // 学科级 category / \(...\) 定界符, 直接判 hard 导致 3 次重试全灭;
        // 归一化后校验器只拦截真值类失败 (空 content / 不可渲染 / 伪造引用)
        const document: NoteDraftDocument = normalizeDeepSectionDraft(this.parseDraftDocument(json), outlineSection);
        const issues: NoteGenerationIssue[] = validateDraftDocument(document, outlineSection.sourceIds, true);
        const codes: string[] = [];
        for (const issue of issues) {
          const detail: string = issue.message.trim().length > 0 ? ': ' + issue.message : '';
          codes.push(issue.code + detail);
        }
        return codes;
      },
    );
    return normalizeDeepSectionDraft(this.parseDraftDocument(parsed), outlineSection);
  }

  private updateDeepLedger(
    ledger: NoteGenerationLedger,
    outlineSection: NoteGenerationOutlineSection,
    content: string,
    segments: NoteGenerationSegment[],
  ): void {
    const sourceIds: string[] = outlineSection.sourceIds.slice(0);
    // P0-5 (2026-09-20): ledger 是跨节共享上下文, 不是内容仓库 —
    // value 截断 (DEEP_LEDGER_VALUE_MAX_CHARS), 否则 N 节后 prompt 线性膨胀
    if (this.contentProtocol.hasFormulaSyntax(content)) {
      ledger.formulas.push({
        key: 'formula-' + outlineSection.id,
        value: content.length > DEEP_LEDGER_VALUE_MAX_CHARS ? content.substring(0, DEEP_LEDGER_VALUE_MAX_CHARS) : content,
        sourceIds: sourceIds,
        sectionId: outlineSection.id,
      });
    }
    const words: string[] = content.split(' ');
    if (words.length > 0) {
      const term: string = words[0].trim();
      if (term.length > 0) {
        ledger.terminology.push({
          key: term.length > 24 ? term.substring(0, 24) : term,
          value: term.length > 24 ? term.substring(0, 24) : term,
          sourceIds: sourceIds,
          sectionId: outlineSection.id,
        });
      }
    }
    // P0-5: 原实现遍历全部 segments 按 sourceId 匹配 — 单源对话流下每节
    // 重录全部"因此/结论" segment, N 节后二次方膨胀 (实测 55 节 19×55 条)。
    // 收紧为: 仅本节 segmentIds 内的结论 + 按 segment id 去重 + value 截断。
    const existingConclusionKeys: string[] = [];
    for (const entry of ledger.conclusions) {
      if (!existingConclusionKeys.includes(entry.key)) {
        existingConclusionKeys.push(entry.key);
      }
    }
    for (const segment of segments) {
      const belongsToSection: boolean = outlineSection.segmentIds?.includes(segment.id) === true;
      if (!belongsToSection || !(segment.text.includes('因此') || segment.text.includes('结论'))) {
        continue;
      }
      const key: string = 'conclusion-' + segment.id;
      if (existingConclusionKeys.includes(key)) {
        continue;
      }
      existingConclusionKeys.push(key);
      ledger.conclusions.push({
        key: key,
        value: segment.text.length > DEEP_LEDGER_VALUE_MAX_CHARS
          ? segment.text.substring(0, DEEP_LEDGER_VALUE_MAX_CHARS) : segment.text,
        sourceIds: sourceIds,
        sectionId: outlineSection.id,
      });
    }
  }

  private buildDeepEvidence(
    outline: NoteGenerationOutline,
    sections: NoteDraftSection[],
    segments: NoteGenerationSegment[],
    bundle: SourceBundle,
  ): NoteGenerationEvidenceItem[] {
    const evidence: NoteGenerationEvidenceItem[] = [];
    for (const section of sections) {
      const outlineSection: NoteGenerationOutlineSection | undefined = outline.sections.find(
        (item: NoteGenerationOutlineSection): boolean => item.id === section.id,
      );
      if (outlineSection === undefined) {
        continue;
      }
      const sourceId: string | undefined = outlineSection.sourceIds[0];
      if (sourceId === undefined) {
        continue;
      }
      const segment: NoteGenerationSegment | undefined = segments.find(
        (item: NoteGenerationSegment): boolean => outlineSection.segmentIds?.includes(item.id) === true,
      );
      if (segment === undefined) {
        continue;
      }
      const excerpt: string = segment.text.substring(0, Math.min(segment.text.length, 240));
      // segment 文本必须重新定位到原始 fragment 后才能成为引用。定位失败时只保留
      // assertion 并留下空 sourceRefs，让 artifact validator 明确报错；不得伪造空引文或偏移。
      let fragment: SourceFragment | undefined = undefined;
      for (const candidate of bundle.fragments) {
        if (candidate.id === sourceId) {
          fragment = candidate;
          break;
        }
      }
      const evidenceId: string = 'evidence-' + section.id;
      const refs: EvidenceSourceRef[] = [];
      if (fragment !== undefined) {
        const located: number = fragment.text.indexOf(excerpt);
        if (located >= 0) {
          refs.push({
            id: evidenceId + ':ref-1',
            sourceId: sourceId,
            sourceFingerprint: fragment.fingerprint,
            excerpt: fragment.text.substring(located, located + excerpt.length),
            start: located,
            end: located + excerpt.length,
          });
        }
      }
      evidence.push({
        id: evidenceId,
        assertion: {
          type: segment.boundary === 'formula_block' ? 'formula' : segment.boundary === 'derivation' ? 'step' : 'claim',
          text: excerpt,
          targetSectionId: section.id,
        },
        sourceRefs: refs,
        origin: 'pipeline',
      });
    }
    return evidence;
  }

  private async callStandardArtifacts(
    request: NoteGenerationRequest,
    requirement: NoteGenerationRequirement,
    purpose: string,
  ): Promise<NoteGenerationStandardResult> {
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Return JSON only for a math note standard route. ' + purpose + '\n'
        + 'Preserve the exact user instruction, formulas, steps, examples and source mapping. '
        + 'When evidence is returned, each item should use a source excerpt and target section. '
        + 'Evidence may be an empty array or be omitted on the first pass; the pipeline will build evidence from the original source fragments when needed. '
        + 'Use stable section labels and source IDs from the input when they are unambiguous.\n'
        + 'category must be exactly one of: 概念, 定理, 公式, 证明题, 计算题.\n'
        + 'Outline and draft section sourceIds may be empty when the mapping is not yet known. Do not invent IDs; the pipeline will fill missing mappings from the real source bundle.\n'
        + 'Section content: use $...$ for inline math and $$ on their own lines for display math; '
        + 'never use \\( \\) or \\[ \\]; use markdown lists (- item / 1. item) instead of \\begin{itemize} or \\begin{enumerate}.\n'
        + 'Summary must be no longer than 60 characters; it may contain short inline math using $...$, '
        + 'but must not contain display math.\n'
        + 'Evidence excerpts must be copied verbatim (character-exact) from the sources.\n'
        + LATEX_GENERATION_RULES + '\n'
        + 'Output schema: top-level object with outline and draft; evidence is an optional array of evidence items. '
        + 'outline contains schemaVersion and sections; '
        + 'draft contains schemaVersion, title, summary, subject, category, chapter, difficulty, tags, and sections.\n'
        + 'instruction=' + request.instruction + '\n'
        + 'mustInclude=' + requirement.mustInclude.join(',') + '\n'
        + 'sources:\n' + this.standardSourceText(request.sources),
    };
    const userMessage: ChatMessage = { role: 'user', content: 'Generate Outline, Evidence ledger, and Draft document.' };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    const parsed: Record<string, Object> = await this.jsonCaller.callJson(
      messages,
      {
        label: 'standard artifacts',
        maxTokens: this.budgetedRequestTokens(request, KNOWLEDGE_MAX_TOKENS),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: this.structuredResponseFormat(NOTE_STANDARD_JSON_SCHEMA, 'mindtrace_note_standard'),
        candidateSelector: (extraction: LlmGuardJsonExtractionResult): LlmGuardJsonCandidate | undefined =>
          this.selectStandardArtifactsCandidate(extraction),
      },
      (json: Record<string, Object>): LlmGuardValidationResult => {
        if (this.isStandardArtifactsCandidate(json)) {
          return { ok: true, issues: [] };
        }
        return { ok: false, issues: ['standard artifacts require draft'] };
      },
    );
    return this.parseStandardResult(parsed, request.sources);
  }

  /**
   * standard 路线候选选择策略 (原 selectStandardArtifactsJsonText 的候选版):
   * 0 候选 / 唯一候选不可解析 / 多候选且命中数 ≠ 1 → undefined (seam 终止, 保持 fail-fast 旧行为)
   */
  private selectStandardArtifactsCandidate(
    extraction: LlmGuardJsonExtractionResult,
  ): LlmGuardJsonCandidate | undefined {
    if (extraction.candidates.length === 0) {
      return undefined;
    }
    if (extraction.candidates.length === 1) {
      return extraction.success ? extraction.candidates[0] : undefined;
    }
    let eligible: LlmGuardJsonCandidate | undefined = undefined;
    let eligibleCount: number = 0;
    for (const candidate of extraction.candidates) {
      if (candidate.parseable && candidate.object !== undefined && this.isStandardArtifactsCandidate(candidate.object)) {
        eligible = candidate;
        eligibleCount += 1;
      }
    }
    return eligibleCount === 1 ? eligible : undefined;
  }

  private isStandardArtifactsCandidate(parsed: Record<string, Object>): boolean {
    const outlineValue: Object | undefined = this.readRecordValue(parsed, 'outline');
    const evidenceValue: Object | undefined = this.readRecordValue(parsed, 'evidence');
    const draftValue: Object | undefined = this.readRecordValue(parsed, 'draft');
    if (outlineValue !== undefined && evidenceValue !== undefined && draftValue !== undefined) {
      return !Array.isArray(outlineValue) && typeof outlineValue === 'object'
        && Array.isArray(evidenceValue)
        && !Array.isArray(draftValue) && typeof draftValue === 'object';
    }
    if (draftValue !== undefined && !Array.isArray(draftValue) && typeof draftValue === 'object') {
      return this.isDraftArtifactsCandidate(draftValue as Record<string, Object>);
    }
    if (this.isDraftArtifactsCandidate(parsed)) {
      return true;
    }
    return this.findNestedStandardArtifacts(parsed) !== undefined;
  }

  private isDraftArtifactsCandidate(parsed: Record<string, Object>): boolean {
    const titleValue: Object | undefined = this.readRecordValue(parsed, 'title');
    const sectionsValue: Object | undefined = this.readRecordValue(parsed, 'sections');
    return typeof titleValue === 'string' && titleValue.trim().length > 0 && Array.isArray(sectionsValue);
  }

  private findNestedStandardArtifacts(parsed: Record<string, Object>): Record<string, Object> | undefined {
    const preferredKeys: string[] = ['result', 'data', 'note', 'document', 'draftDocument', 'answer', 'content', 'output'];
    const entries: Array<[string, Object]> = Object.entries(parsed) as Array<[string, Object]>;
    for (const key of preferredKeys) {
      const nested: Record<string, Object> | undefined = this.readNestedStandardArtifacts(
        this.readRecordValueFromEntries(entries, key),
      );
      if (nested !== undefined) {
        return nested;
      }
    }
    for (const entry of entries) {
      const key: string = entry[0];
      if (preferredKeys.includes(key)) {
        continue;
      }
      const nested: Record<string, Object> | undefined = this.readNestedStandardArtifacts(entry[1]);
      if (nested !== undefined) {
        return nested;
      }
    }
    return undefined;
  }

  private readRecordValue(parsed: Record<string, Object>, key: string): Object | undefined {
    return this.readRecordValueFromEntries(Object.entries(parsed) as Array<[string, Object]>, key);
  }

  private readOptionalString(parsed: Record<string, Object>, key: string): string | undefined {
    const value: Object | undefined = this.readRecordValue(parsed, key);
    return value === undefined ? undefined : String(value);
  }

  private readRecordValueFromEntries(entries: Array<[string, Object]>, key: string): Object | undefined {
    for (const entry of entries) {
      if (entry[0] === key) {
        return entry[1];
      }
    }
    return undefined;
  }

  private readNestedStandardArtifacts(value: Object | undefined): Record<string, Object> | undefined {
    if (value === undefined || value === null || Array.isArray(value)) {
      return undefined;
    }
    if (typeof value === 'string') {
      const jsonText: string = new LlmGuard().extractJsonObject(value);
      if (jsonText.length === 0) {
        return undefined;
      }
      try {
        return JSON.parse(jsonText) as Record<string, Object>;
      } catch (_e) {
        return undefined;
      }
    }
    if (typeof value === 'object') {
      const record: Record<string, Object> = value as Record<string, Object>;
      if (this.isStandardArtifactsCandidate(record) || this.isDraftArtifactsCandidate(record)) {
        return record;
      }
    }
    return undefined;
  }

  private async callIndependentVerifier(
    result: NoteGenerationStandardResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
    tokenBudget?: number,
  ): Promise<NoteGenerationVerification> {
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Act as a read-only independent note verifier. Return JSON only. Verify the outline, draft, '
        + 'evidence, source grounding, and requirement coverage. Never rewrite, replace, repair, or generate '
        + 'outline, draft, or evidence. Use exact top-level keys: status, issues, evidenceStatuses. '
        + 'Do not use overallStatus or any other alias. Return evidenceStatuses in the same order as the supplied '
        + 'evidence array; '
        + 'each value must be supported, contradicted, or ambiguous. Never copy or invent evidence IDs. When '
        + 'evidence is empty, evidenceStatuses must be empty, but you must still verify the outline, draft, '
        + 'sources, and requirements. For evidenceStatuses, judge only whether each cited excerpt supports the '
        + 'assertion. If a source faithfully contains an implausible or factually wrong statement, keep that '
        + 'evidence status supported and report the factual problem separately in issues and the top-level status.\n'
        + 'outline=' + JSON.stringify(result.outline) + '\n'
        + 'draft=' + JSON.stringify(result.draft) + '\n'
        + 'evidenceByPosition=' + this.verifierEvidenceText(result.evidence) + '\n'
        + 'sources=' + this.standardSourceText(bundle) + '\n'
        + 'mustInclude=' + requirement.mustInclude.join(',') + '\n'
        + 'mustAvoid=' + requirement.mustAvoid.join(','),
    };
    const userMessage: ChatMessage = {
      role: 'user',
      content: 'Verify the complete note and classify each evidence assertion by array position.',
    };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    let modelVerification: NoteGenerationVerification;
    try {
      const parsed: Record<string, Object> = await this.jsonCaller.callJson(
        messages,
        {
          label: 'independent verifier',
          maxTokens: this.budgetedTokens(tokenBudget, 2600),
          timeoutMs: KNOWLEDGE_TIMEOUT_MS,
          responseFormat: this.verificationResponseFormat(result.evidence),
        },
        (json: Record<string, Object>): LlmGuardValidationResult => {
          const issues: string[] = [];
          const statusesValue: Object | undefined = this.readRecordValue(json, 'evidenceStatuses');
          if (statusesValue !== undefined && !Array.isArray(statusesValue)) {
            issues.push('evidenceStatuses must be an array');
          }
          const issuesValue: Object | undefined = this.readRecordValue(json, 'issues');
          if (issuesValue !== undefined && !Array.isArray(issuesValue)) {
            issues.push('issues must be an array');
          }
          return { ok: issues.length === 0, issues: issues };
        },
        (json: Record<string, Object>): string[] =>
          this.validateIndependentVerifierJson(json, result.evidence),
      );
      modelVerification = this.parseVerification(parsed, result.evidence);
    } catch (e) {
      modelVerification = { status: 'ambiguous', issues: [{
        stage: 'verifier', code: 'VERIFIER_UNAVAILABLE', severity: 'hard',
        message: 'independent verifier did not return a complete result', repairable: false,
      }], checkedEvidenceIds: [], decisions: [] };
    }
    const local: NoteGenerationVerification = new NoteGenerationArtifactValidator().verify(
      result.outline,
      result.evidence,
      result.draft,
      bundle,
      requirement,
    );
    return this.combineVerification(modelVerification, local);
  }

  private normalizeStandardResult(
    result: NoteGenerationStandardResult,
    bundle: SourceBundle,
    instruction: string,
  ): NoteGenerationStandardResult {
    const sourceIds: string[] = [];
    for (const fragment of bundle.fragments) {
      sourceIds.push(fragment.id);
    }
    const originalSectionIds: string[] = [];
    for (const section of result.outline.sections) {
      originalSectionIds.push(section.id);
    }
    const outline: NoteGenerationOutline = normalizeOutline(result.outline, sourceIds);
    const outlineSourceIdsBySectionId: Map<string, string[]> = new Map<string, string[]>();
    for (const section of outline.sections) {
      outlineSourceIdsBySectionId.set(section.id, section.sourceIds);
    }
    const sections: NoteDraftSection[] = [];
    for (const section of result.draft.sections) {
      const oldIndex: number = originalSectionIds.indexOf(section.id);
      const remappedId: string = oldIndex >= 0 ? outline.sections[oldIndex].id : section.id;
      // 2026-09-20 P0-6: draft section sourceIds 先过滤非法 (LLM 常写 run id /
      // 缺 'conversation:' 前缀 → SOURCE_REFERENCE_INVALID), 空后再回填
      // (outline 对应节优先, 否则全部源)
      const mappedSourceIds: string[] = [];
      for (const sourceId of section.sourceIds) {
        if (sourceIds.includes(sourceId) && !mappedSourceIds.includes(sourceId)) {
          mappedSourceIds.push(sourceId);
        }
      }
      if (mappedSourceIds.length === 0) {
        const fromOutline: string[] | undefined = outlineSourceIdsBySectionId.get(remappedId);
        const fallbackIds: string[] = fromOutline !== undefined && fromOutline.length > 0
          ? fromOutline : sourceIds;
        for (const sourceId of fallbackIds) {
          mappedSourceIds.push(sourceId);
        }
      }
      sections.push({
        id: remappedId,
        label: normalizeDraftSectionLabel(section.label, oldIndex >= 0 ? oldIndex : sections.length),
        // 2026-09-19: 采用 MM-MD 规范化器的修复结果 (\(\)→$..$, \[→$$)
        content: this.normalizeSectionContent(section.content),
        sourceIds: mappedSourceIds,
        state: section.state,
        baseHash: section.baseHash,
      });
    }
    const draft: NoteDraftDocument = {
      // 2026-09-20 P0-6: schemaVersion 用管线常量, 不透传模型输出
      // (实测模型返回 '1.0' 必挂 SCHEMA_VERSION)
      schemaVersion: NOTE_DRAFT_SCHEMA_VERSION,
      title: result.draft.title,
      summary: normalizeDraftSummary(result.draft.summary),
      subject: result.draft.subject,
      // 2026-09-19: category 归一化到 5 类题型枚举 (学科级标签判死问题)
      category: normalizeDraftCategory(result.draft.category),
      chapter: result.draft.chapter,
      difficulty: normalizeDraftDifficulty(result.draft.difficulty),
      tags: result.draft.tags,
      sections: sections,
      instruction: instruction,
    };
    const remappedEvidence: NoteGenerationEvidenceItem[] = [];
    for (const item of result.evidence) {
      const oldIndex: number = originalSectionIds.indexOf(item.assertion.targetSectionId);
      remappedEvidence.push({
        id: item.id,
        assertion: {
          type: item.assertion.type,
          text: item.assertion.text,
          targetSectionId: oldIndex >= 0 ? outline.sections[oldIndex].id : item.assertion.targetSectionId,
        },
        sourceRefs: item.sourceRefs.slice(0),
        origin: item.origin,
      });
    }
    let evidence: NoteGenerationEvidenceItem[] = remappedEvidence;
    if (evidence.length === 0) {
      evidence = buildPipelineEvidence(outline, bundle);
    }
    const normalizedResult: NoteGenerationStandardResult = {
      outline: outline,
      evidence: evidence,
      draft: draft,
      verification: result.verification,
    };
    return normalizedResult;
  }

  /**
   * 章节内容采用 MM-MD 规范化器的修复结果 (2026-09-19):
   * validateDraftDocument 把 ok=false (含规范化器已自动修复的兼容项, 如 \(\)→$..$)
   * 一律判 MM_MD_INVALID (hard), 而 LLM 天然输出 \( \) / \[ \] — 原判据下
   * 数学笔记几乎必然全灭。修复: fallbackRequired=false 时采用 normalizedText
   * (规范化器本职), 仅真正不可渲染的内容保留原值交由校验器判 hard。
   */
  private normalizeSectionContent(content: string): string {
    if (content.trim().length === 0) {
      return content;
    }
    const validation: ContentValidationResult = this.contentProtocol.validateNoteMarkdown(content);
    if (!validation.fallbackRequired && validation.normalizedText.trim().length > 0) {
      return validation.normalizedText;
    }
    return content;
  }

  private combineVerification(
    model: NoteGenerationVerification,
    local: NoteGenerationVerification,
  ): NoteGenerationVerification {
    let status: EvidenceVerificationStatus = model.status;
    if (local.status === 'contradicted') {
      status = 'contradicted';
    } else if (local.status === 'ambiguous' && status === 'supported') {
      status = 'ambiguous';
    }
    const issues: NoteGenerationIssue[] = [];
    for (const issue of model.issues) {
      issues.push(issue);
    }
    for (const issue of local.issues) {
      issues.push(issue);
    }
    const decisions: NoteGenerationEvidenceDecision[] = [];
    for (const decision of model.decisions) {
      decisions.push(decision);
    }
    for (const decision of local.decisions) {
      let exists: boolean = false;
      for (const existing of decisions) {
        if (existing.evidenceId === decision.evidenceId) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        decisions.push(decision);
      }
    }
    return { status: status, issues: issues, checkedEvidenceIds: model.checkedEvidenceIds, decisions: decisions };
  }

  private standardSourceText(bundle: SourceBundle): string {
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + '] ' + fragment.text);
    }
    return lines.join('\n');
  }

  private verifierEvidenceText(evidence: NoteGenerationEvidenceItem[]): string {
    const lines: string[] = [];
    let index: number = 0;
    for (const item of evidence) {
      lines.push('[' + index.toString() + '] origin=' + item.origin
        + '; assertionType=' + item.assertion.type
        + '; targetSectionId=' + item.assertion.targetSectionId
        + '; assertionText=' + JSON.stringify(item.assertion.text));
      for (const ref of item.sourceRefs) {
        lines.push('  sourceRef sourceId=' + ref.sourceId
          + '; sourceFingerprint=' + ref.sourceFingerprint
          + '; start=' + ref.start.toString()
          + '; end=' + ref.end.toString()
          + '; excerpt=' + JSON.stringify(ref.excerpt));
      }
      index += 1;
    }
    return lines.length === 0 ? '[]' : lines.join('\n');
  }

  private parseStandardResult(parsed: Record<string, Object>, sources: SourceBundle): NoteGenerationStandardResult {
    const nested: Record<string, Object> | undefined = this.findNestedStandardArtifacts(parsed);
    const parsedDraft: Object | undefined = this.readRecordValue(parsed, 'draft');
    const parsedOutline: Object | undefined = this.readRecordValue(parsed, 'outline');
    if (nested !== undefined && !this.isDraftArtifactsCandidate(parsed)
      && parsedDraft === undefined && parsedOutline === undefined) {
      return this.parseStandardResult(nested, sources);
    }
    const outlineValue: Object | undefined = parsedOutline;
    const evidenceValue: Object | undefined = this.readRecordValue(parsed, 'evidence');
    const draftValue: Object | undefined = parsedDraft;
    if (outlineValue !== undefined && draftValue !== undefined && evidenceValue === undefined) {
      return {
        outline: this.parseOutline(outlineValue as Record<string, Object>),
        evidence: [],
        draft: this.parseDraftDocument(draftValue as Record<string, Object>),
        verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] },
      };
    }
    if (outlineValue === undefined || evidenceValue === undefined || draftValue === undefined) {
      if (draftValue !== undefined) {
        return parseDirectStandardArtifacts(draftValue as Record<string, Object>, sources);
      }
      if (this.readRecordValue(parsed, 'title') !== undefined
        && this.readRecordValue(parsed, 'sections') !== undefined) {
        return parseDirectStandardArtifacts(parsed, sources);
      }
      throw new Error('standard artifacts require draft; keys=' + Object.keys(parsed).join(','));
    }
    const outline: NoteGenerationOutline = this.parseOutline(outlineValue as Record<string, Object>);
    const sourceIdsBySectionId: Map<string, string[]> = new Map<string, string[]>();
    for (const section of outline.sections) {
      sourceIdsBySectionId.set(section.id, section.sourceIds);
    }
    const candidates: NoteGenerationEvidenceCandidate[] = this.parseEvidenceCandidates(evidenceValue);
    return {
      outline: outline,
      evidence: normalizeEvidenceItems(candidates, sources, sourceIdsBySectionId),
      draft: this.parseDraftDocument(draftValue as Record<string, Object>),
      verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] },
    };
  }

  private parseOutline(value: Record<string, Object>): NoteGenerationOutline {
    const sectionValue: Object | undefined = this.readRecordValue(value, 'sections');
    const sections: NoteGenerationOutlineSection[] = [];
    if (sectionValue !== undefined && Array.isArray(sectionValue)) {
      for (const item of sectionValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        const mustInclude: string[] = this.readStringArray(this.readRecordValue(record, 'mustInclude'));
        const sourceIds: string[] = this.readStringArray(this.readRecordValue(record, 'sourceIds'));
        sections.push({
          id: String(this.readRecordValue(record, 'id') ?? ''),
          label: String(this.readRecordValue(record, 'label') ?? ''),
          order: Number(this.readRecordValue(record, 'order') ?? sections.length),
          mustInclude: mustInclude,
          sourceIds: sourceIds,
        });
      }
    }
    return { schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION, sections: sections };
  }

  private parseEvidenceCandidates(value: Object): NoteGenerationEvidenceCandidate[] {
    const evidence: NoteGenerationEvidenceCandidate[] = [];
    if (!Array.isArray(value)) {
      return evidence;
    }
    for (const item of value as Object[]) {
      const record: Record<string, Object> = item as Record<string, Object>;
      const references: EvidenceCandidateSourceRef[] = [];
      const referenceValue: Object | undefined = this.readRecordValue(record, 'sourceRefs');
      if (referenceValue !== undefined && Array.isArray(referenceValue)) {
        for (const reference of referenceValue as Object[]) {
          const ref: Record<string, Object> = reference as Record<string, Object>;
          references.push({
            sourceId: String(this.readRecordValue(ref, 'sourceId') ?? ''),
            excerpt: String(this.readRecordValue(ref, 'excerpt') ?? ''),
          });
        }
      }
      const typeValue: string = String(this.readRecordValue(record, 'type') ?? 'claim');
      const evidenceType: EvidenceItemType = typeValue === 'definition' || typeValue === 'formula'
        || typeValue === 'step' || typeValue === 'example' || typeValue === 'conclusion' ? typeValue : 'claim';
      evidence.push({
        type: evidenceType,
        claim: String(this.readRecordValue(record, 'claim') ?? ''),
        sourceRefs: references,
        targetSectionId: String(this.readRecordValue(record, 'targetSectionId') ?? ''),
      });
    }
    return evidence;
  }

  private readVerifierStatusValue(json: Record<string, Object>): Object | undefined {
    const statusValue: Object | undefined = this.readRecordValue(json, 'status');
    if (statusValue !== undefined) {
      return statusValue;
    }
    return this.readRecordValue(json, 'overallStatus');
  }

  // 入参由 seam 预解析并保证顶层对象, 空文分支不再存在 (2026-09-19 统一 JSON 生命周期)
  private parseVerification(
    parsed: Record<string, Object>,
    evidence: NoteGenerationEvidenceItem[],
  ): NoteGenerationVerification {
    const statusValue: string = String(this.readVerifierStatusValue(parsed) ?? 'ambiguous');
    let status: EvidenceVerificationStatus = statusValue === 'supported'
      ? 'supported' : statusValue === 'contradicted' ? 'contradicted' : 'ambiguous';
    const decisions: NoteGenerationEvidenceDecision[] = [];
    const checkedEvidenceIds: string[] = [];
    const statusesValue: Object | undefined = this.readRecordValue(parsed, 'evidenceStatuses');
    if (statusesValue !== undefined && Array.isArray(statusesValue)) {
      const statuses: Object[] = statusesValue as Object[];
      for (let index: number = 0; index < evidence.length; index += 1) {
        const itemStatus: string = String(statuses[index] ?? 'ambiguous');
        const decisionStatus: EvidenceVerificationStatus = itemStatus === 'supported'
          ? 'supported' : itemStatus === 'contradicted' ? 'contradicted' : 'ambiguous';
        decisions.push({
          evidenceId: evidence[index].id,
          status: decisionStatus,
        });
        checkedEvidenceIds.push(evidence[index].id);
      }
    }
    const issues: NoteGenerationIssue[] = [];
    const issueValue: Object | undefined = this.readRecordValue(parsed, 'issues');
    if (issueValue !== undefined && Array.isArray(issueValue)) {
      for (const item of issueValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        const severityValue: string = String(this.readRecordValue(record, 'severity') ?? 'hard');
        const severity: 'hard' | 'soft' = severityValue === 'soft' ? 'soft' : 'hard';
        issues.push({
          stage: 'verifier',
          code: String(this.readRecordValue(record, 'code') ?? 'VERIFIER_PROCESS_ISSUE'),
          severity: severity,
          message: String(this.readRecordValue(record, 'message') ?? 'verifier reported a process issue'),
          repairable: false,
          sourceId: this.readOptionalString(record, 'sourceId'),
          sectionId: this.readOptionalString(record, 'sectionId'),
        });
      }
    }
    for (let index: number = 0; index < decisions.length; index += 1) {
      const decision: NoteGenerationEvidenceDecision = decisions[index];
      const sectionId: string = evidence[index].assertion.targetSectionId;
      if (decision.status === 'contradicted') {
        status = 'contradicted';
        issues.push({
          stage: 'verifier', code: 'EVIDENCE_CONTRADICTED', severity: 'hard',
          message: 'the assertion is contradicted by its cited source', repairable: false, sectionId: sectionId,
        });
      } else if (decision.status === 'ambiguous') {
        if (status === 'supported') {
          status = 'ambiguous';
        }
        issues.push({
          stage: 'verifier', code: 'EVIDENCE_AMBIGUOUS', severity: 'hard',
          message: 'the cited source does not unambiguously support the assertion', repairable: false,
          sectionId: sectionId,
        });
      }
    }
    let hasHardIssue: boolean = false;
    for (const issue of issues) {
      if (issue.severity === 'hard') {
        hasHardIssue = true;
        break;
      }
    }
    if (!hasHardIssue && status === 'contradicted') {
      issues.push({
        stage: 'verifier', code: 'NOTE_CONTRADICTED', severity: 'hard',
        message: 'the verifier found the note contradicted by the supplied sources or requirements',
        repairable: false,
      });
    } else if (!hasHardIssue && status === 'ambiguous') {
      issues.push({
        stage: 'verifier', code: 'NOTE_AMBIGUOUS', severity: 'hard',
        message: 'the verifier could not establish that the complete note is supported', repairable: false,
      });
    }
    return {
      status: status,
      issues: issues,
      checkedEvidenceIds: checkedEvidenceIds,
      decisions: decisions,
    };
  }

  private validateIndependentVerifierJson(
    json: Record<string, Object>,
    evidence: NoteGenerationEvidenceItem[],
  ): string[] {
    const issues: string[] = [];
    const statusValue: Object | undefined = this.readVerifierStatusValue(json);
    if (statusValue !== 'supported' && statusValue !== 'contradicted' && statusValue !== 'ambiguous') {
      issues.push('status must be supported, contradicted, or ambiguous');
    }
    const verifierIssuesValue: Object | undefined = this.readRecordValue(json, 'issues');
    if (verifierIssuesValue === undefined || !Array.isArray(verifierIssuesValue)) {
      issues.push('issues must be an array');
    } else {
      for (const issueValue of verifierIssuesValue as Object[]) {
        if (issueValue === null || typeof issueValue !== 'object' || Array.isArray(issueValue)) {
          issues.push('each verifier issue must be an object');
          continue;
        }
        const issue: Record<string, Object> = issueValue as Record<string, Object>;
        const codeValue: Object | undefined = this.readRecordValue(issue, 'code');
        const severityValue: Object | undefined = this.readRecordValue(issue, 'severity');
        const messageValue: Object | undefined = this.readRecordValue(issue, 'message');
        if (typeof codeValue !== 'string' || codeValue.trim().length === 0) {
          issues.push('each verifier issue must include a non-empty code');
        }
        if (severityValue !== 'hard' && severityValue !== 'soft') {
          issues.push('each verifier issue severity must be hard or soft');
        }
        if (typeof messageValue !== 'string' || messageValue.trim().length === 0) {
          issues.push('each verifier issue must include a non-empty message');
        }
      }
    }
    const statusesValue: Object | undefined = this.readRecordValue(json, 'evidenceStatuses');
    if (statusesValue === undefined || !Array.isArray(statusesValue)) {
      return ['evidenceStatuses must be an array'];
    }
    const statuses: Object[] = statusesValue as Object[];
    if (statuses.length !== evidence.length) {
      issues.push('evidenceStatuses must contain one status for every evidence item');
    }
    for (const statusValue of statuses) {
      if (statusValue !== 'supported' && statusValue !== 'contradicted' && statusValue !== 'ambiguous') {
        issues.push('evidence status must be supported, contradicted, or ambiguous');
      }
    }
    return issues;
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
    return this.toKnowledgeUnit(ext, Date.now(), document.summary);
  }

  private budgetedRequestTokens(request: NoteGenerationRequest, fallback: number): number {
    return this.budgetedTokens(request.tokenBudget, fallback);
  }

  private budgetedTokens(budget: number | undefined, requested: number): number {
    if (budget === undefined || budget <= 0) {
      return requested;
    }
    return Math.min(requested, budget);
  }

  private lightSourceText(request: NoteGenerationRequest): string {
    const lines: string[] = [];
    for (const fragment of request.sources.fragments) {
      lines.push('[source:' + fragment.id + '] ' + fragment.text);
    }
    return lines.join('\n');
  }

  private structuredResponseFormat(
    schemaText: string = NOTE_DRAFT_JSON_SCHEMA,
    name: string = 'mindtrace_note_draft',
  ): LlmResponseFormat {
    const schema: Record<string, Object> = JSON.parse(schemaText) as Record<string, Object>;
    const jsonSchema: LlmJsonSchema = {
      name: name,
      strict: true,
      schema: schema,
    };
    const config = LlmConfig.getInstance();
    if (config.supportsStrictStructuredOutput()) {
      return { type: 'json_schema', json_schema: jsonSchema };
    }
    return { type: 'json_object' };
  }

  private verificationResponseFormat(evidence: NoteGenerationEvidenceItem[]): LlmResponseFormat {
    const schemaText: string = buildNoteVerificationJsonSchema(evidence.length);
    return this.structuredResponseFormat(schemaText, 'mindtrace_note_verification');
  }

  private parseDraftDocument(parsed: Record<string, Object>): NoteDraftDocument {
    const sectionsValue: Object | undefined = this.readRecordValue(parsed, 'sections');
    if (sectionsValue === undefined || !Array.isArray(sectionsValue)) {
      throw new Error('light draft sections missing');
    }
    const sections: NoteDraftSection[] = [];
    const rawSections: Object[] = sectionsValue as Object[];
    for (const rawSection of rawSections) {
      const record: Record<string, Object> = rawSection as Record<string, Object>;
      const sourceIds: string[] = this.readStringArray(this.readRecordValue(record, 'sourceIds'));
      sections.push({
        id: String(this.readRecordValue(record, 'id') ?? ''),
        label: String(this.readRecordValue(record, 'label') ?? ''),
        content: String(this.readRecordValue(record, 'content') ?? ''),
        sourceIds: sourceIds,
        state: this.readRecordValue(record, 'state') === 'locked' ? 'locked' : 'generated',
        baseHash: String(this.readRecordValue(record, 'baseHash') ?? ''),
      });
    }
    return {
      schemaVersion: String(this.readRecordValue(parsed, 'schemaVersion') ?? ''),
      title: String(this.readRecordValue(parsed, 'title') ?? ''),
      summary: String(this.readRecordValue(parsed, 'summary') ?? ''),
      subject: String(this.readRecordValue(parsed, 'subject') ?? ''),
      category: String(this.readRecordValue(parsed, 'category') ?? ''),
      chapter: String(this.readRecordValue(parsed, 'chapter') ?? ''),
      difficulty: Number(this.readRecordValue(parsed, 'difficulty') ?? 0),
      tags: this.readStringArray(this.readRecordValue(parsed, 'tags')),
      sections: sections,
    };
  }

  private readStringArray(value: Object | undefined): string[] {
    if (value === undefined || !Array.isArray(value)) {
      return [];
    }
    const result: string[] = [];
    const values: Object[] = value as Object[];
    for (const item of values) {
      if (typeof item === 'string') {
        result.push(item);
      }
    }
    return result;
  }

  private toKnowledgeUnit(ext: KnowledgeUnitExt, createdAt: number, summaryOverride: string = ''): KnowledgeUnit {
    const generatedSummary: string = this.summaryFromFields(ext);
    const summary: string = summaryOverride.trim().length > 0
      ? this.contentExcerptBuilder.buildSummary(summaryOverride, 60)
      : generatedSummary;
    const now: number = createdAt > 0 ? createdAt : Date.now();
    return {
      id: this.uuid(),
      title: ext.title,
      content: this.contentFromFields(ext),
      summary: summary,
      tags: ext.tags,
      subject: ext.subject,
      category: ext.type,
      chapter: ext.chapter,
      difficulty: this.toDifficultyLevel(ext.difficulty),
      source: ext.source.length > 0 ? ext.source : 'camera_capture',
      createdAt: now,
      updatedAt: now,
      reviewStatus: ReviewStatus.NEW,
      nextReviewAt: now + 24 * 60 * 60 * 1000,
      intervalDays: 1,
      easeFactor: 2.5,
      repetitions: 0,
      prerequisites: [],
      related: [],
      embedding: [],
      userId: ext.userId,
      version: 1,
    };
  }

  private summaryFromFields(ext: KnowledgeUnitExt): string {
    const summaryParts: string[] = [];
    for (const field of ext.fields) {
      const normalized: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(field.value);
      if (!normalized.fallbackRequired && normalized.normalizedText.length > 0) {
        summaryParts.push(normalized.normalizedText);
      }
    }
    const source: string = summaryParts.length > 0 ? summaryParts.join('\n') : ext.content;
    const summary: string = this.contentExcerptBuilder.buildSummary(source, 60);
    if (summary.length > 0) {
      return summary;
    }
    return ext.title.trim();
  }

  private toDifficultyLevel(value: number): DifficultyLevel {
    if (value <= 1) { return DifficultyLevel.EASY; }
    if (value === 2) { return DifficultyLevel.MEDIUM; }
    if (value === 3) { return DifficultyLevel.HARD; }
    return DifficultyLevel.EXPERT;
  }

  private uuid(): string {
    return 'KB-' + Date.now().toString(36) + '-' + Math.random().toString(36).substring(2, 8);
  }
  private async callAi(
    ocrText: string,
    typeHint?: string,
    subjectHint?: string,
    chapterHint: string = '',
    confidenceHint: number = 0,
  ): Promise<AiRawResponse> {
    // 可选分类 hint：TypeClassifier 只提供软参考，KnowledgeModel 仍按正文独立结构化。
    const hint: string = (typeHint !== undefined && typeHint.length > 0) || (subjectHint !== undefined && subjectHint.length > 0)
      ? '\n\n## 分类 hint (来自 TypeClassifier 粗分类, AI 自行决定是否采纳)\n' +
        '- 粗分类: ' + (typeHint ?? '未知') + '\n' +
        '- 学科: ' + (subjectHint ?? '未知') + '\n' +
        '- 章节/知识点: ' + (chapterHint.length > 0 ? chapterHint : '未知') + '\n' +
        '- 置信度: ' + confidenceHint.toString() + '\n' +
        '优先用它减少五类歧义；如果正文证据更强, 以正文为准。'
      : '';
    const prompt: string = this.promptBuilder.buildPrompt(ocrText) + hint;

    const systemMsg: ChatMessage = {
      role: 'system',
      content: prompt + '\n' + JSON_ONLY_RULES + '\n' + LATEX_GENERATION_RULES,
    };
    const userText: string = ocrText.length > KNOWLEDGE_INPUT_LIMIT ? ocrText.substring(0, KNOWLEDGE_INPUT_LIMIT) : ocrText;
    const userMsg: ChatMessage = { role: 'user', content: userText };
    const messages: ChatMessage[] = [systemMsg, userMsg];

    console.info('[KnowledgeModel] callAi: systemPrompt=' + prompt.length.toString() + ' chars, userText=' + userText.length.toString() + ' chars');
    let guarded: LlmGuardJsonResult;
    try {
      guarded = await new LlmGuard().callJsonWithRetry(messages, {
        maxTokens: KNOWLEDGE_MAX_TOKENS,
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        label: 'KnowledgeModel structure',
        cancellationToken: this.cancellationToken,
      }, (json: Record<string, Object>): LlmGuardValidationResult => this.validateAiJson(json));
      console.info('[KnowledgeModel] callAi response received, len=' + guarded.raw.length.toString()
        + ', attempts=' + guarded.attempts.toString());
    } catch (llmErr) {
      console.error('[KnowledgeModel] callAi LLM error: ' + (llmErr as Error).message);
      // §13.5: LlmError 原样上抛 (保留 kind 供 StructureNode 映射 retriable),
      // 仅包装非 LlmError 的意外异常
      if (llmErr instanceof LlmError) {
        throw new LlmError(llmErr.message, llmErr.kind);
      }
      throw new Error('LLM 调用失败: ' + (llmErr as Error).message);
    }

    if (!guarded.raw || guarded.raw.length === 0) {
      console.error('[KnowledgeModel] callAi empty content after 200 OK');
      throw new Error('AI 返回为空:content 为空');
    }

    const parsed: Record<string, Object> = guarded.json;

    const aiRaw: AiRawResponse = {
      category: this.normalizeCategory(String(this.readRecordValue(parsed, 'category') ?? ''), typeHint),
      subject: this.normalizeSubject(String(this.readRecordValue(parsed, 'subject') ?? ''), subjectHint),
      chapter: this.normalizeChapter(String(this.readRecordValue(parsed, 'chapter') ?? '')),
      title: this.normalizeTitle(String(this.readRecordValue(parsed, 'title') ?? ''), userText),
      tags: this.normalizeStringArray(this.readRecordValue(parsed, 'tags')),
      difficulty: normalizeDraftDifficulty(Number(this.readRecordValue(parsed, 'difficulty') ?? 3)),
      importance: this.normalizeScore(Number(this.readRecordValue(parsed, 'importance') ?? 3)),
      fields: this.normalizeFields(this.readRecordValue(parsed, 'fields')),
    };

    return aiRaw;
  }

  private validateAiJson(parsed: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    const categoryValue: Object | undefined = this.readRecordValue(parsed, 'category');
    const categoryText: string = typeof categoryValue === 'string' ? categoryValue : '';
    if (categoryText.length === 0 || !isKnownNoteType(normalizeNoteType(categoryText))) {
      issues.push('category must be one of: ' + NOTE_TYPE_KEYS.join('/'));
    }
    if (typeof this.readRecordValue(parsed, 'subject') !== 'string') {
      issues.push('subject must be a string');
    }
    const titleValue: Object | undefined = this.readRecordValue(parsed, 'title');
    if (typeof titleValue !== 'string' || titleValue.trim().length === 0) {
      issues.push('title must be a non-empty string');
    } else if (this.contentProtocol.hasFormulaSyntax(titleValue)) {
      issues.push('title must not contain a formula');
    }
    const tagsValue: Object | undefined = this.readRecordValue(parsed, 'tags');
    if (!Array.isArray(tagsValue)) {
      issues.push('tags must be an array');
    } else {
      const tags: Object[] = tagsValue as Object[];
      for (const tag of tags) {
        if (typeof tag !== 'string' || String(tag).trim().length === 0) {
          issues.push('each tag must be a non-empty string');
          break;
        }
        if (this.contentProtocol.hasFormulaSyntax(String(tag))) {
          issues.push('tags must not contain formulas');
          break;
        }
      }
    }
    if (!this.isScoreValue(this.readRecordValue(parsed, 'difficulty'), 4)) {
      issues.push('difficulty must be a number from 1 to 4');
    }
    if (!this.isScoreValue(this.readRecordValue(parsed, 'importance'), 5)) {
      issues.push('importance must be a number from 1 to 5');
    }
    const fieldsValue: Object | undefined = this.readRecordValue(parsed, 'fields');
    if (!Array.isArray(fieldsValue)) {
      issues.push('fields must be an array');
    } else {
      const fields: Object[] = fieldsValue as Object[];
      if (fields.length === 0) {
        issues.push('fields must not be empty');
      }
      for (const field of fields) {
        const record: Record<string, Object> = field as Record<string, Object>;
        const keyValue: Object | undefined = this.readRecordValue(record, 'key');
        const labelValue: Object | undefined = this.readRecordValue(record, 'label');
        const fieldValue: Object | undefined = this.readRecordValue(record, 'value');
        if (typeof keyValue !== 'string' || keyValue.trim().length === 0) {
          issues.push('each field.key must be a non-empty string');
          break;
        }
        if (typeof labelValue !== 'string' || labelValue.trim().length === 0) {
          issues.push('each field.label must be a non-empty string');
          break;
        }
        if (this.contentProtocol.hasFormulaSyntax(keyValue)
          || this.contentProtocol.hasFormulaSyntax(labelValue)) {
          issues.push('field.key and field.label must not contain formulas');
          break;
        }
        if (typeof fieldValue !== 'string' || fieldValue.trim().length === 0) {
          issues.push('each field.value must be a non-empty string');
          break;
        }
        const contentResult: ContentValidationResult = this.contentProtocol.validateNoteMarkdown(fieldValue);
        if (!contentResult.ok) {
          issues.push('field.value violates MM-MD-v1: ' + contentResult.issues.join(', '));
          break;
        }
      }
    }
    return {
      ok: issues.length === 0,
      issues: issues,
    };
  }

  private isScoreValue(value: Object | undefined, maximum: number): boolean {
    if (typeof value !== 'number' && typeof value !== 'string') {
      return false;
    }
    const score: number = Number(value);
    return !Number.isNaN(score) && score >= 1 && score <= maximum;
  }
  /**
   * 合并标签：AI 返回的标签 + 最小类名，去重
   *
   * @param aiRaw - AI 原始响应
   * @returns 去重后的标签数组
   */
  private buildTags(aiRaw: AiRawResponse): string[] {
    const tags: string[] = [];
    tags.push(aiRaw.category);
    for (const tag of aiRaw.tags) {
      if (tags.indexOf(tag) === -1) {
        tags.push(tag);
      }
    }
    return tags;
  }

  /**
   * 标记需要用户确认的字段（标题/难度/重要性）
   * 证明题和计算题的标题由 AI 总结，用户可以修改
   *
   * @param unit - 正在构建的知识单元
   * @param aiRaw - AI 原始响应
   */
  private markNeedsUserInput(unit: KnowledgeUnitExt, aiRaw: AiRawResponse): void {
    if (aiRaw.category === '证明题' || aiRaw.category === '计算题') {
      unit.needsUserInput.push('title');
    }
    unit.needsUserInput.push('difficulty');
    unit.needsUserInput.push('importance');
  }

  private contentFromFields(ext: KnowledgeUnitExt): string {
    const sections: string[] = [];
    let index: number = 0;
    for (const field of ext.fields) {
      const candidateLabel: string = field.label.trim().length > 0 ? field.label : field.key;
      const label: string = normalizeDraftSectionLabel(candidateLabel, index);
      const valueResult: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(field.value);
      const value: string = valueResult.normalizedText.trim();
      if (value.length > 0) {
        sections.push('## ' + label + '\n' + value);
      }
      index += 1;
    }
    const raw: string = ext.content.trim();
    if (raw.length > 0) {
      sections.push('## 原文\n' + raw);
    }
    if (sections.length === 0) {
      return ext.content;
    }
    return this.contentProtocol.normalizeNoteMarkdown(sections.join('\n\n')).normalizedText;
  }

  private normalizeCategory(value: string, fallback?: string): KnowledgeCategory {
    const normalized: string = normalizeNoteType(value);
    if (isKnownNoteType(normalized)) {
      return normalized as KnowledgeCategory;
    }
    if (fallback !== undefined) {
      const fallbackType: string = normalizeNoteType(fallback);
      if (isKnownNoteType(fallbackType)) {
        return fallbackType as KnowledgeCategory;
      }
    }
    return KNOWLEDGE_FALLBACK_CATEGORY;
  }

  private normalizeSubject(value: string, fallback?: string): string {
    const subject: string = value.trim();
    if (subject.length > 0 && subject !== '未知' && subject !== 'null' && subject !== 'undefined') {
      return subject;
    }
    if (fallback !== undefined) {
      const fallbackSubject: string = fallback.trim();
      if (fallbackSubject.length > 0 && fallbackSubject !== '未知') {
        return fallbackSubject;
      }
    }
    return KNOWLEDGE_FALLBACK_SUBJECT;
  }

  private normalizeChapter(value: string): string {
    const chapter: string = value.trim();
    if (chapter.length > 0 && chapter !== '未知' && chapter !== 'null' && chapter !== 'undefined') {
      return chapter;
    }
    return '';
  }

  private normalizeTitle(value: string, fallbackText: string): string {
    const title: string = value.trim();
    if (title.length > 0 && title !== '未知' && title !== 'null' && title !== 'undefined') {
      return title;
    }
    const firstLine: string = fallbackText.split('\n')[0].trim();
    if (firstLine.length > 0 && firstLine.length <= 60) {
      return firstLine;
    }
    return '数学笔记';
  }

  private normalizeScore(value: number): number {
    if (value >= 1 && value <= 5) {
      return value;
    }
    return 3;
  }

  private normalizeStringArray(value: Object | undefined): string[] {
    const result: string[] = [];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return result;
    }
    const items: Object[] = value as Object[];
    for (const item of items) {
      const text: string = String(item).trim();
      if (text.length > 0 && result.indexOf(text) < 0) {
        result.push(text);
      }
    }
    return result;
  }

  private normalizeFields(value: Object | undefined): StructuredField[] {
    const result: StructuredField[] = [];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return result;
    }
    const items: Object[] = value as Object[];
    for (const item of items) {
      const record: Record<string, Object> = item as Record<string, Object>;
      const key: string = String(this.readRecordValue(record, 'key') ?? '').trim();
      const label: string = String(this.readRecordValue(record, 'label') ?? '').trim();
      const fieldValue: string = String(this.readRecordValue(record, 'value') ?? '').trim();
      if ((key.length > 0 || label.length > 0) && fieldValue.length > 0) {
        result.push({
          key: key.length > 0 ? key : label,
          label: label.length > 0 ? label : key,
          value: fieldValue,
        });
      }
    }
    return result;
  }

  private async resolveClassificationHint(
    ocrText: string,
    type?: string,
    subject?: string,
    chapter: string = '',
  ): Promise<ClassificationResult> {
    const externalHint: ClassificationResult = this.buildExternalHint(ocrText, type, subject, chapter);
    if (type !== undefined || subject !== undefined || chapter.length > 0) {
      return externalHint;
    }
    try {
      const classifier = new TypeClassifier();
      const classified: ClassificationResult = await classifier.classifyText(
        ocrText,
        KNOWLEDGE_CLASSIFY_HINT_TIMEOUT_MS,
      );
      return this.mergeClassificationHint(externalHint, classified);
    } catch (e) {
      console.warn('[KnowledgeModel] TypeClassifier hint skipped: ' + ((e as Error).message ?? String(e)));
      return externalHint;
    }
  }

  private buildExternalHint(
    ocrText: string,
    type?: string,
    subject?: string,
    chapter: string = '',
  ): ClassificationResult {
    return {
      type: this.normalizeCategory(type ?? '', undefined),
      subject: this.normalizeSubject(subject ?? '', undefined),
      chapter: chapter,
      confidence: type !== undefined || subject !== undefined || chapter.length > 0 ? 0.8 : 0,
      ocrText: ocrText,
    };
  }

  private mergeClassificationHint(
    base: ClassificationResult,
    classified: ClassificationResult,
  ): ClassificationResult {
    const result: ClassificationResult = {
      type: base.type,
      subject: base.subject,
      chapter: base.chapter ?? '',
      confidence: base.confidence,
      ocrText: classified.ocrText ?? base.ocrText,
    };
    if (classified.confidence >= KNOWLEDGE_HINT_CONFIDENCE_MIN) {
      result.type = this.normalizeCategory(classified.type, base.type);
      result.confidence = classified.confidence;
    }
    if (classified.subject.trim().length > 0 && classified.subject !== KNOWLEDGE_FALLBACK_SUBJECT) {
      result.subject = classified.subject.trim();
    }
    if ((classified.chapter ?? '').trim().length > 0) {
      result.chapter = (classified.chapter ?? '').trim();
    }
    return result;
  }
}
