// ============================================================================
//  pages/Notes/NotesPage.ets — 笔记页 (5 Tab 之一)
//  ----------------------------------------------------------------------------
//  组件层: Page (D3 spec 012)
//  允许依赖: common 令牌/模型 · viewmodels · services · shared/* · 本目录组件
//  禁止依赖: database/dao 实现 · agents 内部实现 · 网络层直调
//  依赖: NotesViewModel · NotesHeader · NotesEmptyState · NotesSummaryPanel ·
//        SubjectGrid · SubjectViewToggle
// ============================================================================

import { BG_DARK, TEXT, S_4, S_5, F_BASE, W_SEMIBOLD, Toast } from "common"
import { promptAction, router } from "@kit.ArkUI"
import { NotesHeader } from "./NotesHeader"
import { NotesEmptyState } from "./NotesEmptyState"
import { NotesSummaryPanel } from "./NotesSummaryPanel"
import { SubjectGrid } from "./SubjectGrid"
import { SubjectViewToggle } from "./SubjectViewToggle"
import { NotesViewModel } from "../../viewmodels/NotesViewModel"

@Component
export struct NotesPage {
  @StorageProp("statusBarHeight") sbh: number = 0
  @StorageProp("notesVersion") @Watch("onNotesVersionChange") notesVersion: number = 0
  @State vm: NotesViewModel = new NotesViewModel()
  @State subjectViewMode: string = "block"
  private loadedNotesVersion: number = -1
  private loadingNotesVersion: number = -1

  aboutToAppear(): void {
    if (AppStorage.get<number>("notesVersion") === undefined) {
      AppStorage.setOrCreate("notesVersion", 0)
    }
    this.reloadNotes()
  }

  onPageShow(): void {
    this.reloadNotes()
  }

  onNotesVersionChange(): void {
    this.reloadNotes()
  }

  private reloadNotes = (): void => {
    const version: number = AppStorage.get<number>("notesVersion") ?? 0
    if (this.loadedNotesVersion === version || this.loadingNotesVersion === version) {
      return
    }
    this.loadingNotesVersion = version
    this.vm.loadNotes(getContext(this)).then((ok: boolean): void => {
      if (ok) {
        this.loadedNotesVersion = version
      } else {
        try { promptAction.showToast({ message: Toast.NOTE_LOAD_FAILED, duration: 1500 }) } catch (_e) {}
      }
    }).finally((): void => {
      if (this.loadingNotesVersion === version) {
        this.loadingNotesVersion = -1
      }
    })
  }

  private openSubject = (subject: string): void => {
    router.pushUrl({
      url: "pages/Notes/SubjectDetailPage",
      params: { subject: subject },
    })
  }

  private changeSubjectViewMode = (mode: string): void => {
    this.subjectViewMode = mode
  }

  private showSearchTodo = (): void => {
    try { promptAction.showToast({ message: "\u641c\u7d22\u529f\u80fd\u5f00\u53d1\u4e2d", duration: 1500 }) } catch (_e) {}
  }

  build() {
    Column() {
      NotesHeader({
        statusBarHeight: this.sbh,
        subjectCount: this.vm.subjectGroups.length,
        totalCount: this.vm.notes.length,
        onSearchTap: this.showSearchTodo,
      })

      if (this.vm.notes.length === 0) {
        NotesEmptyState()
      } else {
        Column() {
          NotesSummaryPanel({
            totalCount: this.vm.notes.length,
            subjectCount: this.vm.subjectGroups.length,
            weeklyNewCount: this.vm.weeklyNewCount,
            groups: this.vm.subjectGroups,
          })
            .margin({ left: S_5, right: S_5, top: 0, bottom: S_4 })

          Row() {
            Text("学科")
              .fontSize(F_BASE)
              .fontWeight(W_SEMIBOLD)
              .fontColor(TEXT)
            Blank()
            SubjectViewToggle({
              mode: this.subjectViewMode,
              onChange: this.changeSubjectViewMode,
            })
          }
          .width("100%")
          .padding({ left: S_5, right: S_5, bottom: S_4 })
          .alignItems(VerticalAlign.Center)

          SubjectGrid({
            groups: this.vm.subjectGroups,
            viewMode: this.subjectViewMode,
            onSelect: this.openSubject,
          })
        }
        .width("100%")
        .layoutWeight(1)
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
