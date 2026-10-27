/**
 * CardSnapshotStore.ets — 卡片快照 Preferences 存储（单 key 原子替换 + schemaVersion）
 *
 * 路径: common/src/main/ets/kit/CardSnapshotStore.ets
 * 职责: 把 CardSnapshot 编码成单个 schemaVersion JSON 后写入 Preferences；读侧优先新 key，
 *       读不到再回退旧的分字段 key，保证老卡片仍能显示。
 * 依赖: @kit.ArkData preferences; ./FormCardFacade CardSnapshot; ./CardSnapshotCodec 编解码
 *
 * 数据流:
 *   FormCardFacadeImpl.pushSnapshot → save → encodeCardSnapshot → 单个 key + flush
 *   卡片进程 FormAbility.onAddForm → loadResult → 新 key / 旧 key → CardSnapshot
 *
 * 存储约定:
 *   - 新 key `snapshot_v1` 存一个完整 JSON 字符串；单 key 写入天然原子，flush 成功才返回 true。
 *   - save 不抛异常：Preferences 不可用、putSync 或 flush 失败都返回 false，调用方可重试。
 *   - save 保持同步返回 boolean 并使用 flushSync()（等价于 flush()），因为既有调用方
 *     FormCardFacadeImpl.pushSnapshot 不 await；改成 Promise 会让「落盘后再推卡片」失去保证。
 *     该调用方目前忽略返回值；失败会 console.warn，重试接线留给后续切片。
 *   - loadResult 暴露 ok / stale / updatedAt；解码失败返回空快照，不崩。
 *   - 只有新 key 不存在时才回退旧分字段 key；新 key 存在但解码失败时返回空快照
 *     （任务要求「解不出来 → 返回空快照」），避免把损坏值当成可用投影。
 *   - 旧 key（todayReviewCount / streakDays / newUnitCount / masteredRatio / updatedAt）
 *     只读不写，用于升级后的兼容回退。
 *
 * ArkTS 1.1 strict 适配:
 *   - 本文件是既有 Preferences 边界，必须保留 @kit.ArkData；新增的 Codec 保持零 Kit。
 *   - 所有分支显式构造 CardSnapshot / CardSnapshotLoadResult，不用无类型字面量。
 *   - 只新增 loadResult，load 保留并内部委托，既有调用方不需要改。
 */
import { preferences } from '@kit.ArkData';
import { CardSnapshot } from './FormCardFacade';
import {
  CardSnapshotDecodeResult,
  CardSnapshotEnvelope,
  decodeCardSnapshot,
  encodeCardSnapshot,
} from './CardSnapshotCodec';

const STORE_NAME: string = 'mindtrace_card_snapshot';
const SNAPSHOT_KEY: string = 'snapshot_v1';
const LEGACY_TODAY_REVIEW_KEY: string = 'todayReviewCount';
const LEGACY_STREAK_KEY: string = 'streakDays';
const LEGACY_NEW_UNIT_KEY: string = 'newUnitCount';
const LEGACY_MASTERED_RATIO_KEY: string = 'masteredRatio';
const LEGACY_UPDATED_AT_KEY: string = 'updatedAt';
const LEGACY_MISSING: number = -1;

// 读侧结果：ok=false 时 snapshot 是空快照；stale=true 表示没有可用的当前 schema 快照
// （无数据、schema 不认识、旧格式或读取失败）。
export interface CardSnapshotLoadResult {
  ok: boolean;
  stale: boolean;
  snapshot: CardSnapshot;
  updatedAt: number;
}

export class CardSnapshotStore {
  static save(context: Context, snapshot: CardSnapshot): boolean {
    try {
      const store: preferences.Preferences = CardSnapshotStore.getStore(context);
      const raw: string = encodeCardSnapshot(snapshot, snapshot.updatedAt);
      store.putSync(SNAPSHOT_KEY, raw);
      // 同步落盘：既有调用方不 await，用 flushSync 保证返回前已持久化（等价于 flush()）。
      store.flushSync();
      return true;
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      console.warn('[CardSnapshotStore.save] ' + message);
      return false;
    }
  }

  static load(context: Context): CardSnapshot {
    return CardSnapshotStore.loadResult(context).snapshot;
  }

  static loadResult(context: Context): CardSnapshotLoadResult {
    let store: preferences.Preferences;
    try {
      store = CardSnapshotStore.getStore(context);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      console.warn('[CardSnapshotStore.loadResult] ' + message);
      return CardSnapshotStore.emptyResult(false, true);
    }

    try {
      const newValue: preferences.ValueType = store.getSync(SNAPSHOT_KEY, '');
      const raw: string = typeof newValue === 'string' ? newValue : '';
      if (raw.length > 0) {
        const decoded: CardSnapshotDecodeResult = decodeCardSnapshot(raw);
        const envelope: CardSnapshotEnvelope | undefined = decoded.envelope;
        if (decoded.ok && envelope !== undefined) {
          const loaded: CardSnapshotLoadResult = {
            ok: true,
            stale: false,
            snapshot: envelope.snapshot,
            updatedAt: envelope.updatedAt,
          };
          return loaded;
        }
        // 新 key 存在但解不出来：不回退旧 key，直接空快照，避免展示过期投影。
        return CardSnapshotStore.emptyResult(false, decoded.stale);
      }

      // 新 key 不存在：回退旧的分字段 key，保持升级前卡片仍能显示。
      const legacyUpdatedAt: preferences.ValueType = store.getSync(LEGACY_UPDATED_AT_KEY, LEGACY_MISSING);
      if (typeof legacyUpdatedAt === 'number' && legacyUpdatedAt !== LEGACY_MISSING) {
        const legacyUpdatedAtNumber: number = legacyUpdatedAt as number;
        const legacy: CardSnapshot = {
          todayReviewCount: CardSnapshotStore.readNumber(store, LEGACY_TODAY_REVIEW_KEY),
          streakDays: CardSnapshotStore.readNumber(store, LEGACY_STREAK_KEY),
          newUnitCount: CardSnapshotStore.readNumber(store, LEGACY_NEW_UNIT_KEY),
          masteredRatio: CardSnapshotStore.readNumber(store, LEGACY_MASTERED_RATIO_KEY),
          updatedAt: legacyUpdatedAtNumber,
        };
        const loaded: CardSnapshotLoadResult = {
          ok: true,
          stale: true,
          snapshot: legacy,
          updatedAt: legacyUpdatedAtNumber,
        };
        return loaded;
      }

      return CardSnapshotStore.emptyResult(false, true);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      console.warn('[CardSnapshotStore.loadResult] ' + message);
      return CardSnapshotStore.emptyResult(false, true);
    }
  }

  private static emptyResult(ok: boolean, stale: boolean): CardSnapshotLoadResult {
    const empty: CardSnapshot = {
      todayReviewCount: 0,
      streakDays: 0,
      newUnitCount: 0,
      masteredRatio: 0,
      updatedAt: 0,
    };
    const result: CardSnapshotLoadResult = {
      ok: ok,
      stale: stale,
      snapshot: empty,
      updatedAt: 0,
    };
    return result;
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
