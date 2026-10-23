/**
 * AgentUIExtAbility.ets — 小艺智能体半屏卡片扩展入口
 *
 * 路径: entry/src/main/ets/agentextability/AgentUIExtAbility.ets
 * 职责: 承载 spec 031 T1a 的 AgentUIExtensionAbility。小艺拉起本扩展后，
 *       在 onSessionCreate 中加载半屏卡片 pages/AgentUiCard；卡片按钮再
 *       startAbility(EntryAbility) 把用户带回应用内选图流程。
 * 依赖: @kit.AbilityKit (AgentUIExtensionAbility / UIExtensionContentSession / Want / AbilityConstant)、
 *       @kit.PerformanceAnalysisKit (hilog)
 *
 * 数据流:
 *   小艺调起 agentUI 扩展 -> onCreate -> onSessionCreate(want, session)
 *     -> session.loadContent('pages/AgentUiCard', storage)
 *     -> 用户在卡片点击「开始选图」-> startAbility(EntryAbility, mtAction=batch_capture)
 *     -> 卡片 closeSelf -> onDestroy
 *
 * 约束:
 *   - 必须与 AgentExtAbility 同进程运行（spec 031 §4.5）。
 *   - 扩展进程不能直接拉起 Picker，所以只负责加载卡片，由卡片携带
 *     mtAction/mtSource 回到 EntryAbility（spec 031 §3.1）。
 */
import {
  AbilityConstant,
  AgentUIExtensionAbility,
  UIExtensionContentSession,
  Want
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'MindTraceAgentUI';
const DOMAIN: number = 0xA2A1;
const CARD_PAGE: string = 'pages/AgentUiCard';
const SESSION_KEY: string = 'session';

export default class AgentUIExtAbility extends AgentUIExtensionAbility {
  onCreate(launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate: agentUI 扩展创建');
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, 'onSessionCreate: 加载半屏卡片 %{public}s', CARD_PAGE);
    try {
      // 把 session 交给页面，页面「取消」/「开始选图」后据此 terminateSelf。
      const storage: LocalStorage = new LocalStorage();
      storage.setOrCreate(SESSION_KEY, session);
      session.loadContent(CARD_PAGE, storage);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadContent 失败: %{public}s', (error as Error).message);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy: agentUI 扩展退出');
  }
}
