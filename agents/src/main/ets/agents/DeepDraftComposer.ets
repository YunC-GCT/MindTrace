/**
 * DeepDraftComposer.ets — deep 顺序生成、ledger 与来源证据闭包
 *
 * 路径: agents/src/main/ets/agents/DeepDraftComposer.ets
 * 职责: deep 顺序生成、ledger 与来源证据闭包，保持现有生成行为。
 * 依赖: common、GenerationJsonCaller、NoteDraftVerifier、GenerationDraftSupport
 * 数据流: KnowledgeModel / composer → 本 Module → 生成或验证结果
 */
import {
  ContentProtocol,
  LATEX_GENERATION_RULES,
  LlmClient,
  normalizeDraftSummary,
  segmentSourceBundle,
  buildDeepOutline,
  sourceFingerprint,
  validateSourceBundle,
  NOTE_DRAFT_SCHEMA_VERSION,
} from 'common/src/main/ets/Index';
import type {
  ChatMessage,
  LlmGuardValidationResult,
  LlmCaller,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationIssue,
  NoteGenerationRequest,
  NoteGenerationOutline,
  NoteGenerationOutlineSection,
  NoteGenerationEvidenceItem,
  EvidenceSourceRef,
  NoteGenerationStandardResult,
  NoteGenerationDeepResult,
  NoteGenerationSegment,
  NoteGenerationLedger,
  NoteGenerationVerification,
  NoteGenerationProgressSink,
  SourceBundle,
  NoteGenerationRequirement,
  SourceFragment,
  CancellationToken,
} from 'common/src/main/ets/Index';
import {
  NOTE_DRAFT_JSON_SCHEMA,
  normalizeDeepSectionDraft,
  validateDraftDocument,
  validateDraftShape,
} from 'common/src/main/ets/Index';
import { GenerationJsonCaller } from './GenerationJsonCaller';
import { KNOWLEDGE_TIMEOUT_MS } from './PromptBuilder';
import {
  budgetedRequestTokens,
  structuredResponseFormat,
  parseDraftDocument,
  emitProgress,
  NOTE_MATH_REASONING_RULES,
} from './GenerationDraftSupport';
import { NoteDraftVerifier } from './NoteDraftVerifier';

const DEEP_LEDGER_VALUE_MAX_CHARS: number = 160;

export class DeepDraftComposer {
  private readonly jsonCaller: GenerationJsonCaller;
  private readonly contentProtocol: ContentProtocol = new ContentProtocol();
  private readonly verifier: NoteDraftVerifier;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    const client: LlmCaller = llm ?? new LlmClient();
    this.jsonCaller = new GenerationJsonCaller(client, undefined, cancellationToken);
    this.verifier = new NoteDraftVerifier(client, cancellationToken);
  }

  async compose(
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
      emitProgress(progressSink, {
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
    emitProgress(progressSink, {
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
    const verification: NoteGenerationVerification = await this.verifier.verify(
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
        maxTokens: budgetedRequestTokens(request, 4800),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: structuredResponseFormat(),
      },
      (json: Record<string, Object>): LlmGuardValidationResult => {
        const issues: string[] = validateDraftShape(json);
        return { ok: issues.length === 0, issues: issues };
      },
      (json: Record<string, Object>): string[] => {
        // P0-4 (2026-09-19): 先归一化再校验 — LLM 原始输出系统性缺 sourceIds /
        // 学科级 category / \(...\) 定界符, 直接判 hard 导致 3 次重试全灭;
        // 归一化后校验器只拦截真值类失败 (空 content / 不可渲染 / 伪造引用)
        const document: NoteDraftDocument = normalizeDeepSectionDraft(parseDraftDocument(json), outlineSection);
        const issues: NoteGenerationIssue[] = validateDraftDocument(document, outlineSection.sourceIds, true);
        const codes: string[] = [];
        for (const issue of issues) {
          const detail: string = issue.message.trim().length > 0 ? ': ' + issue.message : '';
          codes.push(issue.code + detail);
        }
        return codes;
      },
    );
    return normalizeDeepSectionDraft(parseDraftDocument(parsed), outlineSection);
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
}
