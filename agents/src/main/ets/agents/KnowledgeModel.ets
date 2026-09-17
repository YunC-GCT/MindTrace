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
  LlmGuard,
  LlmClient,
  LlmConfig,
  normalizeNoteType,
  NOTE_TYPE_KEYS,
  ReviewStatus,
  normalizeOutline,
  segmentSourceBundle,
  buildDeepOutline,
  sourceFingerprint,
  validateSourceBundle,
  NoteGenerationEvidenceVerifier,
  NOTE_OUTLINE_SCHEMA_VERSION,
  NOTE_DRAFT_SCHEMA_VERSION,
  NOTE_EVIDENCE_JSON_SCHEMA,
  NOTE_STANDARD_JSON_SCHEMA,
  NOTE_VERIFICATION_JSON_SCHEMA,
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
  LlmCallResult,
  LlmJsonSchema,
  LlmResponseFormat,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationIssue,
  NoteGenerationRequest,
  NoteGenerationOutline,
  NoteGenerationOutlineSection,
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
  SourceBundle,
  NoteGenerationRequirement,
  IncrementalPlan,
  IncrementalSection,
  IncrementalPatch,
  IncrementalPatchResponse,
  SourceFragment,
} from 'common';
import { NOTE_DRAFT_JSON_SCHEMA, parseDirectStandardArtifacts, validateDraftDocument, validateDraftShape } from 'common';
import { TypeClassifier } from './TypeClassifier';
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

export class KnowledgeModel {
  private contentProtocol: ContentProtocol = new ContentProtocol();
  private contentExcerptBuilder: ContentExcerptBuilder = new ContentExcerptBuilder();
  private promptBuilder: PromptBuilder = new PromptBuilder();
  private llm: LlmCaller;

