/**
 * AgentUiCard.ets — 小艺半屏「选图整理」卡片（App 相册兜底路径）
 *
 * 路径: entry/src/main/ets/pages/AgentUiCard.ets
 * 职责: 作为 AgentUIExtAbility 的半屏内容。系统限制：UIExtension 半屏卡片内无法渲染
 *       PhotoViewPicker / PhotoPickerComponent（实测空白），因此卡片按钮改为拉起 EntryAbility
 *       的系统照片选择器（pick_from_card），由 App 完成 OCR/整理/入库；图片仍不出应用沙箱。
 * 依赖: @kit.AbilityKit、@kit.BasicServicesKit、@kit.PerformanceAnalysisKit、common UI tokens。
 *
 * 数据流:
 *   AgentUIExtAbility.onSessionCreate -> LocalStorage('session') -> AgentUiCard
 *     -> 点「从相册选图并整理」 -> startAbility(EntryAbility, mtAction=pick_from_card)
 *     -> App 内系统照片选择器 -> OCR/整理/写本地笔记库
 *
 * 约束:
 *   - 卡片自身不渲染相册（UIExtension 嵌套/内嵌 picker 实测空白）；
 *   - 图片不上传云端，最终写入设备本地笔记库。
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
const ACTION_PICK: string = 'pick_from_card';

interface AgentUiCardCopy {
  title: string;
  description: string;
  albumAction: string;
  doneAction: string;
  errorText: string;
}

const CARD_COPY: AgentUiCardCopy = {
  title: 'MindTrace 整理',
  description: '小艺不会把图片直接传给智能体。点下面按钮打开系统相册选一张题目图片，'
    + 'MindTrace 会就地 OCR 并整理入库（图片不出应用沙箱）。',
  albumAction: '从相册选图并整理',
  doneAction: '完成',
  errorText: '打开相册失败，请在 MindTrace App 里点「+」选图。',
};

function buildPickWant(): Want {
  const parameters: Record<string, Object> = {};
  parameters['mtAction'] = ACTION_PICK;
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
  @State busy: boolean = false;

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

  private openPickerInApp = (): void => {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    const ctx: common.UIExtensionContext = getContext(this) as common.UIExtensionContext;
    ctx.startAbility(buildPickWant())
      .then((): void => {
        hilog.info(DOMAIN, TAG, 'AGENT_UI startAbility(pick_from_card) ok');
        ctx.terminateSelf().catch((err: BusinessError): void => {
          hilog.warn(DOMAIN, TAG, 'terminateSelf failed code=%{public}d message=%{public}s',
            err.code, err.message);
        });
      })
      .catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'AGENT_UI startAbility failed code=%{public}d message=%{public}s',
          err.code, err.message);
        this.errorText = CARD_COPY.errorText;
        this.busy = false;
      });
  };

  private closeCard = (): void => {
    const ctx: common.UIExtensionContext = getContext(this) as common.UIExtensionContext;
    ctx.terminateSelf().catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'terminateSelf failed code=%{public}d message=%{public}s',
        err.code, err.message);
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

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(F_SM)
            .fontColor(DANGER)
            .width('100%')
            .margin({ top: S_3 })
            .textAlign(TextAlign.Start)
        }

        Button(CARD_COPY.albumAction)
          .width('100%')
          .height(44)
          .margin({ top: S_5 })
          .backgroundColor(MINT)
          .fontColor(BG_DARK)
          .fontSize(F_MD)
          .fontWeight(W_SEMIBOLD)
          .borderRadius(R_MD)
          .enabled(!this.busy)
          .onClick((): void => {
            this.openPickerInApp();
          })

        Button(CARD_COPY.doneAction)
          .width('100%')
          .height(44)
          .margin({ top: S_3 })
          .backgroundColor(Color.Transparent)
          .fontColor(TEXT_2)
          .fontSize(F_MD)
          .borderRadius(R_MD)
          .border({ width: 1, color: BORDER })
          .onClick((): void => {
            this.closeCard();
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
