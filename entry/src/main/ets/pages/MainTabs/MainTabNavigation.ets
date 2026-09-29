/**
 * MainTabNavigation.ets — 五入口导航业务协调器
 *
 * 路径: entry/src/main/ets/pages/MainTabs/MainTabNavigation.ets
 * 职责: 统一处理内容页切换、中央 AI 入口和最近内容页索引。
 * 依赖: 无 UI 依赖；通过回调连接页面装配层。
 *
 * 数据流:
 *   TabBar/Tabs → select/onSystemIndexChanged → Index 回调 → 页面或浮层
 *
 * 视觉组件只负责发出入口事件，本类不直接创建 OverlayService。
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 interface 与函数类型，避免隐式结构类型。
 */

export const AI_TAB_INDEX: number = 2

export interface MainTabNavigationCallbacks {
  onSelectContent: (index: number) => void
  onSystemSelectContent: (index: number) => void
  onOpenAssistant: () => void
}

export class MainTabNavigation {
  private lastContentIndex: number = 0
  private callbacks: MainTabNavigationCallbacks

  constructor(callbacks: MainTabNavigationCallbacks) {
    this.callbacks = callbacks
  }

  select(index: number): void {
    if (index === AI_TAB_INDEX) {
      this.openAssistant()
      return
    }
    this.lastContentIndex = index
    this.callbacks.onSelectContent(index)
  }

  onSystemIndexChanged(index: number): void {
    if (index === AI_TAB_INDEX) {
      this.openAssistant()
      this.callbacks.onSystemSelectContent(this.lastContentIndex)
      return
    }
    this.lastContentIndex = index
    this.callbacks.onSystemSelectContent(index)
  }

  openAssistant(): void {
    this.callbacks.onOpenAssistant()
  }
}
