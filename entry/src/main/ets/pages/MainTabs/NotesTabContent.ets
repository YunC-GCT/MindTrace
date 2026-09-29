/**
 * NotesTabContent.ets — 笔记 TabContent 装配
 *
 * 路径: entry/src/main/ets/pages/MainTabs/NotesTabContent.ets
 * 职责: 将笔记页面装配到 Tabs 内容项。
 * 依赖: NotesPage
 *
 * 数据流:
 *   Tabs → NotesPage
 */

import { NotesPage } from "../Notes/NotesPage"

@Builder
export function buildNotesTabContent() {
  TabContent() {
    NotesPage()
  }
}
