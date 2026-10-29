/**
 * NoteMarkdownExport.test.ets — #232 笔记 Markdown 导出与 AI 溯源测试
 *
 * 路径: entry/src/test/NoteMarkdownExport.test.ets
 * 职责: 验证 front-matter 五字段、model 缺失兜底、本地时区 exported_at、
 *       以及标题/摘要/正文的拼装与空 content 的省略规则。
 * 依赖: @ohos/hypium; NoteMarkdownExport; common (KnowledgeUnit)
 *
 * 数据流:
 *   固定时间戳 + 合成 KnowledgeUnit → buildFrontMatter/buildMarkdown → 字符串断言
 *
 * ArkTS 1.1 strict 适配:
 *   - 固定时间戳用本地时间构造（new Date(y, m, d, h, min, s)），断言与设备时区无关
 *   - 所有局部变量显式类型；不用 any/unknown
 */

import { describe, expect, it } from '@ohos/hypium'
import { DifficultyLevel, KnowledgeUnit, ReviewStatus } from 'common'
import {
  buildFrontMatter,
  buildMarkdown,
} from '../main/ets/services/NoteMarkdownExport'

// 本地时间 2026-10-25 14:32:11（+08:00 设备上对应 2026-10-25T14:32:11+08:00）
const FIXED_TS: number = new Date(2026, 9, 25, 14, 32, 11).getTime()

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString()
}

function expectedOffset(ts: number): string {
  const date: Date = new Date(ts)
  const offsetMinutes: number = -date.getTimezoneOffset()
  const sign: string = offsetMinutes >= 0 ? '+' : '-'
  const absoluteMinutes: number = Math.abs(offsetMinutes)
  return sign + pad2(Math.floor(absoluteMinutes / 60)) + ':' + pad2(absoluteMinutes % 60)
}

function expectedExportedAt(ts: number): string {
  const date: Date = new Date(ts)
  return date.getFullYear().toString()
    + '-' + pad2(date.getMonth() + 1)
    + '-' + pad2(date.getDate())
    + 'T' + pad2(date.getHours())
    + ':' + pad2(date.getMinutes())
    + ':' + pad2(date.getSeconds())
    + expectedOffset(ts)
}

function exportedAtOf(frontMatter: string): string {
  const lines: string[] = frontMatter.split('\n')
  for (const line of lines) {
    if (line.indexOf('exported_at: ') === 0) {
      return line.substring('exported_at: '.length)
    }
  }
  return ''
}

function makeUnit(title: string, summary: string, content: string): KnowledgeUnit {
  return {
    id: 'note-232',
    title: title,
    content: content,
    summary: summary,
    tags: ['极限'],
    subject: '高等数学',
    category: '概念',
    chapter: '极限',
    difficulty: DifficultyLevel.MEDIUM,
    source: 'camera_capture',
    createdAt: FIXED_TS,
    updatedAt: FIXED_TS,
    reviewStatus: ReviewStatus.NEW,
    nextReviewAt: FIXED_TS,
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 0,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: '',
    version: 1,
  }
}

export default function noteMarkdownExportTest(): void {
  describe('NoteMarkdownExport', (): void => {
    it('should emit all five front-matter fields in fixed order', 0, (): void => {
      const frontMatter: string = buildFrontMatter('deepseek/deepseek-v4-pro', FIXED_TS)

      expect(frontMatter.indexOf('ai_generated: true') >= 0).assertTrue()
      expect(frontMatter.indexOf('app: MindTrace') >= 0).assertTrue()
      expect(frontMatter.indexOf('agent: mindtrace-note-agent') >= 0).assertTrue()
      expect(frontMatter.indexOf('model: deepseek/deepseek-v4-pro') >= 0).assertTrue()
      expect(frontMatter.indexOf('exported_at: ') >= 0).assertTrue()
      expect(frontMatter.indexOf('---') === 0).assertTrue()
      expect(frontMatter.split('---').length).assertEqual(3)
      expect(frontMatter.indexOf('ai_generated') < frontMatter.indexOf('app: MindTrace')
        && frontMatter.indexOf('app: MindTrace') < frontMatter.indexOf('agent: mindtrace-note-agent')
        && frontMatter.indexOf('agent: mindtrace-note-agent') < frontMatter.indexOf('exported_at')
        && frontMatter.indexOf('exported_at') < frontMatter.indexOf('model:')).assertTrue()
    })

    it('should fall back to unknown when modelId is blank', 0, (): void => {
      const frontMatter: string = buildFrontMatter('   ', FIXED_TS)

      expect(frontMatter).assertContain('model: unknown')
      expect(frontMatter.indexOf('model: \n') < 0).assertTrue()
      expect(frontMatter.indexOf('ai_generated: true') >= 0).assertTrue()
    })

    it('should format exported_at with the local timezone offset', 0, (): void => {
      const exportedAt: string = exportedAtOf(buildFrontMatter('deepseek/deepseek-v4-pro', FIXED_TS))
      const offset: string = expectedOffset(FIXED_TS)

      expect(exportedAt).assertEqual(expectedExportedAt(FIXED_TS))
      expect(exportedAt.indexOf('2026-10-25T14:32:11') === 0).assertTrue()
      expect(exportedAt.indexOf('Z') < 0).assertTrue()
      expect(exportedAt.indexOf(offset) === exportedAt.length - offset.length).assertTrue()
    })

    it('should include title, summary and content in markdown body', 0, (): void => {
      const markdown: string = buildMarkdown(
        makeUnit('极限定义', '函数极限的直观描述', '当 x 趋近于 a 时，函数值趋近于 L。'),
        'deepseek/deepseek-v4-pro',
        FIXED_TS,
      )

      expect(markdown.indexOf('# 极限定义') >= 0).assertTrue()
      expect(markdown.indexOf('函数极限的直观描述') >= 0).assertTrue()
      expect(markdown.indexOf('当 x 趋近于 a 时，函数值趋近于 L。') >= 0).assertTrue()
      expect(markdown.indexOf('ai_generated: true') >= 0).assertTrue()
      expect(markdown.indexOf('ai_generated: true') < markdown.indexOf('# 极限定义')).assertTrue()
      expect(markdown.indexOf('# 极限定义') > markdown.indexOf('\n---\n')).assertTrue()
    })

    it('should omit the content block when content is empty', 0, (): void => {
      const markdown: string = buildMarkdown(makeUnit('极限定义', '只有摘要', ''), 'deepseek/deepseek-v4-pro', FIXED_TS)
      const trimmed: string = markdown.trim()

      expect(markdown.indexOf('只有摘要') >= 0).assertTrue()
      expect(trimmed.substring(trimmed.length - '只有摘要'.length)).assertEqual('只有摘要')
      expect(markdown.indexOf('\n\n\n') < 0).assertTrue()
      expect(markdown.indexOf('# 极限定义') >= 0).assertTrue()
    })
  })
}
