/**
 * AgentUIExtAbility.ets — 小艺智能体半屏卡片扩展入口
 *
 * 路径: entry/src/main/ets/agentextability/AgentUIExtAbility.ets
 * 职责: 承载 spec 031 T1a 的 AgentUIExtensionAbility。小艺拉起本扩展后，
 *       在 onSessionCreate 中解析 card payload 的 query，并加载半屏卡片
 *       pages/AgentUiCard；卡片按钮再 startAbility(EntryAbility) 把用户带回应用选图。
 * 依赖: @kit.AbilityKit (AgentUIExtensionAbility / UIExtensionContentSession / Want / AbilityConstant)、
 *       @kit.PerformanceAnalysisKit (hilog)
 *
 * 数据流:
 *   小艺调起 agentUI 扩展 -> onCreate -> onSessionCreate(want, session)
 *     -> 解析 ability.want.params.payload 里的 query（失败用空串）
 *     -> session.loadContent('pages/AgentUiCard', storage)
 *     -> 用户点「从相册选图」/「拍照整理」-> startAbility(EntryAbility, mtAction=pick_from_card|camera_from_card)
 *     -> 卡片 terminateSelf -> onDestroy
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
const PAYLOAD_KEY: string = 'ability.want.params.payload';
/** 卡片 payload 的形状（A2AUiCard.buildPickCardPartJson 的 payload 字段） */
const QUERY_KEY: string = 'cardQuery';

/** 小艺透传的 card payload：{"query":"...","source":"xiaoyi","v":1} */
interface UiCardPayload {
  query?: string;
}

export default class AgentUIExtAbility extends AgentUIExtensionAbility {
  onCreate(launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate: agentUI 扩展创建');
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    const raw: string = (want.parameters?.[PAYLOAD_KEY] as string) ?? '';
    const query: string = this.readQuery(raw);
    // 真机验收看这一行：AGENT_UI onCreate query=<前 40 字>
    hilog.info(DOMAIN, TAG, 'AGENT_UI onCreate query=%{public}s', query.substring(0, 40));
    hilog.info(DOMAIN, TAG, 'onSessionCreate: 加载半屏卡片 %{public}s payload=%{public}d 字节',
      CARD_PAGE, raw.length);
    try {
      // 把 session / payload / query 交给页面，页面按钮据此 startAbility 并 terminateSelf。
      const storage: LocalStorage = new LocalStorage();
      storage.setOrCreate(SESSION_KEY, session);
      storage.setOrCreate('cardPayload', raw);
      storage.setOrCreate(QUERY_KEY, query);
      session.loadContent(CARD_PAGE, storage);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadContent 失败: %{public}s', (error as Error).message);
    }
  }

  /** payload 是 JSON 字符串；解析失败或没有 query 字段时返回空串，绝不把卡片打成异常。 */
  private readQuery(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    try {
      const parsed: UiCardPayload = JSON.parse(raw) as UiCardPayload;
      if (parsed.query !== undefined && typeof parsed.query === 'string') {
        return parsed.query as string;
      }
      return '';
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'payload JSON 解析失败: %{public}s', (error as Error).message);
      return '';
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy: agentUI 扩展退出');
  }
}
