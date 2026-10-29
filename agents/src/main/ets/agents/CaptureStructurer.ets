/**
 * CaptureStructurer.ets — Capture 结构化业务闭包
 *
 * 路径: agents/src/main/ets/agents/CaptureStructurer.ets
 * 职责: 承载分类 hint、classic LLM 结构化、响应校验归一化和 Capture / 草稿的 KnowledgeUnit 投影。
 * 依赖: common/src/main/ets/Index、TypeClassifier、PromptBuilder、GenerationJsonCaller
 *
 * 数据流:
 *   OCR 文本 → resolveClassificationHint → callAi → normalize* → KnowledgeUnit
 *
 * 第一阶段只做行为保持的文件提取；TruthCheck 仍由 Capture workflow Node 负责。
 */
import type { KnowledgeCategory } from '../models/KnowledgeCategory';
import { KnowledgeUnitExt, createUnitExt, StructuredField, AiRawResponse } from '../models/KnowledgeUnitExt';
import {
  normalizeSubjectName,
  resolveSubjectName,
  sanitizeNoteTitle,
  TitleSanitization,
  SubjectNormalization,
  SubjectResolution,
} from './KnowledgeTaxonomy';
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
  normalizeNoteType,
  NOTE_TYPE_KEYS,
  ReviewStatus,
  normalizeDraftSectionLabel,
  normalizeDraftDifficulty,
} from 'common/src/main/ets/Index';
import type {
  CaptureProvenance,
  ChatMessage,
  ClassificationResult,
  ContentValidationResult,
  KnowledgeUnit,
  LlmGuardJsonResult,
  LlmGuardValidationResult,
  LlmCaller,
  NoteDraftDocument,
  CancellationToken,
} from 'common/src/main/ets/Index';

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

export class CaptureStructurer {
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

  async structure(
    ocrText: string,
    type?: string,
    subject?: string,
    chapter: string = '',
    source: string = 'camera_capture',
    provenance?: CaptureProvenance,
    knownSubjects: string[] = [],
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
        knownSubjects,
      );
    } catch (aiErr) {
      const errMsg: string = (aiErr as Error).message ?? String(aiErr);
      console.warn('[KnowledgeModel] AI structure failed: ' + errMsg);
      if (aiErr instanceof LlmError) {
        throw new LlmError('AI 结构化失败: ' + errMsg, aiErr.kind);
      }
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

    const unit: KnowledgeUnit = this.toKnowledgeUnit(ext, startTime, '', provenance);
    console.info('[KnowledgeModel] structure done: noteId=' + unit.id
      + ' category=' + ext.type + ' aiFields=' + aiRaw.fields.length.toString());
    return unit;
  }

  async structureWithClassification(
    ocrText: string,
    classification: ClassificationResult,
    source: string = 'camera_capture',
    provenance?: CaptureProvenance,
    knownSubjects: string[] = [],
  ): Promise<KnowledgeUnit> {
    return await this.structure(
      ocrText,
      classification.type,
      classification.subject,
      classification.chapter ?? '',
      source,
      provenance,
      knownSubjects,
    );
  }

  draftToKnowledgeUnit(
    document: NoteDraftDocument,
    source: string,
    provenance?: CaptureProvenance,
  ): KnowledgeUnit {
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
    return this.toKnowledgeUnit(ext, Date.now(), document.summary, provenance);
  }

  private toKnowledgeUnit(
    ext: KnowledgeUnitExt,
    createdAt: number,
    summaryOverride: string = '',
    provenance?: CaptureProvenance,
  ): KnowledgeUnit {
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
      // 溯源字段: 没有图片/OCR 证据时保持空字符串/0；0 表示 OCR 未提供置信度，不是估算值。
      sourceImageId: provenance !== undefined ? provenance.sourceImageId : '',
      sourceRegion: provenance !== undefined ? provenance.sourceRegion : '',
      ocrConfidence: provenance !== undefined ? provenance.ocrConfidence : 0,
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
    knownSubjects: string[] = [],
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
    const prompt: string = this.promptBuilder.buildPrompt(ocrText, knownSubjects) + hint;

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

    // 先清洗标题，再决定 title 用哪个：复核标记被剥掉时说明模型自己也不确定，
    // 这个事实要挂到 AiRawResponse 上，最后由 needsUserInput 告诉用户「标题待确认」。
    const titleSource: string = String(this.readRecordValue(parsed, 'title') ?? '');
    const titleClean: TitleSanitization = sanitizeNoteTitle(titleSource);

    const aiRaw: AiRawResponse = {
      category: this.normalizeCategory(String(this.readRecordValue(parsed, 'category') ?? ''), typeHint),
      subject: this.normalizeSubject(String(this.readRecordValue(parsed, 'subject') ?? ''), subjectHint, knownSubjects),
      chapter: this.normalizeChapter(String(this.readRecordValue(parsed, 'chapter') ?? '')),
      title: this.normalizeTitle(titleClean.title, userText),
      titleNeedsReview: titleClean.stripped.length > 0,
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
    // 标题里原本有「（OCR 信息不完整）」这类标记 → 标记被剥掉了，但不确定性要留给用户看。
    if (aiRaw.category === '证明题' || aiRaw.category === '计算题' || aiRaw.titleNeedsReview === true) {
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

  private normalizeSubject(value: string, fallback?: string, knownSubjects: string[] = []): string {
    // 学科裁决：内置学科 > 库里已有学科 > 才允许新建。
    // 提示词里已经把已有学科列成封闭词表，这里再兜一次，防止模型无视约束。
    const resolution: SubjectResolution = resolveSubjectName(value, knownSubjects);
    const normalized: SubjectNormalization = normalizeSubjectName(resolution.subject, fallback !== undefined ? fallback : '');
    const subject: string = normalized.subject.trim();
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
    // 入参已经过 sanitizeNoteTitle；这里只兜「空标题」和「占位值」两种退化。
    const title: string = value.trim();
    if (title.length > 0 && title !== '未知' && title !== 'null' && title !== 'undefined') {
      return title;
    }
    const firstLine: string = sanitizeNoteTitle(fallbackText.split('\n')[0]).title;
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
  private readRecordValue(parsed: Record<string, Object>, key: string): Object | undefined {
    const entries: Array<[string, Object]> = Object.entries(parsed);
    for (const entry of entries) {
      if (entry[0] === key) return entry[1];
    }
    return undefined;
  }
}

