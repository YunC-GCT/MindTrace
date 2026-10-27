/**
 * DraftComposer.ets — light/standard 草稿生成
 *
 * 路径: agents/src/main/ets/agents/DraftComposer.ets
 * 职责: light/standard 草稿生成，保持现有生成行为。
 * 依赖: common、GenerationJsonCaller、NoteDraftVerifier、GenerationDraftSupport
 * 数据流: KnowledgeModel → light/standard 生成 → 草稿与只读验证结果
 */
import {
  ContentProtocol,
  LATEX_GENERATION_RULES,
  LlmGuard,
  LlmClient,
  normalizeOutline,
  normalizeDraftCategory,
  normalizeDraftSummary,
  normalizeLightDraft,
  normalizeDraftSectionLabel,
  normalizeDraftDifficulty,
  buildPipelineEvidence,
  validateSourceBundle,
  NOTE_OUTLINE_SCHEMA_VERSION,
  NOTE_DRAFT_SCHEMA_VERSION,
  NOTE_STANDARD_JSON_SCHEMA,
} from 'common/src/main/ets/Index';
import type {
  ChatMessage,
  ContentValidationResult,
  LlmGuardJsonExtractionResult,
  LlmGuardJsonCandidate,
  LlmGuardValidationResult,
  LlmCaller,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationIssue,
  NoteGenerationRequest,
  NoteGenerationOutline,
  NoteGenerationOutlineSection,
  NoteGenerationEvidenceCandidate,
  EvidenceCandidateSourceRef,
  NoteGenerationEvidenceItem,
  EvidenceItemType,
  NoteGenerationStandardResult,
  NoteGenerationVerification,
  NoteGenerationProgressSink,
  SourceBundle,
  NoteGenerationRequirement,
  CancellationToken,
} from 'common/src/main/ets/Index';
import {
  NOTE_DRAFT_JSON_SCHEMA,
  normalizeEvidenceItems,
  parseDirectStandardArtifacts,
  validateDraftDocument,
  validateDraftShape,
} from 'common/src/main/ets/Index';
import { GenerationJsonCaller } from './GenerationJsonCaller';
import { KNOWLEDGE_MAX_TOKENS, KNOWLEDGE_TIMEOUT_MS } from './PromptBuilder';
import {
  readRecordValue,
  readRecordValueFromEntries,
  readStringArray,
  budgetedRequestTokens,
  structuredResponseFormat,
  parseDraftDocument,
  emitProgress,
  standardSourceText,
  NOTE_MATH_REASONING_RULES,
} from './GenerationDraftSupport';
import { NoteDraftVerifier } from './NoteDraftVerifier';

