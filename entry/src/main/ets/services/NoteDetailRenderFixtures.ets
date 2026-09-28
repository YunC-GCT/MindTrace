/**
 * NoteDetailRenderFixtures.ets — NoteDetail 离线性能基准输入
 *
 * 路径: entry/src/main/ets/services/NoteDetailRenderFixtures.ets
 * 职责: 定义 A/B/C/C′ 公式矩阵、短/长正文与六种 renderer 输入，并构造真实
 *       NoteDetailOverlay 所需的 NoteItem / KnowledgeUnit / KnowledgeUnit[]。
 * 依赖: common 数据模型
 *
 * 数据流:
 *   fixture id + NoteType + length profile → createNoteDetailBenchmarkFixture() → Overlay props
 *
 * 设计要点:
 *   - 固定文本、固定时间戳、无网络/随机/LLM 依赖。
 *   - A/B/C/C′ 公式数冻结为 0/2/6/6；C′ 为 3 对连续闭合公式。
 *   - short/long 正文分别固定为 800/2000 UTF-16 code-unit。
 *
 * ArkTS 1.1 strict 适配:
 *   - 所有对象字面量都有显式接口上下文；不使用 any/unknown/解构。
 */

import {
  NoteItem,
  KnowledgeUnit,
  DifficultyLevel,
  ReviewStatus,
} from 'common'

export type NoteDetailFixtureId = 'A' | 'B' | 'C' | 'C_P'
export type NoteDetailFixtureLayout = 'none' | 'sparse' | 'dense' | 'consecutive_pairs'
export type NoteDetailLengthProfile = 'short' | 'long'
export type NoteDetailFixtureNoteType = '概念' | '定理' | '公式' | '证明题' | '计算题'
export type NoteDetailRendererFamily = NoteDetailFixtureNoteType | '兜底'

export interface NoteDetailFixtureDefinition {
  id: NoteDetailFixtureId
  formulaCount: number
  layout: NoteDetailFixtureLayout
}

export class NoteDetailBenchmarkFixture {
  id: NoteDetailFixtureId = 'A'
  rendererFamily: NoteDetailRendererFamily = '概念'
  lengthProfile: NoteDetailLengthProfile = 'long'
  formulaCount: number = 0
  bodyText: string = ''
  note: NoteItem = new NoteItem(0, '', '', '', '', 0, '', [], '')
  unit: KnowledgeUnit
  units: KnowledgeUnit[] = []

  constructor(id: NoteDetailFixtureId, rendererFamily: NoteDetailRendererFamily,
    lengthProfile: NoteDetailLengthProfile, formulaCount: number, bodyText: string,
    note: NoteItem, unit: KnowledgeUnit, units: KnowledgeUnit[]) {
    this.id = id
    this.rendererFamily = rendererFamily
    this.lengthProfile = lengthProfile
    this.formulaCount = formulaCount
    this.bodyText = bodyText
    this.note = note
    this.unit = unit
    this.units = units
  }
}

export const NOTE_DETAIL_SHORT_CODE_UNITS: number = 800
export const NOTE_DETAIL_LONG_CODE_UNITS: number = 2000

export const NOTE_DETAIL_RENDERER_FAMILIES: NoteDetailRendererFamily[] = [
  '概念',
  '定理',
  '公式',
  '证明题',
  '计算题',
  '兜底',
]

export const NOTE_DETAIL_FIXTURE_A: NoteDetailFixtureDefinition = {
  id: 'A',
  formulaCount: 0,
  layout: 'none',
}

export const NOTE_DETAIL_FIXTURE_B: NoteDetailFixtureDefinition = {
  id: 'B',
  formulaCount: 2,
  layout: 'sparse',
}

export const NOTE_DETAIL_FIXTURE_C: NoteDetailFixtureDefinition = {
  id: 'C',
  formulaCount: 6,
  layout: 'dense',
}

export const NOTE_DETAIL_FIXTURE_C_P: NoteDetailFixtureDefinition = {
  id: 'C_P',
  formulaCount: 6,
  layout: 'consecutive_pairs',
}

export const NOTE_DETAIL_FIXTURES: NoteDetailFixtureDefinition[] = [
  NOTE_DETAIL_FIXTURE_A,
  NOTE_DETAIL_FIXTURE_B,
  NOTE_DETAIL_FIXTURE_C,
  NOTE_DETAIL_FIXTURE_C_P,
]

const FIXED_CREATED_AT: number = 1789956000000
const BASE_SENTENCE: string = '函数、定义、推导与例题共同构成可复习的数学知识单元。'
const FORMULA_TEXT: string = '$$x^2 + y^2 = z^2$$'
const PAIR_SEPARATOR: string = ' '
const GROUP_SEPARATOR: string = '正文分隔段落。'

function targetLength(profile: NoteDetailLengthProfile): number {
  return profile === 'short' ? NOTE_DETAIL_SHORT_CODE_UNITS : NOTE_DETAIL_LONG_CODE_UNITS
}

function repeatToLength(seed: string, length: number): string {
  let text: string = '## 定义\n'
  while (text.length < length) {
    text += seed
  }
  return text.substring(0, length)
}

function replaceRange(original: string, start: number, replacement: string): string {
  return original.substring(0, start) + replacement + original.substring(start + replacement.length)
}

