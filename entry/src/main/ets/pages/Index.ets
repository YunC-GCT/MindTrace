// ============================================================================
//  pages/Index.ets — 主容器装配层
//  ----------------------------------------------------------------------------
//  职责: 5 Tab 导航编排 + 全局浮层调度 (委托 OverlayService)
//  依赖: TabBar, OverlayService, AgentFloatWindow, WebKeepAlive,
//       NoteDetailRenderBenchmarkHost, NoteDetailBenchmarkLaunch
//  ============================================================================

import { BG_DARK } from "common"
import { HomePage } from "./Home/HomePage"
import { NotesPage } from "./Notes/NotesPage"
import { ReviewPage } from "./Review/ReviewPage"
import { ProfilePage } from "./Profile/ProfilePage"
import { TabBar } from "./MainTabs/TabBar"
import { AgentFloatWindow } from "../overlays/AgentFloatWindow/AgentFloatWindow"
import { KeyboardAvoidMode } from "@kit.ArkUI"
import { OverlayService } from "../services/OverlayService"
import { WebKeepAlive } from "../shared/atoms/WebKeepAlive"
import { WEB_KEEP_ALIVE_EXPERIMENT_KEY } from "../services/WebKeepAliveExperiment"
import {
  NOTE_DETAIL_BENCHMARK_CONFIG_KEY,
  NoteDetailBenchmarkLaunchConfig,
} from "../services/NoteDetailBenchmarkLaunch"
import { NoteDetailRenderBenchmarkHost } from "../benchmark/NoteDetailRenderBenchmarkHost"

const overlays = new OverlayService();

@Entry
@Component
struct Index {
  @State cur: number = 0
  @State pendingImageUri: string = ""
  @State lastContentIndex: number = 0
  @StorageLink('activeOverlay') activeOverlay: string = '';
  @StorageLink(WEB_KEEP_ALIVE_EXPERIMENT_KEY) webKeepAliveExperimentEnabled: boolean = false;
  @StorageLink(NOTE_DETAIL_BENCHMARK_CONFIG_KEY)
  benchmarkConfig: NoteDetailBenchmarkLaunchConfig = NoteDetailBenchmarkLaunchConfig.disabled();
  private tc: TabsController = new TabsController()

  aboutToAppear(): void {
    try { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE); } catch (e) {}
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
            TabContent() {
              HomePage({
                onGoCamera: (): void => { overlays.open('camera') },
                onGoReview: (): void => { this.cur = 3; this.tc.changeIndex(3) },
              })
            }
            TabContent() { NotesPage() }
            TabContent() {
              Column().width("100%").height("100%").backgroundColor(BG_DARK)
            }
            TabContent() {
              ReviewPage({
                onGoAI: (): void => { overlays.open('float') },
              })
            }
            TabContent() { ProfilePage() }
          }
          .barHeight(0).layoutWeight(1).scrollable(false)
          .onChange((i: number): void => {
            if (i === 2) {
              overlays.open('float');
              this.cur = this.lastContentIndex;
              this.tc.changeIndex(this.lastContentIndex);
              return;
            }
            this.cur = i;
            this.lastContentIndex = i;
          })

          TabBar({
            cur: this.cur,
            onTabChange: (i: number): void => { this.cur = i; this.tc.changeIndex(i) },
            onAiTap: (): void => { overlays.open('float') },
          })
        }
        .width("100%").height("100%").backgroundColor(BG_DARK)

        // AgentFloatWindow
        AgentFloatWindow({
          show: this.activeOverlay === 'float',
          onClose: (): void => {
            overlays.close();
            this.pendingImageUri = "";
          },
          pendingImageUri: this.pendingImageUri,
        })
      }
    }
    .width("100%").height("100%")
  }
}
