// ============================================================================
//  services/StudyPlanService.ets — 学习计划 AI 生成服务 (F2 小步先修)
//  ----------------------------------------------------------------------------
//  职责: 生成学习计划标题 (LLM 调用 + JSON 数组解析), 供 StudyPlanViewModel 调用。
//  边界: 只负责"生成", 不做持久化 — insert 仍由 ViewModel 的 UI-CRUD 路径执行;
//        F2 长期 (写路径统一, 见 agent-tools inventory 2026-09-06) 时再收敛
//        insert + schema 校验。
//  背景: inventory F2 — StudyPlanViewModel 越层直写 DAO + LLM, AI 生成路径抽到
//        Service 层 (AGENTS.md 架构表: ViewModel = UI state, Service = 编排)。
//
//  ArkTS 1.1 strict: 显式类型, 无 Record<>, 无 RegExpMatchArray
//  ============================================================================

import { LlmClient } from "common"
import type { ChatMessage, LlmCallResult } from "common"

export class StudyPlanService {
  // 生成学习计划标题; 解析失败返回空数组 (与原 ViewModel 行为一致)
  static async generateTitles(knownTitles: string[]): Promise<string[]> {
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

    const client: LlmClient = new LlmClient()
    const replyResult: LlmCallResult = await client.call({
      messages: messages,
      maxTokens: 1024,
      timeoutMs: 60000,
    })
    const reply: string = replyResult.text ?? ''
    return StudyPlanService.parsePlanTitles(reply)
  }

  // ---- 解析 LLM JSON 数组（避免 RegExpMatchArray） ----
  private static parsePlanTitles(raw: string): string[] {
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
      console.error("[StudyPlanService.parsePlanTitles] " + (e as Error).message)
      return []
    }
  }
}
