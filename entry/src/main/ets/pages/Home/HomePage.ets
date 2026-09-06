// ============================================================================
//  pages/Home/HomePage.ets — 首页 (5 Tab 之一)
//  ----------------------------------------------------------------------------
//  组件层: Page (D3 spec 012)
//  允许依赖: common 令牌/模型 · viewmodels · services · shared/* · 本目录组件
//  禁止依赖: database/dao 实现 · agents 内部实现 · 网络层直调
//  依赖: HomeViewModel · FloatingButton · HeroBanner · HomeCollapsedReview ·
//        ReminderBanner · HomeTopBar · HomeRecentNotes · NoteDetailOverlay · NoteItemMapper
// ============================================================================

import { BG_DARK, DUR_SLOW, NoteItem, KnowledgeUnit } from "common"
import type { ReminderFacade } from "common"
import { promptAction } from "@kit.ArkUI"
import { getReminderFacade } from "../../kit/ReminderFacadeImpl"
import { FloatingButton } from "./FloatingButton"
import { HeroBanner } from "./HeroBanner"
import { HomeCollapsedReview } from "./HomeCollapsedReview"
import { ReminderBanner } from "./ReminderBanner"
import { NoteDetailOverlay } from "../../overlays/NoteDetailOverlay/NoteDetailOverlay"
import { HomeTopBar } from "./HomeTopBar"
import { HomeRecentNotes } from "./HomeRecentNotes"
import { HomeViewModel } from "../../viewmodels/HomeViewModel"
import { unitToNoteItem } from "../../utils/NoteItemMapper"
import { invalidateDetailRender } from "../../overlays/NoteDetailOverlay/model/DetailRenderCache"

@Component
export struct HomePage {
  @StorageProp("statusBarHeight") sbh: number = 0
  @StorageProp('notesVersion') @Watch('onNotesVersionChange') notesVersion: number = 0
  @State vm: HomeViewModel = new HomeViewModel()
  @State selectedNote: NoteItem | null = null
  @State reviewRingCollapsed: boolean = false
  @State selectedUnit: KnowledgeUnit | null = null
  @State creatingNote: boolean = false
  private loadedNotesVersion: number = -1
  private loadingNotesVersion: number = -1
  onGoCamera: () => void = (): void => {}
  onGoReview: () => void = (): void => {}

  aboutToAppear(): void {
    this.reloadHome()
  }

  onPageShow(): void {
    this.reloadHome()
  }

  onNotesVersionChange(): void {
    this.reloadHome()
  }

  private reloadHome(): void {
    const version: number = AppStorage.get<number>('notesVersion') ?? 0
    if (this.loadedNotesVersion === version || this.loadingNotesVersion === version) {
      return
    }
    this.loadingNotesVersion = version
    this.vm.init(getContext(this)).then((ok: boolean): void => {
      if (ok) {
        this.loadedNotesVersion = version
      } else {
        try { promptAction.showToast({ message: "Failed to load notes", duration: 1500 }) } catch (_e) {}
      }
    }).finally((): void => {
      if (this.loadingNotesVersion === version) {
        this.loadingNotesVersion = -1
      }
    })
  }

  private openDetail = (note: NoteItem): void => {
    this.creatingNote = false
    this.selectedNote = note
    this.selectedUnit = null
    this.vm.loadNote(getContext(this), note.rawId).then((unit: KnowledgeUnit | null): void => {
      if (this.selectedNote !== null && this.selectedNote.id === note.id) {
        this.selectedUnit = unit
      }
    })
  }

  private openCreate = (): void => {
    this.selectedNote = null
    this.selectedUnit = null
    this.creatingNote = true
  }

  private closeDetail = (): void => {
    this.selectedNote = null
    this.selectedUnit = null
  }

  private handleSaved = (unit: KnowledgeUnit): void => {
    const note: NoteItem = unitToNoteItem(unit)
    this.creatingNote = false
    this.selectedNote = note
    this.selectedUnit = unit
  }

