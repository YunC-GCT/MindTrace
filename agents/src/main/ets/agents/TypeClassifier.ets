import {
  isKnownNoteType,
  JSON_ONLY_RULES,
  LlmGuard,
  normalizeNoteType,
  NOTE_TYPE_KEYS,
} from 'common';
import type {
  ChatMessage,
  ClassificationResult,
  DispatchPayload,
  LlmGuardJsonResult,
  LlmGuardValidationResult,
  NoteCategory,
} from 'common';
import { OcrTool } from '../tools/OcrTool';

const CLASSIFY_TEXT_LIMIT: number = 6000;
const CLASSIFY_MAX_TOKENS: number = 800;
const CLASSIFY_TIMEOUT_MS: number = 120000;
const FALLBACK_SUBJECT: string = '其它';
const FALLBACK_CATEGORY: NoteCategory = '概念';

interface CategoryRule {
  category: NoteCategory;
  keywords: string[];
}

interface SubjectRule {
  subject: string;
  keywords: string[];
}

interface ParsedClassification {
  category: NoteCategory;
  subject: string;
  chapter: string;
  confidence: number;
}

const CATEGORY_RULES: CategoryRule[] = [
  { category: '证明题', keywords: ['证明', '求证', '证得', '推证', '反证', '归纳法'] },
  { category: '计算题', keywords: ['计算', '求解', '求值', '化简', '解方程', '求极限', '积分', '导数'] },
  { category: '定理', keywords: ['定理', '引理', '命题', '推论', '法则'] },
  { category: '公式', keywords: ['公式', '恒等式', '表达式', '展开式', '等价形式'] },
  { category: '概念', keywords: ['定义', '概念', '性质', '含义', '是什么'] },
];

const SUBJECT_RULES: SubjectRule[] = [
  { subject: '数学分析', keywords: ['极限', '连续', '导数', '微分', '积分', '级数', '函数列', '中值定理'] },
  { subject: '线性代数', keywords: ['矩阵', '行列式', '向量组', '线性相关', '特征值', '特征向量', '线性空间'] },
  { subject: '解析几何', keywords: ['直线', '平面', '圆锥曲线', '椭圆', '双曲线', '抛物线', '空间坐标'] },
  { subject: '概率论', keywords: ['概率', '随机变量', '分布', '期望', '方差', '协方差', '独立事件'] },
  { subject: '初中数学', keywords: ['二次函数', '一次函数', '勾股定理', '相似三角形', '圆周角'] },
  { subject: '高中数学', keywords: ['数列', '立体几何', '三角函数', '导数应用', '圆锥曲线'] },
];

export interface TypeClassifierTextResult {
  // 原始输入文本：text payload 原文，或图片/文件 OCR 原文，已合并 userText。
  rawText: string;
  // 预处理后的文本：供 UI 展示、KnowledgeModel 结构化和后续分类逻辑使用。
  text: string;
  // 输入来源，用于调用方判断这次是否真的走了 OCR。
  kind: 'text' | 'image' | 'file';
}

/**
 * TypeClassifier 负责文本暴露 + 轻量分类。
 *
 * 推荐用法：
 *   const classifier = new TypeClassifier();
 *   const result = await classifier.recognizeText(payload, context);
 *   const textForDownstream = result.text;
 *
 * 兼容旧链路：
 *   const classification = await classifier.classify(payload, context);
 *   const textForDownstream = classification.ocrText ?? '';
 *
 * 返回约定：
 *   - recognizeText().rawText: OCR/输入原文，便于排查识别质量。
 *   - recognizeText().text: 轻量预处理后的文本，便于下游直接使用。
 *   - classify(): LLM 优先识别五类 + 学科；失败时规则兜底，不阻断 Dispatcher。
 */
export class TypeClassifier {
  async recognizeText(payload: DispatchPayload, context?: Context): Promise<TypeClassifierTextResult> {
    const rawText: string = await this.extractText(payload, context);
    return {
      rawText: rawText,
      text: this.preprocessText(rawText),
      kind: payload.kind,
    };
  }

  async classify(payload: DispatchPayload, context?: Context): Promise<ClassificationResult> {
    const result: TypeClassifierTextResult = await this.recognizeText(payload, context);
    return await this.classifyPreparedText(result.text, CLASSIFY_TIMEOUT_MS);
  }

  async classifyText(text: string, timeoutMs: number = CLASSIFY_TIMEOUT_MS): Promise<ClassificationResult> {
    return await this.classifyPreparedText(this.preprocessText(text), timeoutMs);
  }

