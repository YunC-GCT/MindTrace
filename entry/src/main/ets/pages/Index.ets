// ============================================================================
//  pages/Index.ets — 主容器装配层
//  ----------------------------------------------------------------------------
//  职责: 5 Tab 导航装配 + 全局浮层状态承载
//  依赖: TabBar, MainTabNavigation, 五个 TabContent 装配组件,
//       MainTabActions, AgentFloatWindow, WebKeepAlive,
//       NoteDetailRenderBenchmarkHost, NoteDetailBenchmarkLaunch
//  ============================================================================

import { BG_DARK } from "common"
import { TabBar } from "./MainTabs/TabBar"
import { MainTabNavigation } from "./MainTabs/MainTabNavigation"
import { MainTabActions } from "./MainTabs/MainTabActions"
import { buildHomeTabContent } from "./MainTabs/HomeTabContent"
import { buildNotesTabContent } from "./MainTabs/NotesTabContent"
import { buildAiTabContent } from "./MainTabs/AiTabContent"
import { buildReviewTabContent } from "./MainTabs/ReviewTabContent"
import { buildProfileTabContent } from "./MainTabs/ProfileTabContent"
import { AgentFloatWindow } from "../overlays/AgentFloatWindow/AgentFloatWindow"
import { KeyboardAvoidMode } from "@kit.ArkUI"
import { WebKeepAlive } from "../shared/atoms/WebKeepAlive"
import { WEB_KEEP_ALIVE_EXPERIMENT_KEY } from "../services/WebKeepAliveExperiment"
import {
  NOTE_DETAIL_BENCHMARK_CONFIG_KEY,
  NoteDetailBenchmarkLaunchConfig,
} from "../services/NoteDetailBenchmarkLaunch"
import { NoteDetailRenderBenchmarkHost } from "../benchmark/NoteDetailRenderBenchmarkHost"
import { noteDetailBackPressCoordinator } from "../overlays/NoteDetailOverlay/NoteDetailBackPressCoordinator"

const tabActions = new MainTabActions()

@Entry
@Component
struct Index {
  @State cur: number = 0
  @State pendingImageUri: string = ""
  @StorageLink('activeOverlay') activeOverlay: string = '';
  @StorageLink(WEB_KEEP_ALIVE_EXPERIMENT_KEY) webKeepAliveExperimentEnabled: boolean = false;
  @StorageLink(NOTE_DETAIL_BENCHMARK_CONFIG_KEY)
  benchmarkConfig: NoteDetailBenchmarkLaunchConfig = NoteDetailBenchmarkLaunchConfig.disabled();
  private tc: TabsController = new TabsController()
  private selectContent = (index: number): void => {
    this.cur = index
    this.tc.changeIndex(index)
  }
  private restoreContent = (index: number): void => {
    this.cur = index
    this.tc.changeIndex(index)
  }
  private openAssistant = (): void => { tabActions.openAssistant() }
  private navigation: MainTabNavigation = new MainTabNavigation({
    onSelectContent: (index: number): void => { this.selectContent(index) },
    onSystemSelectContent: (index: number): void => { this.restoreContent(index) },
    onOpenAssistant: (): void => { this.openAssistant() },
  })

  aboutToAppear(): void {
    try { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE); } catch (e) {}
  }

  onBackPress(): boolean {
    return noteDetailBackPressCoordinator.handleBack()
  }

  build() {
    Stack() {
      if (this.webKeepAliveExperimentEnabled) {
        WebKeepAlive()
      }
      if (this.benchmarkConfig.enabled) {
        NoteDetailRenderBenchmarkHost({ config: this.benchmarkConfig })
      } else {
        Column() {
          Tabs({ index: this.cur, controller: this.tc }) {
            buildHomeTabContent(
              (): void => { tabActions.openCamera() },
              (): void => { this.navigation.select(3) },
            )
            buildNotesTabContent()
            buildAiTabContent()
            buildReviewTabContent((): void => { this.navigation.openAssistant() })
            buildProfileTabContent()
          }
          .barHeight(0).layoutWeight(1).scrollable(false)
          .onChange((i: number): void => { this.navigation.onSystemIndexChanged(i) })

          TabBar({
            cur: this.cur,
            onTabChange: (i: number): void => { this.navigation.select(i) },
            onAiTap: (): void => { this.navigation.openAssistant() },
          })
        }
        .width("100%").height("100%").backgroundColor(BG_DARK)

        // AgentFloatWindow
        AgentFloatWindow({
          show: this.activeOverlay === 'float',
          onClose: (): void => {
            tabActions.closeOverlay();
            this.pendingImageUri = "";
          },
          pendingImageUri: this.pendingImageUri,
        })
      }
    }
    .width("100%").height("100%")
  }
}
