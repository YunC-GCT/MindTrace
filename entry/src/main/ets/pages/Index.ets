// ============================================================================
//  pages/Index.ets — 主容器装配层
//  ----------------------------------------------------------------------------
//  职责: 5 Tab 导航编排 + 全局浮层调度 (委托 OverlayService)
//  依赖: TabBar, OverlayService, CameraOverlay, AgentFloatWindow
//  ============================================================================

import { BG_DARK } from "common"
import { HomePage } from "./Home/HomePage"
import { NotesPage } from "./Notes/NotesPage"
import { ReviewPage } from "./Review/ReviewPage"
import { ProfilePage } from "./Profile/ProfilePage"
import { TabBar } from "./MainTabs/TabBar"
import { AgentFloatWindow } from "../overlays/AgentFloatWindow/AgentFloatWindow"
import { CameraOverlay } from "../overlays/CameraOverlay/CameraOverlay"
import { ErrorBanner } from "../shared/atoms/ErrorBanner"
import { KeyboardAvoidMode } from "@kit.ArkUI"
import { OverlayService } from "../services/OverlayService"

const overlays = new OverlayService();

@Entry
@Component
struct Index {
  @State cur: number = 0
  @State pendingImageUri: string = ""
  @State lastContentIndex: number = 0
  @StorageLink('activeOverlay') activeOverlay: string = '';
  private tc: TabsController = new TabsController()

  aboutToAppear(): void {
    try { this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE); } catch (e) {}
  }

  // 拍照/选图完成 → 图片传给 AI 浮窗
  private onCameraConfirm = (uri: string, _src: "camera" | "album"): void => {
    overlays.close(); // 关相机
    this.pendingImageUri = "";
    setTimeout((): void => {
      this.pendingImageUri = uri;
      overlays.open('float'); // 开浮窗
    }, 0);
  }

  build() {
    Stack() {
      // 全局错误横幅: 订阅 ErrorBus, 三档 severity (info/warn/error), 不持久化
      ErrorBanner()

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

      // CameraOverlay
      if (this.activeOverlay === 'camera') {
        CameraOverlay({
          onClose: (): void => { overlays.close() },
          onConfirm: this.onCameraConfirm,
        })
      }

      // AgentFloatWindow
      AgentFloatWindow({
        show: this.activeOverlay === 'float',
        onClose: (): void => {
          overlays.close();
          this.pendingImageUri = "";
        },
        onGoCamera: (): void => overlays.switchTo('camera'),
        pendingImageUri: this.pendingImageUri,
      })
    }
    .width("100%").height("100%")
  }
}
