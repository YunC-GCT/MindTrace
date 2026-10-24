/**
 * FormCardFacadeImpl.ets — 桌面卡片真实实现
 *
 * 路径: entry/src/main/ets/kit/FormCardFacadeImpl.ets
 * 职责: 把 CardSnapshot 写入卡片快照并通过 @kit.FormKit 推送给已发布的卡片
 * 依赖: @kit.AbilityKit, @kit.FormKit; common CardSnapshot/CardSnapshotBinding/CardSnapshotStore/FormCardFacade
 *
 * 数据流:
 *   CardSnapshotService → getFormCardFacade().pushSnapshot(snapshot) → updateForm
 *
 * ArkTS 1.1 strict 适配:
 *   - 模块顶层 export getFormCardFacade(),保持组合根入口单一
 *   - 仅刷新 TodayReviewCard,避免影响其他卡片实例
 */
import { common } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSnapshot, CardSnapshotBinding, CardSnapshotStore, FormCardFacade } from 'common';

const DOMAIN: number = 0xC4D1;
const TAG: string = 'FormCard';

export class FormCardFacadeImpl implements FormCardFacade {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async pushSnapshot(snapshot: CardSnapshot): Promise<void> {
    // 快照先落 preferences：卡片 onAddForm 读的就是这份，没加卡片时也不能丢
    CardSnapshotStore.save(this.context, snapshot);
    const binding: formBindingData.FormBindingData =
      formBindingData.createFormBindingData(new CardSnapshotBinding(snapshot));
    let forms: formInfo.RunningFormInfo[] = [];
    try {
      forms = await formProvider.getPublishedRunningFormInfos();
    } catch (error) {
      // 桌面没加卡片时系统会抛「Failed to obtain the configuration information」，
      // 这是正常状态，不是故障：快照已落盘，等卡片加上后 onAddForm 自会读到。
      const e: BusinessError = error as BusinessError;
      hilog.warn(DOMAIN, TAG, '%{public}s', 'no running forms: ' + e.message);
      return;
    }
    let pushed: number = 0;
    for (const form of forms) {
      if (form.moduleName === 'cardservice' && form.formName === 'TodayReviewCard') {
        await formProvider.updateForm(form.formId, binding);
        pushed += 1;
      }
    }
    hilog.info(DOMAIN, TAG, '%{public}s',
      'forms=' + forms.length.toString() + ' pushed=' + pushed.toString()
        + ' due=' + snapshot.todayReviewCount.toString() + ' new=' + snapshot.newUnitCount.toString());
  }
}

export function getFormCardFacade(): FormCardFacade | null {
  const impl: FormCardFacadeImpl | undefined = AppStorage.get<FormCardFacadeImpl>('formCardFacade');
  return impl ?? null;
}
