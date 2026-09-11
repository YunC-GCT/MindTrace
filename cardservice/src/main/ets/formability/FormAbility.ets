import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { CardSnapshot, CardSnapshotBinding, CardSnapshotStore } from 'common';

export default class FormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const snapshot: CardSnapshot = this.loadSnapshot();
    return formBindingData.createFormBindingData(new CardSnapshotBinding(snapshot));
  }

  onUpdateForm(formId: string): void {
    const snapshot: CardSnapshot = this.loadSnapshot();
    const binding: formBindingData.FormBindingData =
      formBindingData.createFormBindingData(new CardSnapshotBinding(snapshot));
    formProvider.updateForm(formId, binding).catch((e: Error) => {
      console.warn('[FormAbility.onUpdateForm] ' + e.message);
    });
  }

  private loadSnapshot(): CardSnapshot {
    try {
      return CardSnapshotStore.load(this.context);
    } catch (e) {
      console.warn('[FormAbility.loadSnapshot] ' + (e instanceof Error ? e.message : String(e)));
      const empty: CardSnapshot = {
        todayReviewCount: 0,
        streakDays: 0,
        newUnitCount: 0,
        masteredRatio: 0,
        updatedAt: 0,
      };
      return empty;
    }
  }
}
