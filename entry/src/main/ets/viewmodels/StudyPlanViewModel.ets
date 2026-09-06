// ============================================================================
//  viewmodels/StudyPlanViewModel.ets — 学习计划业务逻辑层
//  ----------------------------------------------------------------------------
//  职责: 管理学习计划列表的增删改查 + AI 智能生成。
//  持久化: StudyPlanDao (RDB study_plan 表)，init() 时加载全量。
//  AI: generatePlan() 通过 LlmClient 调 DeepSeek，基于已有 KnowledgeUnit 生成计划。
//
//  ArkTS 1.1 strict:
//    - 显式类型，无 Record<>，无 RegExpMatchArray
//    - 变更后 this.items = this.items.slice(0) 强制数组引用更新，触发 @Observed→ForEach 重渲染
//  ============================================================================

import { StudyPlanItem } from "common"
import { DatabaseHelper } from "common"
import { LlmClient } from "common"
import type { ChatMessage, LlmCallResult } from "common"
import { StudyPlanDao } from "../database/StudyPlanDao"
import { StudyPlanSnapshot, UiDataCacheService } from "../services/UiDataCacheService"

@Observed
export class StudyPlanViewModel {
  items: StudyPlanItem[] = []
  newTitle: string = ""
  editingId: string = ""
  isLoading: boolean = false
  initError: boolean = false
  private dao: StudyPlanDao | null = null
  private llm: LlmClient = new LlmClient()

  // ---- 初始化 ----
  async init(context: Context): Promise<void> {
    try {
      const cached: StudyPlanSnapshot | null = UiDataCacheService.getStudyPlanSnapshot()
      if (cached !== null) {
        this.items = cached.items.slice(0)
        this.initError = false
      }
      const store = await DatabaseHelper.init(context)
      this.dao = new StudyPlanDao(store)
      this.items = await this.dao.queryAll()
      UiDataCacheService.setStudyPlanSnapshot(this.items)
      this.initError = false
    } catch (e) {
      console.error("[StudyPlanViewModel.init] " + (e as Error).message)
      this.dao = null
      this.initError = true
    }
  }

  // ---- 计算属性 ----
  get completedCount(): number {
    let count: number = 0
    for (const item of this.items) {
      if (item.isDone) {
        count++
      }
    }
    return count
  }

  get totalCount(): number {
    return this.items.length
  }

  get isEditing(): boolean {
    return this.editingId.length > 0
  }

  async submitInput(): Promise<void> {
    if (this.isEditing) {
      await this.saveEditing()
    } else {
      await this.addItem()
    }
  }

  // ---- 新增 ----
  async addItem(): Promise<void> {
    const trimmed: string = this.newTitle.trim()
    if (trimmed.length === 0) {
      return
    }
    const item: StudyPlanItem = new StudyPlanItem(trimmed)

    if (this.dao !== null) {
      try {
        await this.dao.insert(item)
      } catch (e) {
        console.error("[StudyPlanViewModel.addItem] " + (e as Error).message)
      }
    }
    this.items.push(item)
    this.items = this.items.slice(0)
    this.refreshStudyPlanCache()
    this.newTitle = ""
  }

  // ---- 开始修改 ----
  beginEdit(item: StudyPlanItem): void {
    this.editingId = item.id
    this.newTitle = item.title
  }

  // ---- 保存修改 ----
  async saveEditing(): Promise<void> {
    const trimmed: string = this.newTitle.trim()
    if (trimmed.length === 0 || this.editingId.length === 0) {
      return
    }
    const idx: number = this.items.findIndex((i: StudyPlanItem): boolean => i.id === this.editingId)
    if (idx < 0) {
      this.editingId = ""
      this.newTitle = ""
      return
    }

    this.items[idx].title = trimmed
    this.items = this.items.slice(0)
    this.refreshStudyPlanCache()

    if (this.dao !== null) {
      try {
        await this.dao.updateTitle(this.editingId, trimmed)
      } catch (e) {
        console.error("[StudyPlanViewModel.saveEditing] " + (e as Error).message)
      }
    }
    this.editingId = ""
    this.newTitle = ""
  }

  // ---- 切换完成状态 ----
  async toggleItem(item: StudyPlanItem): Promise<void> {
    const idx: number = this.items.findIndex((i: StudyPlanItem): boolean => i.id === item.id)
    if (idx < 0) {
      return
    }
    this.items[idx].isDone = !this.items[idx].isDone
    this.items = this.items.slice(0)
    this.refreshStudyPlanCache()

    if (this.dao !== null) {
      try {
        await this.dao.updateDone(item.id, this.items[idx].isDone)
      } catch (e) {
        console.error("[StudyPlanViewModel.toggleItem] " + (e as Error).message)
      }
    }
  }

