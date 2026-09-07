// MindTrace - KnowledgeModel
// ============================================================================
//  agents/KnowledgeModel.ets — 知识结构化编排 agent
//  ----------------------------------------------------------------------------
//  路径: agents/src/main/ets/agents/KnowledgeModel.ets
//  职责: structure() / structureWithClassification() 编排 — 组装提示词 (PromptBuilder)、
//        调用 LLM (callAi: LlmGuard JSON 校验重试, 即 ADR-0012 ToolLoop 的预留 seam)、
//        归一化字段、合并分类 hint、产出主线 KnowledgeUnit
//  依赖: common (LlmGuard / ContentProtocol / NOTE_TYPE_KEYS / models) ·
//        TypeClassifier · PromptBuilder · TruthCheckService
//  数据流: OCR 文本 → resolveClassificationHint → callAi (prompt + JSON_ONLY_RULES)
//          → validateAiJson → normalize* → toKnowledgeUnit
//          (含 TruthCheckService.check 真值标记) → KnowledgeUnit
//  沿革: spec 015 (2026-09-06) 原地拆分 — 提示词/真值检查/常量拆为三个协作服务,
//        本类依用户命名裁决保留 KnowledgeModel 之名, 878 行 god class → 554 行
//  ============================================================================
import type { KnowledgeCategory } from '../models/KnowledgeCategory';
import { MvpTruthCheckResult } from '../models/TruthCheckResult';
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
  normalizeNoteType,
  NOTE_TYPE_KEYS,
  ReviewStatus,
} from 'common';
import type {
  ChatMessage,
  ClassificationResult,
  ContentValidationResult,
  KnowledgeUnit,
  LlmGuardJsonResult,
  LlmGuardValidationResult,
} from 'common';
import { TypeClassifier } from './TypeClassifier';
import { TruthCheckService } from './TruthCheckService';
import { PromptBuilder } from './PromptBuilder';

const KNOWLEDGE_INPUT_LIMIT: number = 12000;
const KNOWLEDGE_MAX_TOKENS: number = 12000;
const KNOWLEDGE_TIMEOUT_MS: number = 300000;
const KNOWLEDGE_CLASSIFY_HINT_TIMEOUT_MS: number = 10000;
const KNOWLEDGE_HINT_CONFIDENCE_MIN: number = 0.55;
const KNOWLEDGE_FALLBACK_CATEGORY: KnowledgeCategory = '概念';
const KNOWLEDGE_FALLBACK_SUBJECT: string = '其它';

export class KnowledgeModel {
  private contentProtocol: ContentProtocol = new ContentProtocol();
  private contentExcerptBuilder: ContentExcerptBuilder = new ContentExcerptBuilder();
  private truthCheckService: TruthCheckService = new TruthCheckService();
  private promptBuilder: PromptBuilder = new PromptBuilder();

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

    const truthResult: MvpTruthCheckResult = this.truthCheckService.check(ocrText);
    ext.truthFlag = truthResult.truthFlag;
    if (!truthResult.truthFlag) {
      for (const item of truthResult.details) {
        if (!item.passed) {
          for (const issue of item.issues) {
            ext.truthDetails.push('[' + item.checkName + '] ' + issue);
          }
        }
      }
    }
    this.markNeedsUserInput(ext, aiRaw);

    const unit: KnowledgeUnit = this.toKnowledgeUnit(ext, startTime);
    console.info('[KnowledgeModel] structure done: id=' + unit.id
      + ' title=' + unit.title
      + ' category=' + ext.type
      + ' tags=' + JSON.stringify(unit.tags)
      + ' contentLen=' + unit.content.length.toString()
      + ' summary=' + unit.summary
      + ' aiFields=' + aiRaw.fields.length.toString());
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
