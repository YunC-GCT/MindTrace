/**
 * AgentUiCard.ets — 小艺拍题/选图半屏卡片
 *
 * 路径: entry/src/main/ets/pages/AgentUiCard.ets
 * 职责: 作为 AgentUIExtAbility 的半屏内容，向用户说明下一步，
 *       并把「从相册选图」/「拍照整理」意图通过 Want 参数交回 EntryAbility。
 * 依赖: @kit.AbilityKit (common / UIExtensionContentSession / Want)、
 *       @kit.BasicServicesKit (BusinessError)、@kit.PerformanceAnalysisKit (hilog)、
 *       common (UI tokens)
 *
 * 数据流:
 *   AgentUIExtAbility.onSessionCreate -> LocalStorage('session' / 'cardQuery') -> AgentUiCard
 *     -> 「从相册选图」-> startAbility(EntryAbility, { mtAction: 'pick_from_card' })
 *     -> 「拍照整理」  -> startAbility(EntryAbility, { mtAction: 'camera_from_card' })
 *     -> 成功后 terminateSelf()；失败则页面显示「请在 MindTrace 里点『+』选图」
 *
 * 尺寸:
 *   - 根容器只做 100% 宽度与自适应高度，不铺深色全屏底；
 *   - 卡片本身 maxWidth 520，平板/折叠屏上居中收窄。
 */
import { common, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BG_CARD,
  BG_DARK,
  BORDER,
  DANGER,
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
const QUERY_KEY: string = 'cardQuery';
const MT_BUNDLE: string = 'com.example.mindtrace';
const ENTRY_ABILITY: string = 'EntryAbility';
/** 与 EntryAbility.readCardAction 约定的两个动作 */
const ACTION_PICK: string = 'pick_from_card';
const ACTION_CAMERA: string = 'camera_from_card';

/** 卡片文案集中存放，避免 build() 内散落字符串。 */
interface AgentUiCardCopy {
  title: string;
  description: string;
  albumAction: string;
  cameraAction: string;
  errorText: string;
}

const CARD_COPY: AgentUiCardCopy = {
  title: 'MindTrace 整理',
  description: '点下方按钮选择题目图片',
  albumAction: '从相册选图',
  cameraAction: '拍照整理',
  errorText: '请在 MindTrace 里点『+』选图',
};

/**
 * 组装拉起 EntryAbility 的 Want。
 * ArkTS 的 arkts-no-untyped-obj-literals 不接受 Record<string, Object> 字面量，
 * 因此先建空 Record 再按键赋值（与 skill/skillability/SkillAbility 同一写法）。
 */
function buildCaptureWant(action: string): Want {
  const parameters: Record<string, Object> = {};
  parameters['mtAction'] = action;
  parameters['mtSource'] = 'agent_ui';
  const want: Want = {
    bundleName: MT_BUNDLE,
    abilityName: ENTRY_ABILITY,
    parameters: parameters,
  };
  return want;
}

@Entry
@Component
struct AgentUiCard {
  private session: UIExtensionContentSession | undefined = undefined;
  @State errorText: string = '';

  aboutToAppear(): void {
    const storage: LocalStorage | undefined = this.getUIContext().getSharedLocalStorage();
    if (storage !== undefined) {
      this.session = storage.get<UIExtensionContentSession>(SESSION_KEY);
      const query: string = storage.get<string>(QUERY_KEY) ?? '';
      hilog.info(DOMAIN, TAG, 'AgentUiCard aboutToAppear: query=%{public}s',
        query.substring(0, 40));
    }
    hilog.info(DOMAIN, TAG, 'AgentUiCard aboutToAppear: session=%{public}s',
      this.session === undefined ? 'missing' : 'ready');
  }

  /** 先拉起 EntryAbility 处理 mtAction，成功后再关闭卡片。 */
  private openApp = (action: string): void => {
    this.errorText = '';
    const ctx: common.UIExtensionContext = getContext(this) as common.UIExtensionContext;
    ctx.startAbility(buildCaptureWant(action))
      .then((): void => {
        hilog.info(DOMAIN, TAG, 'startAbility(EntryAbility) 成功: mtAction=%{public}s', action);
        ctx.terminateSelf().catch((err: BusinessError): void => {
          hilog.warn(DOMAIN, TAG, 'terminateSelf 失败 code=%{public}d message=%{public}s',
            err.code, err.message);
        });
      })
      .catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'startAbility(EntryAbility) 失败 code=%{public}d message=%{public}s',
          err.code, err.message);
        this.errorText = CARD_COPY.errorText;
      });
  };

  build() {
    Column() {
      Column() {
        Text(CARD_COPY.title)
          .fontSize(F_LG)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(CARD_COPY.description)
          .fontSize(F_SM)
          .fontColor(TEXT_2)
          .width('100%')
          .margin({ top: S_2 })
          .lineHeight(LH_COMFORT)
          .textAlign(TextAlign.Start)

        Button(CARD_COPY.albumAction)
          .width('100%')
          .height(44)
          .margin({ top: S_5 })
          .backgroundColor(MINT)
          .fontColor(BG_DARK)
          .fontSize(F_MD)
          .fontWeight(W_SEMIBOLD)
          .borderRadius(R_MD)
          .onClick((): void => {
            this.openApp(ACTION_PICK);
          })

        Button(CARD_COPY.cameraAction)
          .width('100%')
          .height(44)
          .margin({ top: S_3 })
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_2)
          .fontSize(F_MD)
          .borderRadius(R_MD)
          .border({ width: 1, color: BORDER })
          .onClick((): void => {
            this.openApp(ACTION_CAMERA);
          })

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(F_SM)
            .fontColor(DANGER)
            .width('100%')
            .margin({ top: S_3 })
            .textAlign(TextAlign.Start)
        }
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
