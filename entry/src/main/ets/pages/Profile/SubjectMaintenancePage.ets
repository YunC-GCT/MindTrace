// ============================================================================
//  pages/Profile/SubjectMaintenancePage.ets — 我的 → 学科整理
//  ----------------------------------------------------------------------------
//  页面层: Page (D3 spec 012)
//  职责: 把「学科归一 + 标题清洗」这件一次性程序变成用户随时可点的功能：
//        展示当前学科分布 → 用户点「开始整理」→ 立刻重跑一遍归一 →
//        显示归一了几条、原来的学科名并到了哪里、整理后的分布。
//  依赖: SubjectRepairService(预览/整理) · PageHeader(顶栏)
//  禁止依赖: database · agents 内部实现
//
//  数据流:
//   aboutToAppear → SubjectRepairService.preview → 学科分布
//   点击整理     → SubjectRepairService.repairNow → 报告(before/after/changes)
// ============================================================================

import {
  BG_CARD,
  BG_DARK,
  BORDER,
  DANGER,
  F_LG,
  F_MD,
  F_SM,
  GLASS_8,
  MINT,
  R_FULL,
  R_LG,
  S_1,
  S_2,
  S_3,
  S_4,
  S_5,
  S_6,
  TEXT,
  TEXT_2,
  TEXT_3,
  W_SEMIBOLD,
} from "common"
import { common } from "@kit.AbilityKit"
import { PageHeader } from "../AiSettings/PageHeader"
import {
  SubjectChange,
  SubjectRepairReport,
  SubjectRepairService,
  SubjectUsage,
} from "../../services/SubjectRepairService"

@Entry
@Component
struct SubjectMaintenancePage {
  @StorageProp("statusBarHeight") sbh: number = 0
  @State loading: boolean = true
  @State running: boolean = false
  @State before: SubjectUsage[] = []
  @State after: SubjectUsage[] = []
  @State changes: SubjectChange[] = []
  @State scanned: number = 0
  @State subjectFixed: number = 0
  @State titleFixed: number = 0
  @State failed: number = 0
  @State hasRun: boolean = false
  @State errorText: string = ""

  aboutToAppear(): void {
    this.reloadPreview()
  }

