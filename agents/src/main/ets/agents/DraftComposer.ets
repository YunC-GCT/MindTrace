/**
 * DraftComposer.ets — light/standard 草稿生成业务闭包
 *
 * 路径: agents/src/main/ets/agents/DraftComposer.ets
 * 职责: 生成并验证 light/standard 草稿，同时承载共享的 deep/incremental 生成辅助逻辑。
 * 依赖: common/src/main/ets/Index、GenerationJsonCaller
 *
 * 数据流:
 *   NoteGenerationRequest → source/schema/domain gates → draft/evidence/verifier result
 *
 * 生成入口仍由 KnowledgeModel facade 暴露，保持外部 Interface 不变。
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

/** deep ledger 单条 value 上限 (字符): 防止共享 ledger 随节数膨胀推高 prompt (P0-5) */
const DEEP_LEDGER_VALUE_MAX_CHARS: number = 160;

const NOTE_MATH_REASONING_RULES: string =
  'Distinguish source givens, derived conclusions, and unconfirmed conditions. '
  + 'Solve the supplied problem and explain checkable derivation steps; do not merely transcribe it. '
  + 'You may add relevant definitions and standard theorems, stating their applicability and linking derivations to the source givens. '
  + 'Never present a derived result or an invented example as a verbatim source quotation. '
  + 'Do not silently guess unclear symbols, domains, orientations or other key conditions. '
  + 'If a missing condition changes the answer, state the precise question for the user and keep any resulting answer explicitly conditional. '
  + 'Before returning, check algebra, signs and consistent normal/boundary orientation; for extrema compare interior and boundary candidates; '
  + 'verify auxiliary-function derivatives and substitutions. Correct source errors only with an explicit explanation, preserving the original quotation. '
  + 'Classification confidence is model metadata, not OCR accuracy or mathematical truth.\n';

export class DraftComposer {
  private contentProtocol: ContentProtocol = new ContentProtocol();
  private jsonCaller: GenerationJsonCaller;
  private readonly cancellationToken?: CancellationToken;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    const client: LlmCaller = llm ?? new LlmClient();
    this.cancellationToken = cancellationToken;
    this.jsonCaller = new GenerationJsonCaller(client, undefined, cancellationToken);
  }

  async structureLightDraft(request: NoteGenerationRequest): Promise<NoteDraftDocument> {
    const sourceIssues: NoteGenerationIssue[] = validateSourceBundle(request.sources);
    if (sourceIssues.length > 0) {
      throw new Error('light source gate failed: ' + sourceIssues[0].code);
    }
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
        + NOTE_MATH_REASONING_RULES
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
        + NOTE_MATH_REASONING_RULES
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
        + 'Distinguish literal source quotations from mathematical derivations and explicitly labeled supplementary knowledge. '
        + 'Do not reject a valid derivation merely because its conclusion is not verbatim in the source. '
        + 'Check its premises, theorem applicability and intermediate steps instead. Evidence excerpts must still be verbatim and support their assertions. '
        + 'Classification confidence (including legacy fields labeled 置信度) is model metadata, not OCR accuracy or mathematical truth; '
        + 'confidence metadata alone is not grounds for a hard issue or an ambiguous evidence status. '
        + 'Hard issues include demonstrated mathematical errors, unsupported critical assumptions, misleading quotations, '
        + 'and missing conditions that prevent establishing a required answer. An explicitly conditional answer or request for clarification '
        + 'is not itself a false claim; verify that it does not hide an unconditional conclusion. '
        + 'Check normal/boundary orientation and signs, boundary versus interior extrema, and auxiliary-function calculations. '
        + 'Treat wording, optional elaboration and presentation preferences as soft issues. '
        + 'Use top-level supported when only soft issues remain; contradicted for established errors; ambiguous for unresolved critical conditions. '
        + 'Give each issue a Chinese message identifying the exact formula or claim, why it fails, and what needs correction or user confirmation; '
        + 'include sectionId and sourceId when identifiable. Do not emit generic LOGIC_GAP or GROUNDING_GAP without a concrete missing step or premise.\n'
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

}

