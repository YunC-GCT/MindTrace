/**
 * CardSnapshotCodec.ets — 卡片快照纯编解码（schemaVersion + 默认值补齐）
 *
 * 路径: common/src/main/ets/kit/CardSnapshotCodec.ets
 * 职责: 把 CardSnapshot 编成单个带 schemaVersion 的 JSON 字符串，并在解码时容忍缺失字段；
 *       不读 Preferences、不抛异常，供 CardSnapshotStore 与 Node 契约测试共用。
 * 依赖: ./FormCardFacade (CardSnapshot，零 Kit)
 *
 * 数据流:
 *   CardSnapshotStore.save → encodeCardSnapshot → 单个 JSON value
 *   CardSnapshotStore.loadResult → decodeCardSnapshot → CardSnapshot / stale 标记
 *
 * 解码约定:
 *   - raw 为空 / undefined → ok=false, stale=true, error=EMPTY
 *   - JSON 坏 / null → ok=false, stale=false, error=MALFORMED
 *   - schemaVersion !== 1 → ok=false, stale=true（调用方回退空快照）
 *   - schemaVersion=1 → ok=true，缺失字段用 0（updatedAt 先回退 envelope.updatedAt）补齐
 *
 * ArkTS 1.1 strict 适配:
 *   - JSON.parse 结果显式 as 到内部 interface，再逐字段做 typeof 校验，不直接信任外部 JSON。
 *   - 不写无类型对象字面量；每个返回值都标注了具体接口。
 */
import { CardSnapshot } from './FormCardFacade';

export const CARD_SNAPSHOT_SCHEMA_VERSION: number = 1;

const ERROR_EMPTY: string = 'EMPTY';
const ERROR_MALFORMED: string = 'MALFORMED';
const ERROR_SCHEMA_VERSION: string = 'SCHEMA_VERSION_UNSUPPORTED';

// 落盘 envelope：schemaVersion 负责识别旧版本，updatedAt 是投影时间。
export interface CardSnapshotEnvelope {
  schemaVersion: number;
  updatedAt: number;
  snapshot: CardSnapshot;
}

export interface CardSnapshotDecodeResult {
  ok: boolean;
  stale: boolean;          // schemaVersion 不认识 → true，调用方回退空快照
  envelope?: CardSnapshotEnvelope;
  error?: string;
}

// 外部 JSON 的宽松形状：所有字段都可能缺失或类型错误，解码时逐项校验。
interface CardSnapshotPayload {
  todayReviewCount?: number;
  streakDays?: number;
  newUnitCount?: number;
  masteredRatio?: number;
  updatedAt?: number;
}

interface CardSnapshotEnvelopeRaw {
  schemaVersion?: number;
  updatedAt?: number;
  snapshot?: CardSnapshotPayload | null;
}

function numberOrDefault(value: number | undefined, fallback: number): number {
  // JSON 的 1e999 会解析成 Infinity；非有限数一律回退，避免把脏值写进投影。
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function failResult(stale: boolean, error: string): CardSnapshotDecodeResult {
  const result: CardSnapshotDecodeResult = {
    ok: false,
    stale: stale,
    error: error,
  };
  return result;
}

export function encodeCardSnapshot(snapshot: CardSnapshot, updatedAt: number): string {
  const envelope: CardSnapshotEnvelope = {
    schemaVersion: CARD_SNAPSHOT_SCHEMA_VERSION,
    updatedAt: updatedAt,
    snapshot: snapshot,
  };
  return JSON.stringify(envelope);
}

export function decodeCardSnapshot(raw: string | undefined): CardSnapshotDecodeResult {
  if (raw === undefined || raw.length === 0) {
    return failResult(true, ERROR_EMPTY);
  }

  let parsed: CardSnapshotEnvelopeRaw | null | undefined = undefined;
  try {
    parsed = JSON.parse(raw) as CardSnapshotEnvelopeRaw | null;
  } catch (e) {
    return failResult(false, ERROR_MALFORMED);
  }
  if (parsed === null || parsed === undefined) {
    return failResult(false, ERROR_MALFORMED);
  }

  const version: number | undefined = parsed.schemaVersion;
  if (version !== CARD_SNAPSHOT_SCHEMA_VERSION) {
    return failResult(true, ERROR_SCHEMA_VERSION);
  }

  // 缺 snapshot / 字段缺失都不抛：用默认值补齐后再返回 ok=true。
  let payload: CardSnapshotPayload = {};
  const rawPayload: CardSnapshotPayload | null | undefined = parsed.snapshot;
  if (rawPayload !== undefined && rawPayload !== null) {
    payload = rawPayload;
  }

  const snapshotUpdatedAt: number = numberOrDefault(payload.updatedAt, 0);
  // envelope.updatedAt 缺失时回退到 snapshot.updatedAt，避免 loadResult 丢投影时间。
  const envelopeUpdatedAt: number = numberOrDefault(parsed.updatedAt, snapshotUpdatedAt);
  const snapshot: CardSnapshot = {
    todayReviewCount: numberOrDefault(payload.todayReviewCount, 0),
    streakDays: numberOrDefault(payload.streakDays, 0),
    newUnitCount: numberOrDefault(payload.newUnitCount, 0),
    masteredRatio: numberOrDefault(payload.masteredRatio, 0),
    updatedAt: numberOrDefault(payload.updatedAt, envelopeUpdatedAt),
  };

  const envelope: CardSnapshotEnvelope = {
    schemaVersion: CARD_SNAPSHOT_SCHEMA_VERSION,
    updatedAt: envelopeUpdatedAt,
    snapshot: snapshot,
  };
  const result: CardSnapshotDecodeResult = {
    ok: true,
    stale: false,
    envelope: envelope,
  };
  return result;
}
