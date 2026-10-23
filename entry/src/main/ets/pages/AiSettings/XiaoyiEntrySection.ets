/**
 * XiaoyiEntrySection.ets — AI 设置页「问小艺」入口（issue #225）
 *
 * 路径: entry/src/main/ets/pages/AiSettings/XiaoyiEntrySection.ets
 * 职责: 用 AgentFrameworkKit 的 FunctionComponent 在应用内嵌入小艺智能体入口；
 *       进入前先用 AgentController.isAgentSupport() 探测设备 / 账号是否可用，
 *       不可用时只显示中文提示，不渲染 FunctionComponent。
 * 依赖: @kit.AgentFrameworkKit (AgentController / FunctionComponent / FunctionController)
 *       @kit.AbilityKit (common.UIAbilityContext)
 *       @kit.BasicServicesKit (BusinessError)
 *       common (BG_CARD / TEXT / TEXT_3 / TEXT_4 / R_LG / F_SM / F_XS / W_SEMIBOLD)
 *
 * 数据流:
 *   aboutToAppear() → AgentController.isAgentSupport(ctx, AGENT_ID)
 *     → supported / checked / hint → build() 渲染 FunctionComponent 或提示行
 *
 * 设计要点:
 *   - 对话在小艺侧完成，本应用拿不到回答，因此本入口不写本地笔记。
 *   - 错误码来自 AgentFrameworkKit：
 *       1022400010 参数错误 / 1022400011 隐私协议未接受
 *       1022400012 华为账号未登录 / 1022400013 网络错误 / 1022400014 内部错误
 *
 * ArkTS 1.1 strict 适配:
 *   - struct 内不放普通方法，异步回调写成箭头函数字段，避免 this 丢失。
 *   - catch 参数不标类型，用 BusinessError 断言后再取 code。
 */

import { AgentController, FunctionComponent, FunctionController } from '@kit.AgentFrameworkKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { BG_CARD, TEXT, TEXT_3, TEXT_4, R_LG, F_SM, F_XS, W_SEMIBOLD } from 'common'

// issue #225: 小艺开放平台智能体 ID（与端A2A 的 agentId 对齐）。
// 若真机返回 1022400010（参数错误）或 isAgentSupport=false，
// 替换为小艺开放平台生成的智能体 ID。
const AGENT_ID: string = 'mindtrace-note-agent'

// 错误码 → 中文提示。未知码保留原始码，便于真机排查。
function errorHint(code: number): string {
  switch (code) {
    case 1022400010:
      return '智能体参数错误，请确认智能体 ID 已在开放平台配置'
    case 1022400011:
      return '请先在小艺中同意隐私协议'
    case 1022400012:
      return '请先登录华为账号后再使用「问小艺」'
    case 1022400013:
      return '网络异常，请检查网络后重试'
    case 1022400014:
      return '小艺服务内部错误，请稍后重试'
    default:
      return `「问小艺」暂不可用（错误码 ${code}）`
  }
}

@Component
export struct XiaoyiEntrySection {
  @State supported: boolean = false
  @State checked: boolean = false
  @State hint: string = ''

  // FunctionController 目前是空实现（SDK 注释 "This API is reserved"），
  // 仅作为 FunctionComponent 的可选入参透传。
  private controller: FunctionController = new FunctionController()

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    new AgentController().isAgentSupport(ctx, AGENT_ID)
      .then((ok: boolean): void => {
        this.supported = ok
        this.checked = true
        if (!ok) {
          this.hint = '当前设备或账号暂不支持「问小艺」（请确认已登录华为账号、同意隐私协议，且智能体已关联本应用）'
        }
      })
      .catch((e: BusinessError): void => {
        this.supported = false
        this.checked = true
        this.hint = errorHint(e.code)
      })
  }

  // FunctionComponent 内部错误（拉起后 / 对话中）同样落到 hint
  private onError = (e: BusinessError): void => {
    this.hint = errorHint(e.code)
  }

  build() {
    Column() {
      Text('问小艺')
        .fontSize(F_SM)
        .fontColor(TEXT)
        .fontWeight(W_SEMIBOLD)

      Text('对话在小艺侧完成，回答不会写入本地笔记')
        .fontSize(F_XS)
        .fontColor(TEXT_3)
        .margin({ top: 4 })

      if (this.supported) {
        // 系统半屏智能体对话入口；标题按钮形态由 options.title 决定
        Column() {
          FunctionComponent({
            agentId: AGENT_ID,
            onError: this.onError,
            options: { title: '问小艺' },
            controller: this.controller,
          })
        }
        .width('100%')
        .margin({ top: 12 })

        // 拉起后 / 对话中的错误（隐私协议、登录、网络）也在此可见
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(F_XS)
            .fontColor(TEXT_4)
            .margin({ top: 6 })
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      } else {
        // 未检测完成 / 不可用 / 出错：只给提示行，不渲染组件
        Text(this.checked
          ? (this.hint.length > 0 ? this.hint : '当前设备暂不支持「问小艺」')
          : '正在检测「问小艺」可用性…')
          .fontSize(F_XS)
          .fontColor(TEXT_4)
          .margin({ top: 8 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(R_LG)
    .backgroundColor(BG_CARD)
    .margin({ left: 8, right: 8, top: 8 })
  }
}
