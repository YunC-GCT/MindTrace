/**
 * AgentUiCard.ets — 小艺批量整理半屏卡片
 *
 * 路径: entry/src/main/ets/pages/AgentUiCard.ets
 * 职责: 作为 AgentUIExtAbility 的半屏内容，向用户说明「整理数学题」的下一步，
 *       并把「开始选图」意图通过 Want 参数交回 EntryAbility（batch_capture）。
 * 依赖: @kit.AbilityKit (common / UIExtensionContentSession / Want)、
 *       @kit.BasicServicesKit (BusinessError)、@kit.PerformanceAnalysisKit (hilog)、
 *       common (UI tokens)
 *
 * 数据流:
 *   AgentUIExtAbility.onSessionCreate -> LocalStorage('session') -> AgentUiCard
 *     -> 「开始选图」-> startAbility(EntryAbility, { mtAction: 'batch_capture', mtSource: 'agent_ui' })
 *     -> closeSelf() -> session.terminateSelf()
 *     -> 「取消」-> closeSelf() -> session.terminateSelf()
 *
 * 尺寸:
 *   - 页面根容器只做 100% 宽度与自适应高度，不铺深色全屏底；
 *   - 卡片本身 maxWidth 520，平板/折叠屏上居中收窄。
 */
import { common, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BG_CARD,
  BG_DARK,
  BORDER,
  F_BASE,
  F_LG,
  F_MD,
  F_SM,
  LH_COMFORT,
  MINT,
  R_LG,
  R_MD,
  S_2,
  S_3,
  S_4,
  S_5,
  TEXT,
  TEXT_2,
  W_SEMIBOLD
} from 'common';

const TAG: string = 'MindTraceAgentUI';
const DOMAIN: number = 0xA2A1;
const SESSION_KEY: string = 'session';

/** 卡片文案集中存放，避免 build() 内散落字符串。 */
interface AgentUiCardCopy {
  title: string;
  description: string;
  primaryAction: string;
  secondaryAction: string;
}

/** 回传 EntryAbility 的批量整理参数（spec 031 §4.1）。 */
interface BatchCaptureParameters {
  mtAction: string;
  mtSource: string;
}

const BATCH_CAPTURE: BatchCaptureParameters = {
  mtAction: 'batch_capture',
  mtSource: 'agent_ui',
};

/**
 * 组装拉起 EntryAbility 的 Want。
 * 本轮（T1a）只验证卡片能否渲染，参数透传留到 T1b：
 * ArkTS 的 arkts-no-untyped-obj-literals 不接受 Record<string, Object> 字面量。
 */
function buildBatchCaptureWant(): Want {
  const want: Want = {
    bundleName: 'com.example.mindtrace',
    abilityName: 'EntryAbility',
  };
  return want;
}

@Entry
@Component
struct AgentUiCard {
  private copy: AgentUiCardCopy = {
    title: '整理数学题',
    description: '从相册选择题目图片，自动生成笔记',
    primaryAction: '开始选图',
    secondaryAction: '取消',
  };

  private session: UIExtensionContentSession | undefined = undefined;

  aboutToAppear(): void {
    const storage: LocalStorage | undefined = this.getUIContext().getSharedLocalStorage();
    if (storage !== undefined) {
      this.session = storage.get<UIExtensionContentSession>(SESSION_KEY);
    }
    hilog.info(DOMAIN, TAG, 'AgentUiCard aboutToAppear: session=%{public}s',
      this.session === undefined ? 'missing' : 'ready');
  }

  /** 关闭半屏卡片；session 由 AgentUIExtAbility 通过 LocalStorage 注入。 */
  private closeSelf = (): void => {
    const session: UIExtensionContentSession | undefined = this.session;
    if (session === undefined) {
      hilog.warn(DOMAIN, TAG, 'closeSelf: session 不存在，无法关闭卡片');
      return;
    }
    session.terminateSelf()
      .then((): void => {
        hilog.info(DOMAIN, TAG, 'closeSelf: 卡片已关闭');
      })
      .catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'closeSelf 失败 code=%{public}d message=%{public}s',
          err.code, err.message);
      });
  };

  /** 先拉起 EntryAbility 处理 batch_capture，成功后再关闭卡片。 */
  private startBatchCapture = (): void => {
    const ctx: common.UIExtensionContext = getContext(this) as common.UIExtensionContext;
    ctx.startAbility(buildBatchCaptureWant())
      .then((): void => {
        hilog.info(DOMAIN, TAG, 'startAbility(EntryAbility) 成功: mtAction=%{public}s',
          BATCH_CAPTURE.mtAction);
        this.closeSelf();
      })
      .catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'startAbility(EntryAbility) 失败 code=%{public}d message=%{public}s',
          err.code, err.message);
      });
  };

  build() {
    Column() {
      Column() {
        Text(this.copy.title)
          .fontSize(F_LG)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(this.copy.description)
          .fontSize(F_SM)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ top: S_2 })
          .lineHeight(LH_COMFORT)
          .textAlign(TextAlign.Start)

        Button(this.copy.primaryAction)
          .width('100%')
          .height(44)
          .margin({ top: S_5 })
          .backgroundColor(MINT)
          .fontColor(BG_DARK)
          .fontSize(F_MD)
          .fontWeight(W_SEMIBOLD)
          .borderRadius(R_MD)
          .onClick((): void => {
            this.startBatchCapture();
          })

        Button(this.copy.secondaryAction)
          .width('100%')
          .height(44)
          .margin({ top: S_3 })
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_2)
          .fontSize(F_BASE)
          .borderRadius(R_MD)
          .border({ width: 1, color: BORDER })
          .onClick((): void => {
            this.closeSelf();
          })
      }
      .width('100%')
      .constraintSize({ maxWidth: 520 })
      .padding(S_5)
      .backgroundColor(BG_CARD)
      .borderRadius(R_LG)
      .border({ width: 1, color: BORDER })
    }
    .width('100%')
    .padding(S_4)
    .alignItems(HorizontalAlign.Center)
  }
}