export class DraftComposer {
  private readonly jsonCaller: GenerationJsonCaller;
  private readonly contentProtocol: ContentProtocol = new ContentProtocol();
  private readonly verifier: NoteDraftVerifier;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    const client: LlmCaller = llm ?? new LlmClient();
    this.jsonCaller = new GenerationJsonCaller(client, undefined, cancellationToken);
    this.verifier = new NoteDraftVerifier(client, cancellationToken);
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
    const responseFormat = structuredResponseFormat();
    const parsed: Record<string, Object> = await this.jsonCaller.callJson(
      messages,
      {
        label: 'light draft',
        maxTokens: budgetedRequestTokens(request, 1200),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: responseFormat,
      },
      (json: Record<string, Object>): LlmGuardValidationResult => {
        const issues: string[] = validateDraftShape(json);
        return { ok: issues.length === 0, issues: issues };
      },
      (json: Record<string, Object>): string[] => {
        const document: NoteDraftDocument = normalizeLightDraft(parseDraftDocument(json), request.sources);
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
    return normalizeLightDraft(parseDraftDocument(parsed), request.sources);
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
    emitProgress(progressSink, {
      phase: 'verify',
      state: 'running',
      activity: 'check_accuracy',
    });
    const verification: NoteGenerationVerification = await this.verifier.verify(
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
        + 'sources:\n' + standardSourceText(request.sources),
    };
    const userMessage: ChatMessage = { role: 'user', content: 'Generate Outline, Evidence ledger, and Draft document.' };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    const parsed: Record<string, Object> = await this.jsonCaller.callJson(
      messages,
      {
        label: 'standard artifacts',
        maxTokens: budgetedRequestTokens(request, KNOWLEDGE_MAX_TOKENS),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: structuredResponseFormat(NOTE_STANDARD_JSON_SCHEMA, 'mindtrace_note_standard'),
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
    const outlineValue: Object | undefined = readRecordValue(parsed, 'outline');
    const evidenceValue: Object | undefined = readRecordValue(parsed, 'evidence');
    const draftValue: Object | undefined = readRecordValue(parsed, 'draft');
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
    const titleValue: Object | undefined = readRecordValue(parsed, 'title');
    const sectionsValue: Object | undefined = readRecordValue(parsed, 'sections');
    return typeof titleValue === 'string' && titleValue.trim().length > 0 && Array.isArray(sectionsValue);
  }

  private findNestedStandardArtifacts(parsed: Record<string, Object>): Record<string, Object> | undefined {
    const preferredKeys: string[] = ['result', 'data', 'note', 'document', 'draftDocument', 'answer', 'content', 'output'];
    const entries: Array<[string, Object]> = Object.entries(parsed) as Array<[string, Object]>;
    for (const key of preferredKeys) {
      const nested: Record<string, Object> | undefined = this.readNestedStandardArtifacts(
        readRecordValueFromEntries(entries, key),
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

  private parseStandardResult(parsed: Record<string, Object>, sources: SourceBundle): NoteGenerationStandardResult {
    const nested: Record<string, Object> | undefined = this.findNestedStandardArtifacts(parsed);
    const parsedDraft: Object | undefined = readRecordValue(parsed, 'draft');
    const parsedOutline: Object | undefined = readRecordValue(parsed, 'outline');
    if (nested !== undefined && !this.isDraftArtifactsCandidate(parsed)
      && parsedDraft === undefined && parsedOutline === undefined) {
      return this.parseStandardResult(nested, sources);
    }
    const outlineValue: Object | undefined = parsedOutline;
    const evidenceValue: Object | undefined = readRecordValue(parsed, 'evidence');
    const draftValue: Object | undefined = parsedDraft;
    if (outlineValue !== undefined && draftValue !== undefined && evidenceValue === undefined) {
      return {
        outline: this.parseOutline(outlineValue as Record<string, Object>),
        evidence: [],
        draft: parseDraftDocument(draftValue as Record<string, Object>),
        verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] },
      };
    }
    if (outlineValue === undefined || evidenceValue === undefined || draftValue === undefined) {
      if (draftValue !== undefined) {
        return parseDirectStandardArtifacts(draftValue as Record<string, Object>, sources);
      }
      if (readRecordValue(parsed, 'title') !== undefined
        && readRecordValue(parsed, 'sections') !== undefined) {
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
      draft: parseDraftDocument(draftValue as Record<string, Object>),
      verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] },
    };
  }

  private parseOutline(value: Record<string, Object>): NoteGenerationOutline {
    const sectionValue: Object | undefined = readRecordValue(value, 'sections');
    const sections: NoteGenerationOutlineSection[] = [];
    if (sectionValue !== undefined && Array.isArray(sectionValue)) {
      for (const item of sectionValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        const mustInclude: string[] = readStringArray(readRecordValue(record, 'mustInclude'));
        const sourceIds: string[] = readStringArray(readRecordValue(record, 'sourceIds'));
        sections.push({
          id: String(readRecordValue(record, 'id') ?? ''),
          label: String(readRecordValue(record, 'label') ?? ''),
          order: Number(readRecordValue(record, 'order') ?? sections.length),
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
      const referenceValue: Object | undefined = readRecordValue(record, 'sourceRefs');
      if (referenceValue !== undefined && Array.isArray(referenceValue)) {
        for (const reference of referenceValue as Object[]) {
          const ref: Record<string, Object> = reference as Record<string, Object>;
          references.push({
            sourceId: String(readRecordValue(ref, 'sourceId') ?? ''),
            excerpt: String(readRecordValue(ref, 'excerpt') ?? ''),
          });
        }
      }
      const typeValue: string = String(readRecordValue(record, 'type') ?? 'claim');
      const evidenceType: EvidenceItemType = typeValue === 'definition' || typeValue === 'formula'
        || typeValue === 'step' || typeValue === 'example' || typeValue === 'conclusion' ? typeValue : 'claim';
      evidence.push({
        type: evidenceType,
        claim: String(readRecordValue(record, 'claim') ?? ''),
        sourceRefs: references,
        targetSectionId: String(readRecordValue(record, 'targetSectionId') ?? ''),
      });
    }
    return evidence;
  }

  private lightSourceText(request: NoteGenerationRequest): string {
    const lines: string[] = [];
    for (const fragment of request.sources.fragments) {
      lines.push('[source:' + fragment.id + '] ' + fragment.text);
    }
    return lines.join('\n');
  }
}

