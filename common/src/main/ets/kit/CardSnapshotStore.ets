/**
 * CardSnapshotStore.ets — 卡片快照 Preferences 存储
 *
 * 路径: common/src/main/ets/kit/CardSnapshotStore.ets
 * 职责: 把 CardSnapshot 通过 @kit.ArkData preferences 持久化,跨进程共享单一数据源
 * 依赖: @kit.ArkData preferences; ./FormCardFacade CardSnapshot
 *
 * 数据流:
 *   FormCardFacadeImpl.pushSnapshot → save → putSync; 卡片进程 load → putSync
 *
 * ArkTS 1.1 strict 适配:
 *   - 仅静态方法;通过 module-private getStore 缓存 Preferences 实例
 *   - 所有数据为 number/string,避免复杂反序列化
 */
import { preferences } from '@kit.ArkData';
import { CardSnapshot } from './FormCardFacade';

const STORE_NAME: string = 'mindtrace_card_snapshot';

export class CardSnapshotStore {
  static save(context: Context, snapshot: CardSnapshot): void {
    const store: preferences.Preferences = CardSnapshotStore.getStore(context);
    store.putSync('todayReviewCount', snapshot.todayReviewCount);
    store.putSync('streakDays', snapshot.streakDays);
    store.putSync('newUnitCount', snapshot.newUnitCount);
    store.putSync('masteredRatio', snapshot.masteredRatio);
    store.putSync('updatedAt', snapshot.updatedAt);
  }

  static load(context: Context): CardSnapshot {
    const store: preferences.Preferences = CardSnapshotStore.getStore(context);
    const snapshot: CardSnapshot = {
      todayReviewCount: CardSnapshotStore.readNumber(store, 'todayReviewCount'),
      streakDays: CardSnapshotStore.readNumber(store, 'streakDays'),
      newUnitCount: CardSnapshotStore.readNumber(store, 'newUnitCount'),
      masteredRatio: CardSnapshotStore.readNumber(store, 'masteredRatio'),
      updatedAt: CardSnapshotStore.readNumber(store, 'updatedAt'),
    };
    return snapshot;
  }

  private static getStore(context: Context): preferences.Preferences {
    if (!preferences.isStorageTypeSupported(preferences.StorageType.GSKV)) {
      throw new Error('GSKV is required for card snapshot sharing');
    }
    const options: preferences.Options = {
      name: STORE_NAME,
      storageType: preferences.StorageType.GSKV,
    };
    return preferences.getPreferencesSync(context, options);
  }

  private static readNumber(store: preferences.Preferences, key: string): number {
    const value: preferences.ValueType = store.getSync(key, 0);
    return typeof value === 'number' ? value : 0;
  }
}