  private async classifyPreparedText(text: string, timeoutMs: number): Promise<ClassificationResult> {
    if (text.length === 0) {
      return {
        type: FALLBACK_CATEGORY,
        subject: FALLBACK_SUBJECT,
        chapter: '',
        confidence: 0.2,
        ocrText: text,
      };
    }

    try {
      const parsed: ParsedClassification = await this.callClassifier(text, timeoutMs);
      return {
        type: parsed.category,
        subject: parsed.subject,
        chapter: parsed.chapter,
        confidence: parsed.confidence,
        ocrText: text,
      };
    } catch (e) {
      console.warn('[TypeClassifier] LLM classify failed, using fallback: ' + ((e as Error).message ?? String(e)));
      const fallback: ParsedClassification = this.ruleFallback(text);
      return {
        type: fallback.category,
        subject: fallback.subject,
        chapter: fallback.chapter,
        confidence: fallback.confidence,
        ocrText: text,
      };
    }
  }

  private async extractText(payload: DispatchPayload, context?: Context): Promise<string> {
    if (payload.kind === 'text') { return payload.text; }
    let baseText: string = '';
    if (payload.kind === 'image') {
      const tool = new OcrTool();
      baseText = await tool.recognize(payload.imageUri);
      return this.mergeUserText(baseText, payload.userText);
    }
    if (payload.kind === 'file') {
      if (payload.mimeType.startsWith('image/')) {
        const tool = new OcrTool();
        baseText = await tool.recognize(payload.fileUri);
      }
      return this.mergeUserText(baseText, payload.userText);
    }
    return '';
  }

  private mergeUserText(ocrText: string, userText: string | undefined): string {
    const parts: string[] = [];
    if (ocrText.trim().length > 0) { parts.push(ocrText.trim()); }
    if (userText !== undefined && userText.trim().length > 0) {
      parts.push('User note:\n' + userText.trim());
    }
    return parts.join('\n\n');
  }

  private preprocessText(text: string): string {
    const normalized: string = text
      .replace(/\r\n/g, '\n')
      .replace(/\r/g, '\n')
      .replace(/\u0000/g, '')
      .replace(/\uFFFD/g, '')
      .replace(/[ \t\f\v]+/g, ' ');
    const lines: string[] = normalized.split('\n');
    const kept: string[] = [];
    for (const rawLine of lines) {
      const line: string = rawLine.trim();
      if (line.length === 0) {
        if (kept.length > 0 && kept[kept.length - 1].length > 0) {
          kept.push('');
        }
        continue;
      }
      if (this.isNoiseLine(line)) {
        continue;
      }
      kept.push(line);
    }
    let cleaned: string = kept.join('\n').trim();
    if (cleaned.length > CLASSIFY_TEXT_LIMIT) { cleaned = cleaned.substring(0, CLASSIFY_TEXT_LIMIT); }
    return cleaned;
  }

  private isNoiseLine(line: string): boolean {
    const lower: string = line.toLowerCase();
    if (this.matchesAny(lower, ['扫描全能王', 'camscanner', '水印', '拍照搜题', '作业帮', '小猿搜题'])) {
      return true;
    }
    if (line.length <= 2 && !this.hasMathSignal(line)) {
      return true;
    }
    return false;
  }

  private hasMathSignal(line: string): boolean {
    return /[0-9a-zA-Z+\-*/=<>≤≥∑∫√∞πθαβγδλμξ]/.test(line);
  }

  private matchesAny(text: string, needles: string[]): boolean {
    for (const needle of needles) {
      if (text.indexOf(needle) >= 0) { return true; }
    }
    return false;
  }

  private async callClassifier(text: string, timeoutMs: number): Promise<ParsedClassification> {
    const categories: string = NOTE_TYPE_KEYS.join(' / ');
    const system: string = '你是数学笔记分类器。只返回纯 JSON，不要 markdown。' +
      'category 必须从以下五类选择: ' + categories + '。' +
      'subject 由你根据题目自主判断，不限制枚举；无法判断时返回 "' + FALLBACK_SUBJECT + '"。' +
      'chapter 返回具体章节/知识点短语，无法判断返回空字符串。' +
      'confidence 返回 0 到 1。';
    const user: string = '请识别下面数学内容的 category、subject、chapter、confidence。\n\n' + text;
    const messages: ChatMessage[] = [
      { role: 'system', content: system + '\n' + JSON_ONLY_RULES },
      { role: 'user', content: user },
    ];
    const guarded: LlmGuardJsonResult = await new LlmGuard().callJsonWithRetry(messages, {
      maxTokens: CLASSIFY_MAX_TOKENS,
      timeoutMs: timeoutMs,
      temperature: 0.1,
      label: 'TypeClassifier classification',
    }, (json: Record<string, Object>): LlmGuardValidationResult => this.validateClassificationJson(json));
    return this.classificationFromJson(guarded.json);
  }