  private deleteNote = async (id: string): Promise<void> => {
    const ok: boolean = await this.vm.deleteNote(getContext(this), id)
    if (ok) {
      invalidateDetailRender(id)
      this.selectedNote = null
      this.selectedUnit = null
      try { promptAction.showToast({ message: "Note deleted", duration: 1200 }) } catch (_e) {}
    } else {
      try { promptAction.showToast({ message: "Delete failed", duration: 1500 }) } catch (_e) {}
    }
  }

  // F3 最小闭环: 组合根注入的 ReminderFacade → 安排 1 分钟后的复习提醒 (演示)
  private async scheduleReviewReminder(): Promise<void> {
    const facade: ReminderFacade | null = getReminderFacade()
    if (facade === null) {
      try { promptAction.showToast({ message: "提醒服务未就绪", duration: 1500 }) } catch (_e) {}
      return
    }
    try {
      await facade.scheduleReviewReminder({
        unitId: "home-review-demo",
        title: "MindTrace 复习提醒",
        subtitle: "到时间啦, 回顾你的笔记",
        fireAt: Date.now() + 60 * 1000,
      })
      try { promptAction.showToast({ message: "已设置 1 分钟后的复习提醒", duration: 2000 }) } catch (_e) {}
    } catch (e) {
      try { promptAction.showToast({ message: "提醒设置失败", duration: 1500 }) } catch (_e) {}
    }
  }

  private collapseReviewRing(): void {
    if (this.reviewRingCollapsed) {
      return
    }
    animateTo({ duration: DUR_SLOW, curve: Curve.FastOutSlowIn }, (): void => {
      this.reviewRingCollapsed = true
    })
  }

  private expandReviewRing(): void {
    if (!this.reviewRingCollapsed) {
      return
    }
    animateTo({ duration: DUR_SLOW, curve: Curve.FastOutSlowIn }, (): void => {
      this.reviewRingCollapsed = false
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        HomeTopBar({
          statusBarHeight: this.sbh,
          showReminder: true,
          onSetReminder: (): void => { this.scheduleReviewReminder() },
        })
        if (this.reviewRingCollapsed) {
          HomeCollapsedReview({
            avg: this.vm.avg,
            notesCount: this.vm.notes.length,
            todayCount: this.vm.today,
            dateText: this.vm.dateText,
            onGoReview: (): void => { this.onGoReview() },
          })
          .gesture(
            PanGesture({ direction: PanDirection.Vertical })
              .onActionEnd((event: GestureEvent): void => {
                if (event.offsetY > 24) {
                  this.expandReviewRing()
                }
              })
          )
        } else {
          HeroBanner({
            greeting: this.vm.greeting,
            dateText: this.vm.dateText,
            avg: this.vm.avg,
            notesCount: this.vm.notes.length,
            todayCount: this.vm.today,
            onGoReview: (): void => { this.onGoReview() },
          })
          .gesture(
            PanGesture({ direction: PanDirection.Vertical })
              .onActionEnd((event: GestureEvent): void => {
                if (event.offsetY < -18) {
                  this.collapseReviewRing()
                }
              })
          )
        }

        if (!this.reviewRingCollapsed && this.vm.notes.length < 3) {
          ReminderBanner({ notesCount: this.vm.notes.length })
            .gesture(
              PanGesture({ direction: PanDirection.Vertical })
                .onActionEnd((event: GestureEvent): void => {
                  if (event.offsetY < -18) {
                    this.collapseReviewRing()
                  }
                })
            )
        }

        HomeRecentNotes({
          notes: this.vm.notes,
          compact: this.reviewRingCollapsed,
          onSwipeUp: (): void => { this.collapseReviewRing() },
          onSelect: this.openDetail,
        })
      }
      .width("100%")
      .height("100%")
      .backgroundColor(BG_DARK)

      FloatingButton({ onTap: this.openCreate })

      if (this.creatingNote) {
        NoteDetailOverlay({
          isCreating: true,
          units: this.vm.units,
          onClose: (): void => { this.creatingNote = false },
          onSaved: this.handleSaved,
        })
      }

      if (this.selectedNote !== null) {
        NoteDetailOverlay({
          note: this.selectedNote!,
          unit: this.selectedUnit,
          units: this.vm.units,
          onClose: this.closeDetail,
          onDelete: this.deleteNote,
          onSaved: this.handleSaved,
        })
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
