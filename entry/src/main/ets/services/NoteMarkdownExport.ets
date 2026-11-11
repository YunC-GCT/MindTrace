/**
 * NoteMarkdownExport.ets — 笔记 Markdown 导出（带 AI 生成溯源 front-matter）
 *
 * 路径: entry/src/main/ets/services/NoteMarkdownExport.ets
 * 职责: 把 KnowledgeUnit 拼成 Markdown（固定五字段 front-matter + 标题 + 摘要 + 正文），
 *       经 DocumentViewPicker 让用户选目录，再用 fileIo 写入 .md 文件。
 * 依赖: @kit.CoreFileKit (picker / fileIo)、@kit.AbilityKit (common.UIAbilityContext)、
 *       @kit.PerformanceAnalysisKit (hilog)、common (KnowledgeUnit)
 *
 * 数据流:
 *   NoteDetailOverlay.exportNote()
 *     → NoteMarkdownExporter.save(context, unit, LlmConfig.modelLabel())
 *     → buildMarkdown() → picker.DocumentViewPicker.save()
 *     → fileIo.openSync/writeSync/closeSync → 返回写入 URI
 *
 * 用户取消（picker 返回空数组）时返回空串，由调用方决定不弹错误提示。
 *
 * ArkTS 1.1 strict 适配:
 *   - 保存选项显式声明为 picker.DocumentSaveOptions，不用无类型对象字面量
 *   - 异常统一 throw new Error(String(e))，不写 throw e as Error
 *   - 所有局部变量显式标注类型
 */
import { common } from '@kit.AbilityKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { KnowledgeUnit } from 'common'

const TAG: string = 'NoteExport'
const DOMAIN: number = 0x2320
const UNKNOWN_MODEL: string = 'unknown'
const UNTITLED_NOTE: string = '未命名笔记'

/**
 * 拼装固定五字段的 front-matter（字段顺序不可变）。
 * exported_at 使用本地时区偏移（如 +08:00），不是 UTC 的 Z。
 */
export function buildFrontMatter(modelId: string, now: number): string {
  const lines: string[] = [
    '---',
    'ai_generated: true',
    'app: MindTrace',
    'agent: mindtrace-note-agent',
    'exported_at: ' + formatExportedAt(now),
    'model: ' + resolveModelId(modelId),
    '---',
  ]
  return lines.join('\n') + '\n'
}

/**
 * front-matter + `# 标题` + 空行 + summary + 空行 + content。
 * content 为空时整段省略（包括分隔空行）。
 */
export function buildMarkdown(unit: KnowledgeUnit, modelId: string, now: number): string {
  const rawTitle: string = unit.title.trim()
  const title: string = rawTitle.length > 0 ? rawTitle : UNTITLED_NOTE
  const summary: string = unit.summary.trim()
  const content: string = unit.content.trim()
  const blocks: string[] = ['# ' + title]
  if (summary.length > 0) {
    blocks.push(summary)
  }
  if (content.length > 0) {
    blocks.push(content)
  }
  return buildFrontMatter(modelId, now) + '\n' + blocks.join('\n\n') + '\n'
}

export class NoteMarkdownExporter {
  /**
   * 弹出系统保存面板并写入 Markdown。
   * @returns 写入成功的 URI；用户取消时返回空串。
   */
  static async save(context: common.UIAbilityContext, unit: KnowledgeUnit, modelId: string): Promise<string> {
    const now: number = Date.now()
    const markdown: string = buildMarkdown(unit, modelId, now)
    const fileName: string = 'mindtrace-' + unit.id + '-' + formatCompactDate(new Date(now)) + '.md'
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
    options.newFileNames = [fileName]
    options.fileSuffixChoices = ['.md']

    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context)
    let uris: string[] = []
    try {
      uris = await documentPicker.save(options)
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'export fail')
      throw new Error(String(e))
    }
    if (uris.length === 0) {
      return ''
    }

    const uri: string = uris[0]
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      const bytes: number = fileIo.writeSync(file.fd, markdown)
      fileIo.closeSync(file.fd)
      file = null
      hilog.info(DOMAIN, TAG, '%{public}s', 'export ok bytes=' + bytes.toString())
      return uri
    } catch (e) {
      if (file !== null) {
        try {
          fileIo.closeSync(file.fd)
        } catch (_closeError) {
        }
      }
      hilog.error(DOMAIN, TAG, '%{public}s', 'export fail')
      throw new Error(String(e))
    }
  }
}

function resolveModelId(modelId: string): string {
  const trimmed: string = modelId.trim()
  return trimmed.length > 0 ? trimmed : UNKNOWN_MODEL
}

/** Date#getTimezoneOffset 是 UTC 减本地（分钟），取反得到本地偏移。 */
function formatExportedAt(now: number): string {
  const date: Date = new Date(now)
  const offsetMinutes: number = -date.getTimezoneOffset()
  const sign: string = offsetMinutes >= 0 ? '+' : '-'
  const absoluteMinutes: number = Math.abs(offsetMinutes)
  return date.getFullYear().toString()
    + '-' + pad2(date.getMonth() + 1)
    + '-' + pad2(date.getDate())
    + 'T' + pad2(date.getHours())
    + ':' + pad2(date.getMinutes())
    + ':' + pad2(date.getSeconds())
    + sign + pad2(Math.floor(absoluteMinutes / 60))
    + ':' + pad2(absoluteMinutes % 60)
}

function formatCompactDate(date: Date): string {
  return date.getFullYear().toString()
    + pad2(date.getMonth() + 1)
    + pad2(date.getDate())
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString()
}
