/**
 * NoteItemMapper.ets — KnowledgeUnit → NoteItem 视图层转换
 *
 * 路径: entry/src/main/ets/utils/NoteItemMapper.ets
 * 职责: 把 common 模块的 KnowledgeUnit (持久化业务模型) 转换成
 *       UI 用的 NoteItem 视图模型，供 NotesPage / NotesList 渲染。
 * 依赖: common (KnowledgeUnit / NoteItem / ReviewStatus 类型)
 *
 * 数据流:
 *   KnowledgeUnit (DB/AI 产出)
 *     → unitToNoteItem(unit)
 *       → stableNumericId(unit.id)         // 字符串 ID → 32 位整数 (UI 列表 key 用)
 *       → confidence(unit.reviewStatus)     // ReviewStatus → 0-1 掌握度
 *       → dateText(unit.createdAt)         // 时间戳 → yyyy-MM-dd
 *     → NoteItem (UI 直接渲染)
 *
 * ReviewStatus → 掌握度映射:
 *   GRADUATED 0.95 | REVIEW 0.86 | LEARNING 0.72 | LAPSED 0.45 | 默认 0.64
 *
 * ArkTS 1.1 strict 适配:
 *   - stableNumericId 用 for...of 替代 while + 手动 idx 递增
 *   - JSON.parse 强转 as string[] 后逐项 typeof 检查兜底
 *   - 无 any / unknown，错误统一 (e as Error).message
 */
import {
  ContentExcerptBuilder,
  isKnownNoteType,
  KnowledgeUnit,
  normalizeNoteType,
  NoteItem,
  ReviewStatus,
} from "common"

const CAMERA_SOURCE: string = "camera_capture"
const NOTE_CARD_PREVIEW_LIMIT: number = 46
const CONTENT_EXCERPT_BUILDER: ContentExcerptBuilder = new ContentExcerptBuilder()
const MANUAL_SOURCE: string = "manual"
const FILE_IMPORT_SOURCE: string = "file_import"

function isSourceTag(tag: string): boolean {
  return tag === CAMERA_SOURCE || tag === MANUAL_SOURCE || tag === FILE_IMPORT_SOURCE
}

function resolveType(tags: string[]): string {
  for (const tag of tags) {
    const type: string = normalizeNoteType(tag)
    if (isKnownNoteType(type)) {
      return type
    }
  }
  return firstReturnedFeature(tags)
}

function resolveSubject(tags: string[]): string {
  for (const tag of tags) {
    const t: string = tag.trim()
    if (isReturnedSubjectFeature(t)) {
      return t
    }
  }
  return ""
}

function isReturnedSubjectFeature(tag: string): boolean {
  if (tag.length === 0 || isKnownNoteType(tag) || isSourceTag(tag)) {
    return false
  }
  return true
}

function firstReturnedFeature(tags: string[]): string {
  for (const tag of tags) {
    const t: string = tag.trim()
    if (t.length > 0 && !isSourceTag(t)) {
      return normalizeNoteType(t)
    }
  }
  return "笔记"
}

function stableNumericId(id: string): number {
  let hash: number = 0
  for (const ch of id) {
    hash = (hash * 31 + ch.charCodeAt(0)) % 2147483647
  }
  return hash
}

function pad2(value: number): string {
  return value < 10 ? "0" + value.toString() : value.toString()
}

function dateText(ts: number): string {
  const d: Date = new Date(ts > 0 ? ts : Date.now())
  return d.getFullYear().toString() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function confidence(unit: KnowledgeUnit): number {
  if (unit.reviewStatus === ReviewStatus.GRADUATED) { return 0.95 }
  if (unit.reviewStatus === ReviewStatus.REVIEW) { return 0.86 }
  if (unit.reviewStatus === ReviewStatus.LEARNING) { return 0.72 }
  if (unit.reviewStatus === ReviewStatus.LAPSED) { return 0.45 }
  return 0.64
}

export function unitToNoteItem(unit: KnowledgeUnit): NoteItem {
  const rawId: string = unit.id.length > 0 ? unit.id : unit.title + unit.createdAt.toString()
  const subject: string = unit.subject.trim().length > 0 ? unit.subject.trim() : resolveSubject(unit.tags)
  const type: string = unit.category.length > 0 ? unit.category : resolveType(unit.tags)
  const chapter: string = unit.chapter.length > 0 ? unit.chapter : subject
  const previewSource: string = unit.summary.trim().length > 0 ? unit.summary : unit.content
  const body: string = CONTENT_EXCERPT_BUILDER.buildListPreview(previewSource, NOTE_CARD_PREVIEW_LIMIT)

  return new NoteItem(
    stableNumericId(rawId),
    unit.title,
    type,
    subject,
    chapter,
    confidence(unit),
    body,
    unit.tags,
    dateText(unit.createdAt),
    rawId,
  )
}

export function unitsToNoteItems(units: KnowledgeUnit[]): NoteItem[] {
  const notes: NoteItem[] = []
  for (const unit of units) {
    notes.push(unitToNoteItem(unit))
  }
  return notes
}