  private reloadPreview(): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.loading = true
    SubjectRepairService.preview(context).then((usages: SubjectUsage[]): void => {
      this.before = usages
      this.loading = false
    }).catch((e: Error): void => {
      this.errorText = "读取学科分布失败：" + e.message
      this.loading = false
    })
  }

  private totalOf(usages: SubjectUsage[]): number {
    let total: number = 0
    for (let i = 0; i < usages.length; i++) {
      total += usages[i].count
    }
    return total
  }

  private startRepair(): void {
    if (this.running) {
      return
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.running = true
    this.errorText = ""
    SubjectRepairService.repairNow(context).then((report: SubjectRepairReport): void => {
      this.scanned = report.scanned
      this.subjectFixed = report.subjectFixed
      this.titleFixed = report.titleFixed
      this.failed = report.failed
      this.before = report.before
      this.after = report.after
      this.changes = report.changes
      this.hasRun = true
      this.running = false
    }).catch((e: Error): void => {
      this.errorText = "整理失败：" + e.message
      this.running = false
    })
  }

  @Builder
  subjectChips(usages: SubjectUsage[], tone: string) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(usages, (item: SubjectUsage): void => {
        Text(`${item.subject} · ${item.count}`)
          .fontSize(F_SM)
          .fontColor(tone)
          .padding({ left: S_3, right: S_3, top: S_1 + 2, bottom: S_1 + 2 })
          .borderRadius(R_FULL)
          .backgroundColor(GLASS_8)
          .margin({ right: S_2, bottom: S_2 })
      }, (item: SubjectUsage): string => item.subject)
    }
    .width("100%")
  }

  build() {
    Column() {
      Row()
        .width("100%")
        .height(this.sbh)
        .backgroundColor(BG_DARK)

      PageHeader({ title: "学科整理" })

      Scroll() {
        Column({ space: S_4 }) {
          // ---- 说明 ----
          Column({ space: S_2 }) {
            Text("把已有的笔记重新归到更合适的学科")
              .fontSize(F_LG)
              .fontWeight(W_SEMIBOLD)
              .fontColor(TEXT)
              .width("100%")
            Text("同一门课在库里被写成好几个名字时（最优化 / 最优化方法 / 数学（优化理论/运筹学）），"
              + "这里会把它们并到内置学科里，顺手剥掉标题上的复核标记。已经规范的笔记不会被改动。")
              .fontSize(F_SM)
              .fontColor(TEXT_2)
              .width("100%")
          }
          .width("100%")
          .padding(S_4)
          .backgroundColor(BG_CARD)
          .borderRadius(R_LG)
          .border({ width: 1, color: BORDER })

          // ---- 当前分布 ----
          Column({ space: S_3 }) {
            Row() {
              Text("当前学科分布")
                .fontSize(F_MD)
                .fontWeight(W_SEMIBOLD)
                .fontColor(TEXT)
                .layoutWeight(1)
              Text(this.loading ? "读取中…" : `${this.totalOf(this.before)} 条 · ${this.before.length} 门`)
                .fontSize(F_SM)
                .fontColor(TEXT_3)
            }
            .width("100%")

            if (this.before.length > 0) {
              this.subjectChips(this.before, TEXT_2)
            } else if (!this.loading) {
              Text("库里还没有笔记")
                .fontSize(F_SM)
                .fontColor(TEXT_3)
                .width("100%")
            }
          }
          .width("100%")
          .padding(S_4)
          .backgroundColor(BG_CARD)
          .borderRadius(R_LG)
          .border({ width: 1, color: BORDER })

          // ---- 操作 ----
          Button(this.running ? "正在整理…" : (this.hasRun ? "再整理一次" : "开始整理"))
            .fontSize(F_MD)
            .fontColor(TEXT)
            .height(S_5 + S_4)
            .width("100%")
            .backgroundColor(GLASS_8)
            .borderRadius(R_FULL)
            .enabled(!this.running && !this.loading)
            .onClick((): void => this.startRepair())

          if (this.errorText.length > 0) {
            Text(this.errorText)
              .fontSize(F_SM)
              .fontColor(DANGER)
              .width("100%")
          }

          // ---- 结果 ----
          if (this.hasRun) {
            Column({ space: S_3 }) {
              Row() {
                Text("整理结果")
                  .fontSize(F_MD)
                  .fontWeight(W_SEMIBOLD)
                  .fontColor(TEXT)
                  .layoutWeight(1)
                Text(`扫描 ${this.scanned} 条`)
                  .fontSize(F_SM)
                  .fontColor(TEXT_3)
              }
              .width("100%")

              Row({ space: S_4 }) {
                Text(`学科归一 ${this.subjectFixed} 条`).fontSize(F_SM).fontColor(MINT)
                Text(`标题清理 ${this.titleFixed} 条`).fontSize(F_SM).fontColor(MINT)
                if (this.failed > 0) {
                  Text(`失败 ${this.failed} 条`).fontSize(F_SM).fontColor(DANGER)
                }
              }
              .width("100%")

              if (this.changes.length > 0) {
                Text("合并明细")
                  .fontSize(F_SM)
                  .fontColor(TEXT_3)
                  .width("100%")
                  .margin({ top: S_2 })
                ForEach(this.changes, (item: SubjectChange): void => {
                  Row({ space: S_2 }) {
                    Text(item.from)
                      .fontSize(F_SM)
                      .fontColor(TEXT_2)
                      .layoutWeight(1)
                    Text("→")
                      .fontSize(F_SM)
                      .fontColor(TEXT_3)
                    Text(item.to)
                      .fontSize(F_SM)
                      .fontColor(MINT)
                    Text(`×${item.count}`)
                      .fontSize(F_SM)
                      .fontColor(TEXT_3)
                  }
                  .width("100%")
                }, (item: SubjectChange): string => `${item.from}->${item.to}`)
              } else {
                Text("这次没有需要归一的学科，已经是最干净的状态。")
                  .fontSize(F_SM)
                  .fontColor(TEXT_3)
                  .width("100%")
              }

              Text("整理后分布")
                .fontSize(F_SM)
                .fontColor(TEXT_3)
                .width("100%")
                .margin({ top: S_2 })
              this.subjectChips(this.after, MINT)
            }
            .width("100%")
            .padding(S_4)
            .backgroundColor(BG_CARD)
            .borderRadius(R_LG)
            .border({ width: 1, color: BORDER })
          }

          Text("提示：整理只改学科名和标题上的复核标记，正文内容一个字都不动。")
            .fontSize(F_SM)
            .fontColor(TEXT_3)
            .width("100%")
            .margin({ top: S_2 })
        }
        .width("100%")
        .padding({ left: S_4, right: S_4, top: S_2, bottom: S_6 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      // Scroll 默认把内容垂直居中；内容不满一屏时会飘在中间，这里钉回顶部
      .align(Alignment.Top)
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