  constructor(llm?: LlmCaller) {
    this.llm = llm ?? new LlmClient();
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
        + 'Every section must cite source IDs in sourceIds. Return JSON only.\n'
        + 'Original source fragments are authoritative; summaries never replace conflicting raw text.\n'
        + request.instruction + '\n' + NOTE_DRAFT_JSON_SCHEMA,
    };
    const userMessage: ChatMessage = { role: 'user', content: sourceText };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    const responseFormat = this.structuredResponseFormat();
    const callResult: LlmCallResult = await this.llm.call({
      messages: messages,
      maxTokens: this.budgetedRequestTokens(request, 1200),
      timeoutMs: KNOWLEDGE_TIMEOUT_MS,
      responseFormat: responseFormat,
    });
    const raw: string = callResult.text ?? '';
    const jsonText: string = new LlmGuard().extractJsonObject(raw);
    if (jsonText.length === 0) {
      throw new Error('light draft missing JSON object');
    }
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(jsonText) as Record<string, Object>;
    } catch (e) {
      throw new Error('light draft invalid JSON');
    }
    const shapeIssues: string[] = validateDraftShape(parsed);
    if (shapeIssues.length > 0) {
      throw new Error('light draft schema failed: ' + shapeIssues.join(','));
    }
    const document: NoteDraftDocument = this.parseDraftDocument(parsed);
    const sourceIds: string[] = [];
    for (const fragment of request.sources.fragments) {
      sourceIds.push(fragment.id);
    }
    const issues: NoteGenerationIssue[] = validateDraftDocument(document, sourceIds);
    if (issues.length > 0) {
      const codes: string[] = [];
      for (const issue of issues) {
        codes.push(issue.code);
      }
      throw new Error('light draft validation failed: ' + codes.join(','));
    }
    return document;
  }

  async structureStandardDraft(request: NoteGenerationRequest): Promise<NoteGenerationStandardResult> {
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
    const verification: NoteGenerationVerification = await this.callIndependentVerifier(
      normalized,
      request.sources,
      requirement,
      request.tokenBudget,
    );
    const verified: NoteGenerationStandardResult = this.applyVerification(normalized, verification);
    verified.reextractionCount = 0;
    return verified;
  }

  async repairStandardDraft(
    request: NoteGenerationRequest,
    current: NoteGenerationStandardResult,
    issues: NoteGenerationIssue[],
  ): Promise<NoteGenerationStandardResult> {
    const requirement: NoteGenerationRequirement = request.requirement ?? {
      detailLevel: 'normal',
      mustInclude: [],
      mustAvoid: [],
      targetSectionIds: [],
      preserveUserEdits: true,
    };
    const repairedEvidence: NoteGenerationEvidenceItem[] = await this.callEvidenceRepair(request, current, requirement);
    const repaired: NoteGenerationStandardResult = {
      outline: current.outline,
      evidence: repairedEvidence,
      draft: current.draft,
      verification: { status: 'supported', issues: issues, checkedEvidenceIds: [], decisions: [] },
    };
    const normalized: NoteGenerationStandardResult = this.normalizeStandardResult(repaired, request.sources, request.instruction);
    const verification: NoteGenerationVerification = await this.callIndependentVerifier(
      normalized,
      request.sources,
      requirement,
      request.tokenBudget,
    );
    return this.mergeVerifiedEvidence(current, this.applyVerification(normalized, verification), request.sources, requirement);
  }

  async structureDeepDraft(request: NoteGenerationRequest): Promise<NoteGenerationDeepResult> {
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
    for (const outlineSection of outline.sections) {
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
      summary: summary,
      subject: subject.length === 0 ? '其它' : subject,
      category: category,
      chapter: chapter,
      difficulty: difficulty,
      tags: tags,
      sections: sections,
      instruction: request.instruction,
    };
    const evidence: NoteGenerationEvidenceItem[] = this.buildDeepEvidence(outline, sections, segments);
    const verification: NoteGenerationVerification = new NoteGenerationEvidenceVerifier().verify(
      outline,
      evidence,
      draft,
      request.sources,
      requirement,
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

  async repairDeepDraft(
    request: NoteGenerationRequest,
    current: NoteGenerationDeepResult,
    issues: NoteGenerationIssue[],
  ): Promise<NoteGenerationDeepResult> {
    const targets: string[] = [];
    for (const issue of issues) {
      if (issue.sectionId !== undefined && !targets.includes(issue.sectionId)) {
        targets.push(issue.sectionId);
      }
    }
    if (targets.length === 0 && current.outline.sections.length > 0) {
      targets.push(current.outline.sections[0].id);
    }
    const segments: NoteGenerationSegment[] = current.segments ?? segmentSourceBundle(request.sources);
    const ledger: NoteGenerationLedger = {
      formulas: current.ledger.formulas.slice(0),
      terminology: current.ledger.terminology.slice(0),
      conclusions: current.ledger.conclusions.slice(0),
    };
    const sections: NoteDraftSection[] = [];
    for (const outlineSection of current.outline.sections) {
      let next: NoteDraftSection | undefined = current.draft.sections.find(
        (item: NoteDraftSection): boolean => item.id === outlineSection.id,
      );
      if (targets.includes(outlineSection.id)) {
        const repairedDocument: NoteDraftDocument = await this.callDeepSectionDraft(
          request,
          outlineSection,
          segments,
          ledger,
        );
        next = repairedDocument.sections[0];
      }
      if (next === undefined) {
        throw new Error('deep repair lost section: ' + outlineSection.id);
      }
      const repairedSection: NoteDraftSection = {
        id: outlineSection.id,
        label: outlineSection.label,
        content: next.content,
        sourceIds: outlineSection.sourceIds.slice(0),
        state: next.state,
        baseHash: next.baseHash,
      };
      sections.push(repairedSection);
      this.updateDeepLedger(ledger, outlineSection, repairedSection.content, segments);
    }
    const draft: NoteDraftDocument = {
      schemaVersion: current.draft.schemaVersion,
      title: current.draft.title,
      summary: current.draft.summary,
      subject: current.draft.subject,
      category: current.draft.category,
      chapter: current.draft.chapter,
      difficulty: current.draft.difficulty,
      tags: current.draft.tags.slice(0),
      sections: sections,
      instruction: request.instruction,
    };
    const evidence: NoteGenerationEvidenceItem[] = this.buildDeepEvidence(current.outline, sections, segments);
    const verification: NoteGenerationVerification = new NoteGenerationEvidenceVerifier().verify(
      current.outline,
      evidence,
      draft,
      request.sources,
      request.requirement ?? { detailLevel: 'detailed', mustInclude: [], mustAvoid: [], targetSectionIds: [], preserveUserEdits: true },
    );
    return {
      outline: current.outline,
      evidence: evidence,
      draft: draft,
      verification: verification,
      ledger: ledger,
      segments: segments,
    };
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
    const result: LlmCallResult = await this.llm.call({
      messages: [systemMessage, { role: 'user', content: 'Return section RepairPatch objects only.' }],
      maxTokens: this.budgetedRequestTokens(request, 2400),
      timeoutMs: KNOWLEDGE_TIMEOUT_MS,
      responseFormat: { type: 'json_object' },
    });
    const jsonText: string = new LlmGuard().extractJsonObject(result.text ?? '');
    if (jsonText.length === 0) {
      throw new Error('incremental repair missing JSON object');
    }
    const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
    const value: Object | undefined = parsed['patches'];
    if (value === undefined || !Array.isArray(value)) {
      throw new Error('incremental repair requires patches only');
    }
    const patches: IncrementalPatch[] = [];
    for (const item of value as Object[]) {
      const record: Record<string, Object> = item as Record<string, Object>;
      const sectionId: string = String(record['sectionId'] ?? '');
      if (!plan.targetSectionIds.includes(sectionId) || record['operation'] !== 'replace') {
        throw new Error('incremental repair contains an unplanned patch');
      }
      patches.push({
        sectionId: sectionId,
        operation: 'replace',
        content: String(record['content'] ?? ''),
        sourceIds: this.readStringArray(record['sourceIds']),
      });
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
        + outlineSection.id + '. User instruction=' + request.instruction + '\n'
        + 'section label=' + outlineSection.label + '\n'
        + 'must include=' + outlineSection.mustInclude.join(',') + '\n'
        + 'shared ledger=' + JSON.stringify(ledger) + '\n'
        + 'relevant sources:\n' + relevantLines.join('\n') + '\n' + NOTE_DRAFT_JSON_SCHEMA,
    };
    const result: LlmCallResult = await this.llm.call({
      messages: [systemMessage, { role: 'user', content: 'Draft only this section in document JSON.' }],
      maxTokens: this.budgetedRequestTokens(request, 2400),
      timeoutMs: KNOWLEDGE_TIMEOUT_MS,
      responseFormat: this.structuredResponseFormat(),
    });
    const jsonText: string = new LlmGuard().extractJsonObject(result.text ?? '');
    const parsed: Record<string, Object> = this.parseJsonObjectOrThrow(
      jsonText.length === 0 ? '' : jsonText,
      'deep section draft',
    );
    if (jsonText.length === 0) {
      throw new Error('deep section draft missing JSON object: ' + outlineSection.id);
    }
    const document: NoteDraftDocument = this.parseDraftDocument(parsed);
    const sourceIds: string[] = outlineSection.sourceIds.slice(0);
    const localIssues: NoteGenerationIssue[] = validateDraftDocument(document, sourceIds);
    if (localIssues.length > 0) {
      throw new Error('deep section validation failed: ' + localIssues[0].code);
    }
    return document;
  }

  private updateDeepLedger(
    ledger: NoteGenerationLedger,
    outlineSection: NoteGenerationOutlineSection,
    content: string,
    segments: NoteGenerationSegment[],
  ): void {
    const sourceIds: string[] = outlineSection.sourceIds.slice(0);
    if (content.indexOf('=') >= 0 || content.indexOf('\\(') >= 0) {
      ledger.formulas.push({ key: 'formula-' + outlineSection.id, value: content, sourceIds: sourceIds, sectionId: outlineSection.id });
    }
    const words: string[] = content.split(' ');
    if (words.length > 0) {
      const term: string = words[0].trim();
      if (term.length > 0) {
        ledger.terminology.push({ key: term, value: term, sourceIds: sourceIds, sectionId: outlineSection.id });
      }
    }
    for (const segment of segments) {
      if (sourceIds.includes(segment.sourceId) && (segment.text.includes('因此') || segment.text.includes('结论'))) {
        ledger.conclusions.push({ key: 'conclusion-' + outlineSection.id, value: segment.text, sourceIds: sourceIds, sectionId: outlineSection.id });
      }
    }
  }

  private buildDeepEvidence(
    outline: NoteGenerationOutline,
    sections: NoteDraftSection[],
    segments: NoteGenerationSegment[],
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
      evidence.push({
        id: 'evidence-' + section.id,
        type: segment.boundary === 'formula_block' ? 'formula' : segment.boundary === 'derivation' ? 'step' : 'claim',
        claim: excerpt,
        sourceRefs: [{ sourceId: sourceId, excerpt: excerpt, start: 0, end: excerpt.length }],
        targetSectionId: section.id,
        verification: section.content.includes(excerpt) ? 'supported' : 'ambiguous',
      });
    }
    return evidence;
  }

  private async callEvidenceRepair(
    request: NoteGenerationRequest,
    current: NoteGenerationStandardResult,
    requirement: NoteGenerationRequirement,
  ): Promise<NoteGenerationEvidenceItem[]> {
    const failedIds: string[] = [];
    for (const item of current.evidence) {
      if (item.verification !== 'supported') {
        failedIds.push(item.id);
      }
    }
    for (const issue of current.verification.issues) {
      for (const item of current.evidence) {
        let affected: boolean = false;
        for (const ref of item.sourceRefs) {
          if (issue.sourceId !== undefined && issue.sourceId === ref.sourceId) {
            affected = true;
            break;
          }
        }
        if (!affected && issue.sectionId !== undefined && issue.sectionId === item.targetSectionId) {
          affected = true;
        }
        if (affected && !failedIds.includes(item.id)) {
          failedIds.push(item.id);
        }
      }
    }
    for (const requiredItem of requirement.mustInclude) {
      let covered: boolean = false;
      for (const section of current.outline.sections) {
        if (section.mustInclude.includes(requiredItem)) {
          for (const item of current.evidence) {
            if (item.targetSectionId === section.id) {
              covered = true;
              break;
            }
          }
        }
        if (covered) {
          break;
        }
      }
      if (!covered) {
        failedIds.push('coverage-gap:' + requiredItem);
      }
    }
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Return JSON only with an evidence array. Re-extract only these failed evidence IDs: '
        + failedIds.join(',') + '. Do not rewrite supported evidence, outline, or draft. '
        + 'Each replacement needs an exact source excerpt and target section.\n'
        + 'sources=' + this.standardSourceText(request.sources) + '\n'
        + 'current=' + JSON.stringify(current.evidence) + '\n'
        + 'mustInclude=' + requirement.mustInclude.join(','),
    };
    const userMessage: ChatMessage = { role: 'user', content: 'Repair only contradicted, ambiguous, or uncovered evidence.' };
    const result: LlmCallResult = await this.llm.call({
      messages: [systemMessage, userMessage],
      maxTokens: this.budgetedRequestTokens(request, 2400),
      timeoutMs: KNOWLEDGE_TIMEOUT_MS,
      responseFormat: this.structuredResponseFormat(NOTE_EVIDENCE_JSON_SCHEMA, 'mindtrace_note_evidence_repair'),
    });
    const jsonText: string = new LlmGuard().extractJsonObject(result.text ?? '');
    if (jsonText.length === 0) {
      return [];
    }
    const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
    const evidenceValue: Object | undefined = parsed['evidence'];
    return evidenceValue === undefined ? [] : this.parseEvidence(evidenceValue);
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
        + 'Every evidence item must use a source excerpt and target section. '
        + 'Use stable section labels and source IDs from the input.\n'
        + 'Output schema: top-level object with exactly outline, evidence, and draft. '
        + 'outline contains schemaVersion and sections; evidence is an array of evidence items; '
        + 'draft contains schemaVersion, title, summary, subject, category, chapter, difficulty, tags, and sections.\n'
        + 'instruction=' + request.instruction + '\n'
        + 'mustInclude=' + requirement.mustInclude.join(',') + '\n'
        + 'sources:\n' + this.standardSourceText(request.sources),
    };
    const userMessage: ChatMessage = { role: 'user', content: 'Generate Outline, Evidence ledger, and Draft document.' };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    const result: LlmCallResult = await this.llm.call({
      messages: messages,
      maxTokens: this.budgetedRequestTokens(request, KNOWLEDGE_MAX_TOKENS),
      timeoutMs: KNOWLEDGE_TIMEOUT_MS,
      responseFormat: this.structuredResponseFormat(NOTE_STANDARD_JSON_SCHEMA, 'mindtrace_note_standard'),
    });
    const jsonText: string = this.selectStandardArtifactsJsonText(result.text ?? '');
    const parsed: Record<string, Object> = this.parseJsonObjectOrThrow(jsonText, 'standard artifacts');
    return this.parseStandardResult(parsed, request.sources);
  }

  private selectStandardArtifactsJsonText(raw: string): string {
    const guard: LlmGuard = new LlmGuard();
    const extraction: LlmGuardJsonExtractionResult = guard.extractJsonObjectWithDetails(raw);
    if (extraction.candidates.length === 1) {
      if (extraction.success) {
        return extraction.jsonText;
      }
      throw new Error(this.formatStandardArtifactsSelectionFailure(extraction.category, extraction, 0));
    }
    if (extraction.candidates.length === 0) {
      throw new Error(this.formatStandardArtifactsSelectionFailure(extraction.category, extraction, 0));
    }
    const eligible: LlmGuardJsonCandidate[] = [];
    for (const candidate of extraction.candidates) {
      if (candidate.parseable && candidate.object !== undefined && this.isStandardArtifactsCandidate(candidate.object)) {
        eligible.push(candidate);
      }
    }
    if (eligible.length === 1) {
      return eligible[0].text;
    }
    const category: string = eligible.length === 0 ? 'no_eligible_candidate' : 'multiple_eligible_candidates';
    throw new Error(this.formatStandardArtifactsSelectionFailure(category, extraction, eligible.length));
  }

  private isStandardArtifactsCandidate(parsed: Record<string, Object>): boolean {
    const outlineValue: Object | undefined = parsed['outline'];
    const evidenceValue: Object | undefined = parsed['evidence'];
    const draftValue: Object | undefined = parsed['draft'];
    if (outlineValue !== undefined && evidenceValue !== undefined && draftValue !== undefined) {
      return !Array.isArray(outlineValue) && typeof outlineValue === 'object'
        && Array.isArray(evidenceValue)
        && !Array.isArray(draftValue) && typeof draftValue === 'object';
    }
    if (draftValue !== undefined && !Array.isArray(draftValue) && typeof draftValue === 'object') {
      return this.isDraftArtifactsCandidate(draftValue as Record<string, Object>);
    }
    return this.isDraftArtifactsCandidate(parsed);
  }

  private isDraftArtifactsCandidate(parsed: Record<string, Object>): boolean {
    const titleValue: Object | undefined = parsed['title'];
    const sectionsValue: Object | undefined = parsed['sections'];
    return typeof titleValue === 'string' && titleValue.trim().length > 0 && Array.isArray(sectionsValue);
  }

  private formatStandardArtifactsSelectionFailure(
    category: string,
    extraction: LlmGuardJsonExtractionResult,
    eligibleCount: number,
  ): string {
    return 'standard artifacts JSON extraction failed: category=' + category
      + ', candidates=' + extraction.candidates.length.toString()
      + ', eligible=' + eligibleCount.toString()
      + ', detail=' + extraction.detail
      + ', preview=' + extraction.preview;
  }

  private async callIndependentVerifier(
    result: NoteGenerationStandardResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
    tokenBudget?: number,
  ): Promise<NoteGenerationVerification> {
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Act as an independent verifier. Return JSON only. For each evidence item classify only supported, contradicted, or ambiguous. '
        + 'Do not rewrite evidence, draft, or decide persistence.\n'
        + 'evidence=' + JSON.stringify(result.evidence) + '\n'
        + 'sources=' + this.standardSourceText(bundle) + '\n'
        + 'mustInclude=' + requirement.mustInclude.join(','),
    };
    const userMessage: ChatMessage = { role: 'user', content: 'Verify every evidence source excerpt and claim.' };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    let modelVerification: NoteGenerationVerification;
    try {
      const callResult: LlmCallResult = await this.llm.call({
        messages: messages,
        maxTokens: this.budgetedTokens(tokenBudget, 1600),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: this.structuredResponseFormat(NOTE_VERIFICATION_JSON_SCHEMA, 'mindtrace_note_verification'),
      });
      modelVerification = this.parseVerification(new LlmGuard().extractJsonObject(callResult.text ?? ''));
    } catch (e) {
      modelVerification = { status: 'ambiguous', issues: [{
        stage: 'evidence', code: 'VERIFIER_UNAVAILABLE', severity: 'hard',
        message: 'independent verifier did not return a result', repairable: true,
      }], checkedEvidenceIds: [], decisions: [] };
    }
    const local: NoteGenerationVerification = new NoteGenerationEvidenceVerifier().verify(
      result.outline,
      result.evidence,
      result.draft,
      bundle,
      requirement,
    );
    const verifierIssues: NoteGenerationIssue[] = [];
    for (const item of result.evidence) {
      let decided: boolean = false;
      for (const decision of modelVerification.decisions) {
        if (decision.evidenceId === item.id) {
          decided = true;
          break;
        }
      }
      if (!decided) {
        verifierIssues.push({
          stage: 'evidence', code: 'VERIFIER_DECISION_MISSING', severity: 'hard',
          message: 'independent verifier did not classify every evidence item', repairable: true,
        });
      }
    }
    const completeModelVerification: NoteGenerationVerification = {
      status: verifierIssues.length > 0 && modelVerification.status === 'supported' ? 'ambiguous' : modelVerification.status,
      issues: modelVerification.issues.concat(verifierIssues),
      checkedEvidenceIds: modelVerification.checkedEvidenceIds,
      decisions: modelVerification.decisions,
    };
    return this.combineVerification(completeModelVerification, local);
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
    const evidence: NoteGenerationEvidenceItem[] = [];
    for (const item of result.evidence) {
      const oldIndex: number = originalSectionIds.indexOf(item.targetSectionId);
      const targetSectionId: string = oldIndex >= 0 ? outline.sections[oldIndex].id : item.targetSectionId;
      evidence.push({
        id: item.id,
        type: item.type,
        claim: item.claim,
        sourceRefs: item.sourceRefs,
        targetSectionId: targetSectionId,
        verification: item.verification,
      });
    }
    const sections: NoteDraftSection[] = [];
    for (const section of result.draft.sections) {
      const oldIndex: number = originalSectionIds.indexOf(section.id);
      sections.push({
        id: oldIndex >= 0 ? outline.sections[oldIndex].id : section.id,
        label: section.label,
        content: section.content,
        sourceIds: section.sourceIds,
        state: section.state,
        baseHash: section.baseHash,
      });
    }
    const draft: NoteDraftDocument = {
      schemaVersion: result.draft.schemaVersion,
      title: result.draft.title,
      summary: result.draft.summary,
      subject: result.draft.subject,
      category: result.draft.category,
      chapter: result.draft.chapter,
      difficulty: result.draft.difficulty,
      tags: result.draft.tags,
      sections: sections,
      instruction: instruction,
    };
    const normalizedResult: NoteGenerationStandardResult = {
      outline: outline,
      evidence: evidence,
      draft: draft,
      verification: result.verification,
      reextractionCount: result.reextractionCount,
    };
    return normalizedResult;
  }

  private applyVerification(
    result: NoteGenerationStandardResult,
    verification: NoteGenerationVerification,
  ): NoteGenerationStandardResult {
    const evidence: NoteGenerationEvidenceItem[] = [];
    for (const item of result.evidence) {
      let status: EvidenceVerificationStatus = item.verification;
      for (const decision of verification.decisions) {
        if (decision.evidenceId === item.id) {
          status = decision.status;
          break;
        }
      }
      evidence.push({
        id: item.id,
        type: item.type,
        claim: item.claim,
        sourceRefs: item.sourceRefs,
        targetSectionId: item.targetSectionId,
        verification: status,
      });
    }
    return { outline: result.outline, evidence: evidence, draft: result.draft, verification: verification };
  }

  private mergeVerifiedEvidence(
    original: NoteGenerationStandardResult,
    repaired: NoteGenerationStandardResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
  ): NoteGenerationStandardResult {
    const repairedById: Map<string, NoteGenerationEvidenceItem> = new Map<string, NoteGenerationEvidenceItem>();
    for (const item of repaired.evidence) {
      repairedById.set(item.id, item);
    }
    const evidence: NoteGenerationEvidenceItem[] = [];
    for (const item of original.evidence) {
      if (item.verification === 'supported') {
        evidence.push(item);
      } else {
        let replacement: NoteGenerationEvidenceItem | undefined = repairedById.get(item.id);
        if (replacement === undefined) {
          for (const repairedItem of repaired.evidence) {
            if (repairedItem.targetSectionId === item.targetSectionId && repairedItem.type === item.type) {
              replacement = repairedItem;
              break;
            }
          }
        }
        evidence.push(replacement ?? item);
      }
    }
    for (const item of repaired.evidence) {
      if (original.evidence.find((oldItem: NoteGenerationEvidenceItem): boolean => oldItem.id === item.id) === undefined) {
        evidence.push(item);
      }
    }
    const frozenSectionIds: string[] = [];
    for (const item of original.evidence) {
      if (item.verification === 'supported' && !frozenSectionIds.includes(item.targetSectionId)) {
        frozenSectionIds.push(item.targetSectionId);
      }
    }
    const frozenSections: NoteDraftSection[] = [];
    for (const section of repaired.draft.sections) {
      let frozen: NoteDraftSection | undefined = undefined;
      for (const originalSection of original.draft.sections) {
        if (originalSection.id === section.id && frozenSectionIds.includes(section.id)) {
          frozen = originalSection;
          break;
        }
      }
      frozenSections.push(frozen ?? section);
    }
    const frozenDraft: NoteDraftDocument = {
      schemaVersion: repaired.draft.schemaVersion,
      title: repaired.draft.title,
      summary: repaired.draft.summary,
      subject: repaired.draft.subject,
      category: repaired.draft.category,
      chapter: repaired.draft.chapter,
      difficulty: repaired.draft.difficulty,
      tags: repaired.draft.tags,
      sections: frozenSections,
      instruction: repaired.draft.instruction,
    };
    const local: NoteGenerationVerification = new NoteGenerationEvidenceVerifier().verify(
      original.outline,
      evidence,
      frozenDraft,
      bundle,
      requirement,
    );
    const combined: NoteGenerationVerification = this.combineVerification(repaired.verification, local);
    return { outline: original.outline, evidence: evidence, draft: frozenDraft, verification: combined };
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
    return { status: status, issues: issues, checkedEvidenceIds: local.checkedEvidenceIds, decisions: decisions };
  }

  private standardSourceText(bundle: SourceBundle): string {
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + '] ' + fragment.text);
    }
    return lines.join('\n');
  }

  private parseJsonObjectOrThrow(jsonText: string, label: string): Record<string, Object> {
    if (jsonText.length === 0) {
      throw new Error(label + ' missing JSON object');
    }
    try {
      return JSON.parse(jsonText) as Record<string, Object>;
    } catch (e) {
      throw new Error(label + ' invalid JSON');
    }
  }

  private parseStandardResult(parsed: Record<string, Object>, sources: SourceBundle): NoteGenerationStandardResult {
    const outlineValue: Object | undefined = parsed['outline'];
    const evidenceValue: Object | undefined = parsed['evidence'];
    const draftValue: Object | undefined = parsed['draft'];
    if (outlineValue === undefined || evidenceValue === undefined || draftValue === undefined) {
      if (draftValue !== undefined) {
        return parseDirectStandardArtifacts(draftValue as Record<string, Object>, sources);
      }
      if (parsed['title'] !== undefined && parsed['sections'] !== undefined) {
        return parseDirectStandardArtifacts(parsed, sources);
      }
      throw new Error('standard artifacts require outline, evidence, and draft');
    }
    return {
      outline: this.parseOutline(outlineValue as Record<string, Object>),
      evidence: this.parseEvidence(evidenceValue),
      draft: this.parseDraftDocument(draftValue as Record<string, Object>),
      verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] },
    };
  }

  private parseOutline(value: Record<string, Object>): NoteGenerationOutline {
    const sectionValue: Object | undefined = value['sections'];
    const sections: NoteGenerationOutlineSection[] = [];
    if (sectionValue !== undefined && Array.isArray(sectionValue)) {
      for (const item of sectionValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        const mustInclude: string[] = this.readStringArray(record['mustInclude']);
        const sourceIds: string[] = this.readStringArray(record['sourceIds']);
        sections.push({
          id: String(record['id'] ?? ''), label: String(record['label'] ?? ''),
          order: Number(record['order'] ?? sections.length), mustInclude: mustInclude, sourceIds: sourceIds,
        });
      }
    }
    return { schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION, sections: sections };
  }

  private parseEvidence(value: Object): NoteGenerationEvidenceItem[] {
    const evidence: NoteGenerationEvidenceItem[] = [];
    if (!Array.isArray(value)) {
      return evidence;
    }
    for (const item of value as Object[]) {
      const record: Record<string, Object> = item as Record<string, Object>;
      const references: EvidenceSourceRef[] = [];
      const referenceValue: Object | undefined = record['sourceRefs'];
      if (referenceValue !== undefined && Array.isArray(referenceValue)) {
        for (const reference of referenceValue as Object[]) {
          const ref: Record<string, Object> = reference as Record<string, Object>;
          references.push({ sourceId: String(ref['sourceId'] ?? ''), excerpt: String(ref['excerpt'] ?? ''), start: Number(ref['start'] ?? 0), end: Number(ref['end'] ?? 0) });
        }
      }
      const typeValue: string = String(record['type'] ?? 'claim');
      const evidenceType: EvidenceItemType = typeValue === 'definition' || typeValue === 'formula'
        || typeValue === 'step' || typeValue === 'example' || typeValue === 'conclusion' ? typeValue : 'claim';
      const statusValue: string = String(record['verification'] ?? 'supported');
      const verification: EvidenceVerificationStatus = statusValue === 'contradicted' || statusValue === 'ambiguous' ? statusValue : 'supported';
      evidence.push({ id: String(record['id'] ?? ''), type: evidenceType, claim: String(record['claim'] ?? ''), sourceRefs: references, targetSectionId: String(record['targetSectionId'] ?? ''), verification: verification });
    }
    return evidence;
  }

  private parseVerification(jsonText: string): NoteGenerationVerification {
    if (jsonText.length === 0) {
      return { status: 'ambiguous', issues: [{ stage: 'evidence', code: 'VERIFIER_JSON_REQUIRED', severity: 'hard', message: 'verifier JSON is required', repairable: true }], checkedEvidenceIds: [], decisions: [] };
    }
    const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
    const statusValue: string = String(parsed['status'] ?? 'ambiguous');
    const status: EvidenceVerificationStatus = statusValue === 'supported' ? 'supported' : statusValue === 'contradicted' ? 'contradicted' : 'ambiguous';
    const decisions: NoteGenerationEvidenceDecision[] = [];
    const decisionValue: Object | undefined = parsed['decisions'];
    if (decisionValue !== undefined && Array.isArray(decisionValue)) {
      for (const item of decisionValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        const itemStatus: string = String(record['status'] ?? 'ambiguous');
        const decisionStatus: EvidenceVerificationStatus = itemStatus === 'supported'
          ? 'supported' : itemStatus === 'contradicted' ? 'contradicted' : 'ambiguous';
        decisions.push({ evidenceId: String(record['evidenceId'] ?? ''), status: decisionStatus });
      }
    }
    const issues: NoteGenerationIssue[] = [];
    const issueValue: Object | undefined = parsed['issues'];
    if (issueValue !== undefined && Array.isArray(issueValue)) {
      for (const item of issueValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        const severityValue: string = String(record['severity'] ?? 'hard');
        const severity: 'hard' | 'soft' = severityValue === 'soft' ? 'soft' : 'hard';
        issues.push({
          stage: String(record['stage'] ?? 'evidence'),
          code: String(record['code'] ?? 'VERIFIER_PROCESS_ISSUE'),
          severity: severity,
          message: String(record['message'] ?? 'verifier reported a process issue'),
          repairable: true,
          sourceId: record['sourceId'] === undefined ? undefined : String(record['sourceId']),
          sectionId: record['sectionId'] === undefined ? undefined : String(record['sectionId']),
        });
      }
    }
    return { status: status, issues: issues, checkedEvidenceIds: this.readStringArray(parsed['checkedEvidenceIds']), decisions: decisions };
  }

  draftToKnowledgeUnit(document: NoteDraftDocument, source: string): KnowledgeUnit {
    const fields: StructuredField[] = [];
    for (const section of document.sections) {
      fields.push({ key: section.id, label: section.label, value: section.content });
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
    return this.toKnowledgeUnit(ext, Date.now());
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

  private parseDraftDocument(parsed: Record<string, Object>): NoteDraftDocument {
    const sectionsValue: Object | undefined = parsed['sections'];
    if (sectionsValue === undefined || !Array.isArray(sectionsValue)) {
      throw new Error('light draft sections missing');
    }
    const sections: NoteDraftSection[] = [];
    const rawSections: Object[] = sectionsValue as Object[];
    for (const rawSection of rawSections) {
      const record: Record<string, Object> = rawSection as Record<string, Object>;
      const sourceIds: string[] = this.readStringArray(record['sourceIds']);
      sections.push({
        id: String(record['id'] ?? ''),
        label: String(record['label'] ?? ''),
        content: String(record['content'] ?? ''),
        sourceIds: sourceIds,
        state: record['state'] === 'locked' ? 'locked' : 'generated',
        baseHash: String(record['baseHash'] ?? ''),
      });
    }
    return {
      schemaVersion: String(parsed['schemaVersion'] ?? ''),
      title: String(parsed['title'] ?? ''),
      summary: String(parsed['summary'] ?? ''),
      subject: String(parsed['subject'] ?? ''),
      category: String(parsed['category'] ?? ''),
      chapter: String(parsed['chapter'] ?? ''),
      difficulty: Number(parsed['difficulty'] ?? 0),
      tags: this.readStringArray(parsed['tags']),
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

  private toKnowledgeUnit(ext: KnowledgeUnitExt, createdAt: number): KnowledgeUnit {
    const summary: string = this.summaryFromFields(ext);
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
    const summary: string = this.contentExcerptBuilder.buildPlainSummary(source, 220);
    if (summary.length > 0) {
      return summary;
    }
    return ext.title.trim();
  }

  private toDifficultyLevel(value: number): DifficultyLevel {
    if (value <= 1) { return DifficultyLevel.EASY; }
    if (value === 2 || value === 3) { return DifficultyLevel.MEDIUM; }
    if (value === 4) { return DifficultyLevel.HARD; }
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
      }, (json: Record<string, Object>): LlmGuardValidationResult => this.validateAiJson(json));
      console.info('[KnowledgeModel] callAi response received, len=' + guarded.raw.length.toString()
        + ', attempts=' + guarded.attempts.toString());
    } catch (llmErr) {
      console.error('[KnowledgeModel] callAi LLM error: ' + (llmErr as Error).message);
      throw new Error('LLM 调用失败: ' + (llmErr as Error).message);
    }

    if (!guarded.raw || guarded.raw.length === 0) {
      console.error('[KnowledgeModel] callAi empty content after 200 OK');
      throw new Error('AI 返回为空:content 为空');
    }

    const parsed: Record<string, Object> = guarded.json;

    const aiRaw: AiRawResponse = {
      category: this.normalizeCategory(String(parsed['category'] ?? ''), typeHint),
      subject: this.normalizeSubject(String(parsed['subject'] ?? ''), subjectHint),
      chapter: this.normalizeChapter(String(parsed['chapter'] ?? '')),
      title: this.normalizeTitle(String(parsed['title'] ?? ''), userText),
      tags: this.normalizeStringArray(parsed['tags']),
      difficulty: this.normalizeScore(Number(parsed['difficulty'] ?? 3)),
      importance: this.normalizeScore(Number(parsed['importance'] ?? 3)),
      fields: this.normalizeFields(parsed['fields']),
    };

    return aiRaw;
  }

  private validateAiJson(parsed: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    const categoryValue: Object | undefined = parsed['category'];
    const categoryText: string = typeof categoryValue === 'string' ? categoryValue : '';
    if (categoryText.length === 0 || !isKnownNoteType(normalizeNoteType(categoryText))) {
      issues.push('category must be one of: ' + NOTE_TYPE_KEYS.join('/'));
    }
    if (typeof parsed['subject'] !== 'string') {
      issues.push('subject must be a string');
    }
    const titleValue: Object | undefined = parsed['title'];
    if (typeof titleValue !== 'string' || titleValue.trim().length === 0) {
      issues.push('title must be a non-empty string');
    } else if (this.contentProtocol.hasFormulaSyntax(titleValue)) {
      issues.push('title must not contain a formula');
    }
    const tagsValue: Object | undefined = parsed['tags'];
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
    if (!this.isScoreValue(parsed['difficulty'])) {
      issues.push('difficulty must be a number from 1 to 5');
    }
    if (!this.isScoreValue(parsed['importance'])) {
      issues.push('importance must be a number from 1 to 5');
    }
    const fieldsValue: Object | undefined = parsed['fields'];
    if (!Array.isArray(fieldsValue)) {
      issues.push('fields must be an array');
    } else {
      const fields: Object[] = fieldsValue as Object[];
      if (fields.length === 0) {
        issues.push('fields must not be empty');
      }
      for (const field of fields) {
        const record: Record<string, Object> = field as Record<string, Object>;
        if (typeof record['key'] !== 'string' || String(record['key']).trim().length === 0) {
          issues.push('each field.key must be a non-empty string');
          break;
        }
        if (typeof record['label'] !== 'string' || String(record['label']).trim().length === 0) {
          issues.push('each field.label must be a non-empty string');
          break;
        }
        if (this.contentProtocol.hasFormulaSyntax(String(record['key']))
          || this.contentProtocol.hasFormulaSyntax(String(record['label']))) {
          issues.push('field.key and field.label must not contain formulas');
          break;
        }
        if (typeof record['value'] !== 'string' || String(record['value']).trim().length === 0) {
          issues.push('each field.value must be a non-empty string');
          break;
        }
        const contentResult: ContentValidationResult = this.contentProtocol.validateNoteMarkdown(String(record['value']));
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

  private isScoreValue(value: Object | undefined): boolean {
    if (typeof value !== 'number' && typeof value !== 'string') {
      return false;
    }
    const score: number = Number(value);
    return !Number.isNaN(score) && score >= 1 && score <= 5;
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
    for (const field of ext.fields) {
      const label: string = field.label.trim().length > 0 ? field.label.trim() : field.key.trim();
      const valueResult: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(field.value);
      const value: string = valueResult.normalizedText.trim();
      if (value.length > 0) {
        sections.push('## ' + label + '\n' + value);
      }
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
      const key: string = String(record['key'] ?? '').trim();
      const label: string = String(record['label'] ?? '').trim();
      const fieldValue: string = String(record['value'] ?? '').trim();
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