  // ---- 删除 ----
  async deleteItem(item: StudyPlanItem): Promise<void> {
    const newItems: StudyPlanItem[] = []
    for (const candidate of this.items) {
      if (candidate.id !== item.id) {
        newItems.push(candidate)
      }
    }
    this.items = newItems
    this.refreshStudyPlanCache()

    if (this.dao !== null) {
      try {
        await this.dao.deleteById(item.id)
      } catch (e) {
        console.error("[StudyPlanViewModel.deleteItem] " + (e as Error).message)
      }
    }
  }

  // ---- 置顶 ----
  async pinItem(item: StudyPlanItem): Promise<void> {
    const idx: number = this.items.findIndex((i: StudyPlanItem): boolean => i.id === item.id)
    if (idx <= 0) {
      return
    }
    const pinned: StudyPlanItem = this.items[idx]
    pinned.createdAt = Date.now()
    const newItems: StudyPlanItem[] = [pinned]
    for (const candidate of this.items) {
      if (candidate.id !== item.id) {
        newItems.push(candidate)
      }
    }
    this.items = newItems
    this.refreshStudyPlanCache()
    if (this.editingId === item.id) {
      this.editingId = ""
      this.newTitle = ""
    }

    if (this.dao !== null) {
      try {
        await this.dao.updateCreatedAt(item.id, pinned.createdAt)
      } catch (e) {
        console.error("[StudyPlanViewModel.pinItem] " + (e as Error).message)
      }
    }
  }

  // ---- AI 智能生成 ----
  async generatePlan(knownTitles: string[]): Promise<void> {
    this.isLoading = true
    try {
      const contextStr: string = knownTitles.length > 0
        ? "用户已有以下知识点/计划：" + knownTitles.join("、") + "。"
        : "用户正在学习大学数学（数学分析、高等代数、解析几何）。"

      const systemPrompt: string =
        "你是一个学习计划助手。" + contextStr +
        "请根据这些信息，生成 3-5 条具体的学习计划待办事项，帮助用户系统复习。" +
        "每条计划应简短（15字以内）、可执行。以纯 JSON 字符串数组格式返回，如 [\"复习极限定义\",\"做 3 道导数题\"]。" +
        "只返回 JSON 数组，不要其他内容。"

      const messages: ChatMessage[] = [
        { role: "system", content: systemPrompt },
        { role: "user", content: "请生成学习计划" },
      ]

      const replyResult: LlmCallResult = await this.llm.call({
        messages: messages,
        maxTokens: 1024,
        timeoutMs: 60000,
      })
      const reply: string = replyResult.text ?? ''
      const titles: string[] = this.parsePlanTitles(reply)

      for (const title of titles) {
        const item: StudyPlanItem = new StudyPlanItem(title)
        if (this.dao !== null) {
          try {
            await this.dao.insert(item)
          } catch (e) {
            console.error("[StudyPlanViewModel.generatePlan] insert failed: " + (e as Error).message)
          }
        }
        this.items.push(item)
      }
      this.items = this.items.slice(0)
      this.refreshStudyPlanCache()
    } catch (e) {
      console.error("[StudyPlanViewModel.generatePlan] " + (e as Error).message)
    } finally {
      this.isLoading = false
    }
  }

  // ---- 解析 LLM JSON 数组（避免 RegExpMatchArray） ----
  private parsePlanTitles(raw: string): string[] {
    const start: number = raw.indexOf("[")
    const end: number = raw.lastIndexOf("]")
    if (start === -1 || end === -1 || start >= end) {
      return []
    }
    const json: string = raw.substring(start, end + 1)
    try {
      const parsed: string[] = JSON.parse(json) as string[]
      const result: string[] = []
      for (const item of parsed) {
        if (typeof item === "string" && item.trim().length > 0) {
          result.push(item.trim())
        }
      }
      return result
    } catch (e) {
      console.error("[StudyPlanViewModel.parsePlanTitles] " + (e as Error).message)
      return []
    }
  }

  private refreshStudyPlanCache(): void {
    UiDataCacheService.bumpStudyPlanVersion()
    UiDataCacheService.setStudyPlanSnapshot(this.items)
  }
}
