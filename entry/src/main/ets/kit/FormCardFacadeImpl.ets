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
import { CardSnapshot, CardSnapshotBinding, CardSnapshotStore, FormCardFacade } from 'common';

export class FormCardFacadeImpl implements FormCardFacade {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async pushSnapshot(snapshot: CardSnapshot): Promise<void> {
    CardSnapshotStore.save(this.context, snapshot);
    const binding: formBindingData.FormBindingData =
      formBindingData.createFormBindingData(new CardSnapshotBinding(snapshot));
    const forms: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
    for (const form of forms) {
      if (form.moduleName === 'cardservice' && form.formName === 'TodayReviewCard') {
        await formProvider.updateForm(form.formId, binding);
      }
    }
  }
}

export function getFormCardFacade(): FormCardFacade | null {
  const impl: FormCardFacadeImpl | undefined = AppStorage.get<FormCardFacadeImpl>('formCardFacade');
  return impl ?? null;
}