function buildFormulaRun(definition: NoteDetailFixtureDefinition): string {
  if (definition.id === 'C_P') {
    const pair: string = FORMULA_TEXT + PAIR_SEPARATOR + FORMULA_TEXT
    return pair + GROUP_SEPARATOR + pair + GROUP_SEPARATOR + pair
  }
  let run: string = ''
  let index: number = 0
  while (index < definition.formulaCount) {
    if (run.length > 0) {
      run += '\n正文公式分隔。\n'
    }
    run += FORMULA_TEXT
    index += 1
  }
  return run
}

function buildFixtureBody(definition: NoteDetailFixtureDefinition,
  profile: NoteDetailLengthProfile): string {
  const length: number = targetLength(profile)
  let body: string = repeatToLength(BASE_SENTENCE, length)
  if (definition.formulaCount === 0) {
    return body
  }
  const formulaRun: string = buildFormulaRun(definition)
  const start: number = definition.id === 'B'
    ? Math.floor((length - formulaRun.length) / 2)
    : Math.floor(length / 5)
  body = replaceRange(body, Math.max(16, start), formulaRun)
  return body.substring(0, length)
}

function definitionById(id: NoteDetailFixtureId): NoteDetailFixtureDefinition {
  if (id === 'A') {
    return NOTE_DETAIL_FIXTURE_A
  }
  if (id === 'B') {
    return NOTE_DETAIL_FIXTURE_B
  }
  if (id === 'C') {
    return NOTE_DETAIL_FIXTURE_C
  }
  return NOTE_DETAIL_FIXTURE_C_P
}

function rendererFamilyIndex(rendererFamily: NoteDetailRendererFamily): number {
  const index: number = NOTE_DETAIL_RENDERER_FAMILIES.indexOf(rendererFamily)
  return index < 0 ? 0 : index
}

function fixtureIndex(id: NoteDetailFixtureId): number {
  if (id === 'A') { return 1 }
  if (id === 'B') { return 2 }
  if (id === 'C') { return 3 }
  return 4
}

function fixtureCategoryForRenderer(rendererFamily: NoteDetailRendererFamily): string {
  return rendererFamily === '兜底' ? '未知类型' : rendererFamily
}

function buildUnit(id: NoteDetailFixtureId, rendererFamily: NoteDetailRendererFamily,
  profile: NoteDetailLengthProfile, bodyText: string): KnowledgeUnit {
  const rawId: string = 'note-detail-bench-' + id + '-' + rendererFamilyIndex(rendererFamily).toString()
    + '-' + profile
  const unit: KnowledgeUnit = {
    id: rawId,
    title: 'NoteDetail ' + id + ' · ' + rendererFamily + ' · ' + profile,
    content: bodyText,
    summary: id === 'A' ? '无公式基准' : '公式渲染基准',
    tags: ['benchmark', id, profile],
    subject: '数学分析',
    category: fixtureCategoryForRenderer(rendererFamily),
    chapter: 'NoteDetail 性能基线',
    difficulty: DifficultyLevel.MEDIUM,
    source: 'manual',
    createdAt: FIXED_CREATED_AT,
    updatedAt: FIXED_CREATED_AT,
    reviewStatus: ReviewStatus.NEW,
    nextReviewAt: FIXED_CREATED_AT,
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 0,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: 'benchmark',
    version: 1,
  }
  return unit
}

export function countNoteDetailFormulaPairs(text: string): number {
  let count: number = 0
  let searchFrom: number = 0
  while (true) {
    const openIndex: number = text.indexOf('$$', searchFrom)
    if (openIndex < 0) {
      break
    }
    const closeIndex: number = text.indexOf('$$', openIndex + 2)
    if (closeIndex < 0) {
      break
    }
    count += 1
    searchFrom = closeIndex + 2
  }
  return count
}

export function noteDetailFormulaGaps(text: string): number[] {
  const gaps: number[] = []
  let previousCloseEnd: number = -1
  let searchFrom: number = 0
  while (true) {
    const openIndex: number = text.indexOf('$$', searchFrom)
    if (openIndex < 0) {
      break
    }
    const closeIndex: number = text.indexOf('$$', openIndex + 2)
    if (closeIndex < 0) {
      break
    }
    if (previousCloseEnd >= 0) {
      gaps.push(openIndex - previousCloseEnd)
    }
    previousCloseEnd = closeIndex + 2
    searchFrom = closeIndex + 2
  }
  return gaps
}

export function createNoteDetailBenchmarkFixture(id: NoteDetailFixtureId,
  rendererFamily: NoteDetailRendererFamily, profile: NoteDetailLengthProfile): NoteDetailBenchmarkFixture {
  const definition: NoteDetailFixtureDefinition = definitionById(id)
  const bodyText: string = buildFixtureBody(definition, profile)
  const unit: KnowledgeUnit = buildUnit(id, rendererFamily, profile, bodyText)
  const noteId: number = fixtureIndex(id) * 100 + rendererFamilyIndex(rendererFamily) * 10
    + (profile === 'short' ? 1 : 2)
  const note: NoteItem = new NoteItem(noteId, unit.title, unit.category, unit.subject, unit.chapter,
    0.9, bodyText, unit.tags.slice(), '2026-09-27', unit.id)
  const units: KnowledgeUnit[] = [unit]
  return new NoteDetailBenchmarkFixture(id, rendererFamily, profile, definition.formulaCount,
    bodyText, note, unit, units)
}
