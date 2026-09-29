/**
 * KnowledgeUnitExt.ets — 扩展知识单元类型（KnowledgeModel MVP 专用）
 *
 * 新需求（2026-07）：
 *   5 个最小类：概念/定理/公式/证明题/计算题
 *   AI 自分词 + 填充各类的结构化字段
 *   difficulty 为 1~4 级，importance 为 1~5 级
 */

import { KnowledgeCategory } from './KnowledgeCategory';

// ═══════════════════════════════════════
// 结构化字段
// ═══════════════════════════════════════

/**
 * 结构化字段 — 每个最小类独有的"表列"
 *
 *   key:   程序使用的字段名（如 "definition"）
 *   label: 用户看到的列标题（如 "定义"）
 *   value: AI 填充的内容
 */
export interface StructuredField {
  readonly key: string;
  readonly label: string;
  readonly value: string;
}

/**
 * AI 原始响应（从 AI 返回的 JSON 解析）
 */
export interface AiRawResponse {
  readonly category: KnowledgeCategory;
  readonly subject: string;
  readonly chapter: string;
  readonly title: string;
  readonly tags: string[];
  readonly difficulty: number;
  readonly importance: number;
  readonly fields: StructuredField[];
}

// ═══════════════════════════════════════
// 扩展知识单元
// ═══════════════════════════════════════

export interface KnowledgeUnitExt {
  // ── 核心字段 ──
  /** 唯一标识（由 NoteDao.insert 回填） */
  id: string;
  /** 最小类（5 个之一） */
  type: KnowledgeCategory;
  /** 标题：
   *   概念/定理/公式 → 严谨名称
   *   证明题/计算题   → AI 概括总结 */
  title: string;
  /** 用户输入的完整 OCR 原文 */
  content: string;
  /** 标签（最小类 + AI 关键词 + 学科） */
  tags: string[];
  /** 学科 */
  subject: string;
  /** 章节/知识点短语（独立于 source） */
  chapter: string;

  // ── 结构化字段（该最小类特有的表内容） ──
  /** 该类特有的键值对数组，UI 统一渲染 */
  fields: StructuredField[];

  // ── 真值检验 ──
  /** 是否通过全部真值检验 */
  truthFlag: boolean;
  /** 真值检验详情 */
  truthDetails: string[];

  // ── 评分 ──
  /** 难度 1~4（简单/中等/困难/专家），可由 AI 判定或用户自定义 */
  difficulty: number;
  /** 重要程度 1~5，可由 AI 判定或用户自定义 */
  importance: number;

  // ── 元数据 ──
  /** 需要用户确认/自定义的字段名列表（如 title 不确定时） */
  needsUserInput: string[];
  /** 创建时间戳 ms */
  createdAt: number;
  /** 更新时间戳 ms */
  updatedAt: number;

  // ── 来源 ──
  /** 来源描述 */
  source: string;
  /** 所属用户 ID */
  userId: string;
}

// ═══════════════════════════════════════
// 工厂函数
// ═══════════════════════════════════════

/**
 * 创建空的 KnowledgeUnitExt（带默认值）
 *
 * @param category 最小类
 * @param title 标题
 * @param content 原文
 * @returns 填充默认值的 KnowledgeUnitExt
 */
export function createUnitExt(
  category: KnowledgeCategory,
  subject: string,
  title: string,
  content: string
): KnowledgeUnitExt {
  const now: number = Date.now();
  return {
    id: '',
    type: category,
    title: title,
    content: content,
    tags: [],
    subject: subject,
    chapter: '',
    fields: [],
    truthFlag: true,
    truthDetails: [],
    difficulty: 3,
    importance: 3,
    needsUserInput: [],
    createdAt: now,
    updatedAt: now,
    source: '',
    userId: '',
  };
}