  private parseClassification(raw: string): ParsedClassification {
    let jsonText: string = raw.trim();
    const codeMatch: RegExpMatchArray | null = jsonText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
    if (codeMatch !== null && codeMatch.length >= 2) {
      jsonText = codeMatch[1].trim();
    }
    const braceMatch: RegExpMatchArray | null = jsonText.match(/\{[\s\S]*\}/);
    if (braceMatch !== null) {
      jsonText = braceMatch[0];
    }
    const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
    const validation: LlmGuardValidationResult = this.validateClassificationJson(parsed);
    if (!validation.ok) {
      throw new Error('TypeClassifier JSON invalid: ' + validation.issues.join('; '));
    }
    return this.classificationFromJson(parsed);
  }

  private classificationFromJson(parsed: Record<string, Object>): ParsedClassification {
    const rawCategory: Object | undefined = parsed['category'];
    const rawSubject: Object | undefined = parsed['subject'];
    const rawChapter: Object | undefined = parsed['chapter'];
    const rawConfidence: Object | undefined = parsed['confidence'];
    return {
      category: this.normalizeCategory(String(rawCategory ?? '')),
      subject: this.normalizeSubject(String(rawSubject ?? '')),
      chapter: this.normalizeChapter(String(rawChapter ?? '')),
      confidence: this.normalizeConfidence(Number(rawConfidence ?? 0.65)),
    };
  }

  private validateClassificationJson(parsed: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    const rawCategory: Object | undefined = parsed['category'];
    const categoryText: string = typeof rawCategory === 'string' ? rawCategory : '';
    if (categoryText.length === 0 || !isKnownNoteType(normalizeNoteType(categoryText))) {
      issues.push('category must be one of: ' + NOTE_TYPE_KEYS.join('/'));
    }
    if (typeof parsed['subject'] !== 'string') {
      issues.push('subject must be a string');
    }
    if (parsed['chapter'] !== undefined && typeof parsed['chapter'] !== 'string') {
      issues.push('chapter must be a string when present');
    }
    const confidence: Object | undefined = parsed['confidence'];
    if (typeof confidence !== 'number' && typeof confidence !== 'string') {
      issues.push('confidence must be numeric');
    } else {
      const value: number = Number(confidence);
      if (Number.isNaN(value) || value < 0 || value > 100) {
        issues.push('confidence must be numeric');
      }
    }
    return {
      ok: issues.length === 0,
      issues: issues,
    };
  }

  private ruleFallback(text: string): ParsedClassification {
    return {
      category: this.pickCategoryByRules(text),
      subject: this.pickSubjectByRules(text),
      chapter: this.pickChapterByRules(text),
      confidence: 0.45,
    };
  }

  private pickCategoryByRules(text: string): NoteCategory {
    for (const rule of CATEGORY_RULES) {
      if (this.matchesAny(text, rule.keywords)) {
        return rule.category;
      }
    }
    return FALLBACK_CATEGORY;
  }

  private pickSubjectByRules(text: string): string {
    for (const rule of SUBJECT_RULES) {
      if (this.matchesAny(text, rule.keywords)) {
        return rule.subject;
      }
    }
    return FALLBACK_SUBJECT;
  }

  private pickChapterByRules(text: string): string {
    const lines: string[] = text.split('\n');
    for (const rawLine of lines) {
      const line: string = rawLine.trim();
      if (line.length > 3 && line.length <= 24 && !this.isNoiseLine(line)) {
        return line;
      }
    }
    return '';
  }

  private normalizeCategory(value: string): NoteCategory {
    const normalized: string = normalizeNoteType(value);
    if (isKnownNoteType(normalized)) {
      return normalized as NoteCategory;
    }
    return FALLBACK_CATEGORY;
  }

  private normalizeSubject(value: string): string {
    const subject: string = value.trim();
    if (subject.length === 0 || subject === '未知' || subject === 'null' || subject === 'undefined') {
      return FALLBACK_SUBJECT;
    }
    return subject;
  }

  private normalizeChapter(value: string): string {
    const chapter: string = value.trim();
    if (chapter === '未知' || chapter === 'null' || chapter === 'undefined') {
      return '';
    }
    return chapter;
  }

  private normalizeConfidence(value: number): number {
    if (value >= 0 && value <= 1) {
      return value;
    }
    if (value > 1 && value <= 100) {
      return value / 100;
    }
    return 0.65;
  }
}
