/**
 * WebKeepAlive.ets — ArkWeb 渲染进程保活组件
 *
 * 路径: entry/src/main/ets/shared/atoms/WebKeepAlive.ets
 * 职责: 常驻隐藏空白 Web 组件,保证应用会话期间始终存在存活 Web,
 *      使 SINGLE 模式下共享的渲染进程组不因业务 Web 全部卸载而终止。
 * 依赖: @ohos.web.webview; @kit.PerformanceAnalysisKit(hilog)
 *
 * 背景: appfreeze 2026-09-11 — 公式 Web 批量挂卸导致渲染进程组反复 spawn/terminate。
 * 用法: 全应用只挂载一处(Index root Stack 末尾),随会话常驻,勿放条件渲染分支。
 */

/**
 * WebKeepAlive.ets — ArkWeb 渲染进程保活组件
 *
 * 路径: entry/src/main/ets/shared/atoms/WebKeepAlive.ets
 * 职责: 常驻隐藏空白 Web 组件,保证应用会话期间始终存在存活 Web,
 *      使 SINGLE 模式下共享的渲染进程组不因业务 Web 全部卸载而终止。
 * 依赖: @ohos.web.webview; @kit.PerformanceAnalysisKit(hilog)
 *
 * 背景: appfreeze 2026-09-11 — 公式 Web 批量挂卸导致渲染进程组反复 spawn/terminate。
 * 用法: 全应用只挂载一处(Index root Stack 末尾),随会话常驻,勿放条件渲染分支。
 *
 * ArkTS 1.1 strict 适配:
 *   - catch 变量不标注类型,通过 (`_err`) / (e as Error) 显式断言抽取安全字段;
 *   - 闭包内访问实例字段用 `this.controller` / `this.recoveryCount`。
 */

import webview from '@ohos.web.webview'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000
const KEEP_ALIVE_MAX_RECOVERY: number = 3

@Component
export struct WebKeepAlive {
  controller: webview.WebviewController = new webview.WebviewController()
  private recoveryCount: number = 0

  build() {
    // about:blank 零内容开销; 1x1 + opacity(0) + HitTestMode.None 不占布局不可见不拦触摸
    Web({ src: 'about:blank', controller: this.controller })
      .javaScriptAccess(false)
      .domStorageAccess(false)
      .fileAccess(false)
      .width(1)
      .height(1)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .onAttach((): void => {
        // 显式激活: 官方预启动模式要求 "至少一个Web组件处于活动状态" 才计入
        // 渲染进程保活; opacity(0) 的 Web 不会被自动激活, 必须显式 onActive
        try {
          this.controller.onActive()
        } catch (_err) {
          // controller 未就绪时由 onPageBegin 兜底
        }
      })
      .onPageBegin((): void => {
        try {
          this.controller.onActive()
        } catch (_err) {
          // 忽略: 此时无渲染进程可激活
        }
      })
      .onRenderExited((event: OnRenderExitedEvent): void => {
        // 保活 Web 仍挂载时进程组退出必属异常 (系统回收/崩溃);
        // 限次 refresh 触发渲染进程重建, 防进程缺失且不陷入无限拉起循环
        hilog.warn(DOMAIN, 'testTag',
          'WebKeepAlive onRenderExited reason=%{public}d recovery=%{public}d',
          event ? event.renderExitReason : -1, this.recoveryCount)
        if (this.recoveryCount < KEEP_ALIVE_MAX_RECOVERY) {
          this.recoveryCount += 1
          try {
            this.controller.refresh()
          } catch (_err) {
            // controller 已解绑 (应用销毁期) 时忽略
          }
        }
      })
  }
}
