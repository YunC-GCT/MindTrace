// ============================================================================
//  pages/Review/ReviewPage.ets — 复习页 (5 Tab 之一)
//  ----------------------------------------------------------------------------
//  组件层: Page (D3 spec 012)
//  允许依赖: common 令牌/模型 · viewmodels · services · shared/* · 本目录组件
//  禁止依赖: database/dao 实现 · agents 内部实现 · 网络层直调
//  依赖: StudyPlanViewModel · UiDataCacheService · ReviewGraphView ·
//        ReviewPlanView · ReviewTabSwitch · shared/atoms/AppIcon
// ============================================================================
import { BG_DARK, BORDER, GLASS_8, MINT, S_2, S_3, S_5, R_LG, F_BASE, StudyPlanItem, Toast } from "common"
import { promptAction } from "@kit.ArkUI"
import { StudyPlanViewModel } from "../../viewmodels/StudyPlanViewModel"
import { ReviewGraphView } from "./ReviewGraphView"
import { ReviewPlanView } from "./ReviewPlanView"
import { ReviewTabSwitch } from "./ReviewTabSwitch"
import { AppIcon } from "../../shared/atoms/AppIcon"
import { UiDataCacheService } from "../../services/UiDataCacheService"

const REVIEW_TAB_PLAN: number = 0
const REVIEW_TAB_GRAPH: number = 1

@Component
export struct ReviewPage {
  @StorageProp("statusBarHeight") sbh: number = 0
  @State activeTab: number = REVIEW_TAB_PLAN
  @State vm: StudyPlanViewModel = new StudyPlanViewModel()
  @State liveIds: string[] = []
  @State planOrderIds: string[] = []
  @State showAddPlan: boolean = false
  @State addTitle: string = ""
  @State previewItems: StudyPlanItem[] = [
    new StudyPlanItem("矩阵行列式计算", 1),
    new StudyPlanItem("极限 ε-δ 定义", 2),
    new StudyPlanItem("线性方程组基础变形", 2),
  ]
  private loadedPlanVersion: number = -1
  private loadingPlanVersion: number = -1
  onGoAI: () => void = (): void => {}

  aboutToAppear(): void {
    this.reloadPlans()
  }

  onPageShow(): void {
    this.reloadPlans()
  }

  private reloadPlans(): void {
    const version: number = UiDataCacheService.currentStudyPlanVersion()
    if (this.loadedPlanVersion === version || this.loadingPlanVersion === version) {
      return
    }
    this.loadingPlanVersion = version
    this.vm.init(getContext(this)).then((): void => {
      if (this.vm.initError) {
        try { promptAction.showToast({ message: Toast.PLAN_LOAD_FAILED, duration: 1500 }) } catch (_e) {}
      }
      if (this.vm.initError) {
        return
      }
      this.loadedPlanVersion = version
      this.syncPlanOrder()
      this.pruneLiveQueue()
    }).finally((): void => {
      if (this.loadingPlanVersion === version) {
        this.loadingPlanVersion = -1
      }
    })
  }

  private pruneLiveQueue(): void {
    if (this.liveIds.length > 0) {
      this.liveIds = this.liveIds.filter((id: string): boolean => this.hasActivePlan(id))
    }
  }

  private hasActivePlan(id: string): boolean {
    return this.activeItems().findIndex((item: StudyPlanItem): boolean => item.id === id && !item.isDone) >= 0
  }

  private rawActiveItems(): StudyPlanItem[] {
    const realItems: StudyPlanItem[] = this.vm.items.filter((item: StudyPlanItem): boolean => !item.isDone)
    return realItems.length > 0 ? realItems : this.previewItems
  }

  private activeItems(): StudyPlanItem[] {
    const rawItems: StudyPlanItem[] = this.rawActiveItems()
    const result: StudyPlanItem[] = []
    this.planOrderIds.forEach((id: string): void => {
      const found: StudyPlanItem | undefined = rawItems.find((item: StudyPlanItem): boolean => item.id === id)
      if (found !== undefined) {
        result.push(found)
      }
    })
    rawItems.forEach((item: StudyPlanItem): void => {
      if (result.findIndex((candidate: StudyPlanItem): boolean => candidate.id === item.id) < 0) {
        result.push(item)
      }
    })
    return result
  }

  private syncPlanOrder(): void {
    const rawItems: StudyPlanItem[] = this.rawActiveItems()
    const nextIds: string[] = []
    this.planOrderIds.forEach((id: string): void => {
      if (rawItems.findIndex((item: StudyPlanItem): boolean => item.id === id) >= 0) {
        nextIds.push(id)
      }
    })
    rawItems.forEach((item: StudyPlanItem): void => {
      if (nextIds.indexOf(item.id) < 0) {
        nextIds.push(item.id)
      }
    })
    this.planOrderIds = nextIds
  }

  private addReviewPlan = (): void => {
    this.activeTab = REVIEW_TAB_PLAN
    this.showAddPlan = !this.showAddPlan
    if (!this.showAddPlan) {
      this.addTitle = ""
    }
  }

  private changeAddTitle = (value: string): void => {
    this.addTitle = value
  }

  private cancelAddPlan = (): void => {
    this.addTitle = ""
    this.showAddPlan = false
  }

  private submitAddPlan = (): void => {
    const trimmed: string = this.addTitle.trim()
    if (trimmed.length === 0) {
      try { promptAction.showToast({ message: Toast.PLAN_INPUT_REQUIRED, duration: 1200 }) } catch (_e) {}
      return
    }
    this.vm.newTitle = trimmed
    this.vm.addItem().then((): void => {
      this.addTitle = ""
      this.showAddPlan = false
      this.syncPlanOrder()
      this.pruneLiveQueue()
    })
  }

  private changeTab = (tab: number): void => {
    this.activeTab = tab
  }

  private addToLive = (item: StudyPlanItem): void => {
    if (this.liveIds.indexOf(item.id) >= 0) {
      return
    }
    const nextIds: string[] = this.liveIds.filter((id: string): boolean => this.hasActivePlan(id))
    nextIds.push(item.id)
    this.liveIds = nextIds
    try { promptAction.showToast({ message: Toast.ENQUEUED_REALTIME, duration: 1000 }) } catch (_e) {}
  }

  private addToLiveTop = (item: StudyPlanItem): void => {
    const nextIds: string[] = this.liveIds
      .filter((id: string): boolean => this.hasActivePlan(id) && id !== item.id)
    nextIds.unshift(item.id)
    this.liveIds = nextIds
    try { promptAction.showToast({ message: Toast.MOVED_TO_REALTIME_TOP, duration: 1000 }) } catch (_e) {}
  }

  private moveLivePlan = (item: StudyPlanItem, direction: number): void => {
    const ids: string[] = this.liveIds.filter((id: string): boolean => this.hasActivePlan(id))
    const index: number = ids.indexOf(item.id)
    const target: number = index + direction
    if (index < 0 || target < 0 || target >= ids.length) {
      return
    }
    const moved: string = ids[index]
    ids[index] = ids[target]
    ids[target] = moved
    this.liveIds = ids
  }

  private moveReviewPlan = (item: StudyPlanItem, direction: number): void => {
    this.syncPlanOrder()
    const reviewIds: string[] = this.activeItems()
      .filter((candidate: StudyPlanItem): boolean => this.liveIds.indexOf(candidate.id) < 0)
      .map((candidate: StudyPlanItem): string => candidate.id)
    const index: number = reviewIds.indexOf(item.id)
    const target: number = index + direction
    if (index < 0 || target < 0 || target >= reviewIds.length) {
      return
    }
    const sourcePos: number = this.planOrderIds.indexOf(reviewIds[index])
    const targetPos: number = this.planOrderIds.indexOf(reviewIds[target])
    if (sourcePos < 0 || targetPos < 0) {
      return
    }
    const nextIds: string[] = this.planOrderIds.slice(0)
    const moved: string = nextIds[sourcePos]
    nextIds[sourcePos] = nextIds[targetPos]
    nextIds[targetPos] = moved
    this.planOrderIds = nextIds
  }

  private removeFromLive = (item: StudyPlanItem): void => {
    this.liveIds = this.liveIds.filter((id: string): boolean => id !== item.id)
    const nextIds: string[] = this.planOrderIds.filter((id: string): boolean => id !== item.id)
    nextIds.unshift(item.id)
    this.planOrderIds = nextIds
    try { promptAction.showToast({ message: Toast.MOVED_TO_REVIEW, duration: 1000 }) } catch (_e) {}
  }

  private crossToReview = (item: StudyPlanItem): void => {
    this.liveIds = this.liveIds.filter((id: string): boolean => id !== item.id)
    const nextIds: string[] = this.planOrderIds.filter((id: string): boolean => id !== item.id)
    nextIds.unshift(item.id)
    this.planOrderIds = nextIds
    try { promptAction.showToast({ message: Toast.MOVED_TO_REVIEW, duration: 1000 }) } catch (_e) {}
  }

  private deletePlan = (item: StudyPlanItem): void => {
    this.liveIds = this.liveIds.filter((id: string): boolean => id !== item.id)
    this.planOrderIds = this.planOrderIds.filter((id: string): boolean => id !== item.id)
    if (this.vm.items.length === 0) {
      this.previewItems = this.previewItems.filter((candidate: StudyPlanItem): boolean => candidate.id !== item.id)
      try { promptAction.showToast({ message: Toast.PLAN_DELETED, duration: 1000 }) } catch (_e) {}
      return
    }
    this.vm.deleteItem(item).then((): void => {
      this.pruneLiveQueue()
      try { promptAction.showToast({ message: Toast.PLAN_DELETED, duration: 1000 }) } catch (_e) {}
    })
  }

  build() {
    Column() {
      Row()
        .width("100%")
        .height(this.sbh)
        .backgroundColor(BG_DARK)

      Row({ space: S_3 }) {
        ReviewTabSwitch({
          activeTab: this.activeTab,
          onChange: this.changeTab,
        })
          .layoutWeight(1)

        if (this.activeTab === REVIEW_TAB_PLAN) {
          Button() {
            AppIcon({ name: this.showAddPlan ? "close" : "plus", iconSize: F_BASE + 6, color: MINT, strokeWidth: 1.8 })
          }
          .width(40)
          .height(40)
          .borderRadius(R_LG)
          .backgroundColor(GLASS_8)
          .border({ width: 0.5, color: BORDER })
          .onClick(this.addReviewPlan)
        }
      }
      .width("100%")
      .padding({ left: S_5, right: S_5, top: S_3, bottom: S_2 })
      .alignItems(VerticalAlign.Center)

      if (this.activeTab === REVIEW_TAB_PLAN) {
        ReviewPlanView({
          vm: this.vm,
          planItems: this.activeItems(),
          liveIds: this.liveIds,
          showAddPlan: this.showAddPlan,
          addTitle: this.addTitle,
          onPromote: this.addToLive,
          onPromoteTop: this.addToLiveTop,
          onDemote: this.removeFromLive,
          onCrossToReview: this.crossToReview,
          onMoveLive: this.moveLivePlan,
          onMoveReview: this.moveReviewPlan,
          onRemovePlan: this.deletePlan,
          onAddTitleChange: this.changeAddTitle,
          onSubmitAdd: this.submitAddPlan,
          onCancelAdd: this.cancelAddPlan,
        })
      } else {
        ReviewGraphView({ onGoAI: this.onGoAI })
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
