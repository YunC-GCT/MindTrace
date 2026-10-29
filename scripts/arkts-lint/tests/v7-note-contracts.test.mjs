// #238 契约层切片 A：NoteWrite 纯判定 + CardSnapshot 编解码契约测试。
// 装载真实 .ets 源文件（TypeScript 转译 + vm），不 mock 业务逻辑。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const decisions = loadNoteReviewEtsModule('common/src/main/ets/ports/NoteWriteDecisions.ets');
const port = loadNoteReviewEtsModule('common/src/main/ets/ports/NoteWritePort.ets');
const codec = loadNoteReviewEtsModule('common/src/main/ets/kit/CardSnapshotCodec.ets');

const decideWrite = decisions.decideWrite;
const encodeCardSnapshot = codec.encodeCardSnapshot;
const decodeCardSnapshot = codec.decodeCardSnapshot;

test('ADR-0019 (c) COMMIT_KEY_REQUIRED: empty commitKey is rejected before any lookup', () => {
  const result = decideWrite(null, { commitKey: '' });
  assert.equal(result.kind, 'reject', 'ADR-0019 (d) step 1: empty commitKey must reject');
  assert.equal(result.code, 'COMMIT_KEY_REQUIRED', 'ADR-0019 (c) COMMIT_KEY_REQUIRED');
  assert.equal(result.retryable, false, 'COMMIT_KEY_REQUIRED is a caller bug, not retryable');
});

test('ADR-0019 (d) step 1 precedes step 2: empty commitKey wins over NOTE_NOT_FOUND', () => {
  const result = decideWrite(null, { commitKey: '', expectedVersion: 3 });
  assert.equal(result.kind, 'reject', 'ADR-0019 (d) step 1 must run before the expectedVersion check');
  assert.equal(result.code, 'COMMIT_KEY_REQUIRED', 'empty commitKey is rejected even when expectedVersion is stale');
  assert.equal(result.retryable, false, 'COMMIT_KEY_REQUIRED stays non-retryable');
});

test('ADR-0019 (d) step 2: missing note with positive expectedVersion is NOTE_NOT_FOUND', () => {
  const result = decideWrite(null, { commitKey: 'commit-1', expectedVersion: 3 });
  assert.equal(result.kind, 'conflict', 'ADR-0019 (d) step 2: stale expectedVersion cannot insert');
  assert.equal(result.code, 'NOTE_NOT_FOUND', 'ADR-0019 (c) NOTE_NOT_FOUND');
  assert.equal(result.retryable, false, 'NOTE_NOT_FOUND needs a new preview, not a blind retry');
});

test('ADR-0019 (d) step 3: same commitKey replay is duplicate, not a second write', () => {
  const existing = { noteId: 'note-1', version: 4, commitKey: 'commit-1' };
  const result = decideWrite(existing, { commitKey: 'commit-1' });
  assert.equal(result.kind, 'duplicate', 'ADR-0019 (d) step 3: same commitKey is idempotent replay');
  assert.equal(result.code, '', 'duplicate is a success shape, so code stays empty');
  assert.equal(result.retryable, false, 'duplicate replay is already durable');
});

test('ADR-0019 (d) step 3 precedes step 4: replay wins even when expectedVersion is stale', () => {
  const existing = { noteId: 'note-1', version: 4, commitKey: 'commit-1' };
  const result = decideWrite(existing, { commitKey: 'commit-1', expectedVersion: 2 });
  assert.equal(result.kind, 'duplicate', 'ADR-0019 (d) orders duplicate before VERSION_CONFLICT');
  assert.equal(result.code, '', 'idempotent replay must not be reported as a conflict');
});

test('ADR-0019 (d) step 4: stale expectedVersion is a non-retryable VERSION_CONFLICT', () => {
  const existing = { noteId: 'note-1', version: 4, commitKey: 'commit-old' };
  const result = decideWrite(existing, { commitKey: 'commit-2', expectedVersion: 3 });
  assert.equal(result.kind, 'conflict', 'ADR-0019 (d) step 4: CAS mismatch is a conflict');
  assert.equal(result.code, 'VERSION_CONFLICT', 'ADR-0019 (c) VERSION_CONFLICT');
  assert.equal(result.retryable, false, 'ADR-0019 (c): the same expectedVersion cannot succeed on replay');
});

test('ADR-0019 (d) step 5: approved hash mismatch is a non-retryable APPROVAL_HASH_MISMATCH', () => {
  const existing = { noteId: 'note-1', version: 2, approvedCheckpointHash: 'hash-old' };
  const result = decideWrite(existing, { commitKey: 'commit-2', approvedCheckpointHash: 'hash-new' });
  assert.equal(result.kind, 'reject', 'ADR-0019 (d) step 5: HITL approval hash must match');
  assert.equal(result.code, 'APPROVAL_HASH_MISMATCH', 'ADR-0019 (c) APPROVAL_HASH_MISMATCH');
  assert.equal(result.retryable, false, 'ADR-0019 (c): a stale candidate must be re-previewed, not resent');
});

test('ADR-0019 (d) step 5: approval hash on a missing note is rejected, never inserted', () => {
  const result = decideWrite(null, { commitKey: 'commit-2', approvedCheckpointHash: 'hash-new' });
  assert.equal(result.kind, 'reject', 'ADR-0019 (d) step 5 runs before the insert fallback');
  assert.equal(result.code, 'APPROVAL_HASH_MISMATCH', 'no existing hash can never match a supplied hash');
  assert.equal(result.retryable, false, 'ADR-0019 (c): a stale candidate must be re-previewed, not resent');
});

test('ADR-0019 (d) step 5: matching approved hash does not block an update', () => {
  const existing = { noteId: 'note-1', version: 2, approvedCheckpointHash: 'hash-1' };
  const result = decideWrite(existing, { commitKey: 'commit-2', approvedCheckpointHash: 'hash-1' });
  assert.equal(result.kind, 'update', 'matching approval hash keeps the normal update path');
  assert.equal(result.code, '', 'a successful decision carries an empty code');
  assert.equal(result.retryable, false, 'a successful decision is not retryable');
});

test('ADR-0019 (d) step 6: missing note without expectedVersion is insert', () => {
  const result = decideWrite(null, { commitKey: 'commit-1' });
  assert.equal(result.kind, 'insert', 'ADR-0019 (d) step 6: no existing row means insert');
  assert.equal(result.code, '', 'insert is a success shape, so code stays empty');
  assert.equal(result.retryable, false, 'insert does not need a retry flag');
});

test('ADR-0019 (d) step 6: existing note without CAS or hash is update', () => {
  const existing = { noteId: 'note-1', version: 7 };
  const result = decideWrite(existing, { commitKey: 'commit-1' });
  assert.equal(result.kind, 'update', 'ADR-0019 (d) step 6: existing row means update');
  assert.equal(result.code, '', 'update is a success shape, so code stays empty');
});

test('ADR-0019 (d) step 4: equal expectedVersion is update, never duplicate', () => {
  const existing = { noteId: 'note-1', version: 7, commitKey: 'commit-old' };
  const result = decideWrite(existing, { commitKey: 'commit-new', expectedVersion: 7 });
  assert.equal(result.kind, 'update', 'matching expectedVersion passes CAS and is not a replay');
  assert.equal(result.kind === 'duplicate', false, 'only a matching commitKey may be duplicate');
  assert.equal(result.code, '', 'matching CAS is a success shape');
});

test('ADR-0019 (d) NotePortError keeps code and retryable for callers', () => {
  const error = new port.NotePortError('VERSION_CONFLICT', 'cas failed', true);
  assert.equal(error.code, 'VERSION_CONFLICT', 'port errors must expose ADR-0019 code');
  assert.equal(error.retryable, true, 'port errors must expose retryable');
  assert.equal(error.message, 'cas failed', 'port errors keep the human message');
  assert.equal(error.name, 'NotePortError', 'port errors keep a stable name for logs');
  assert.equal(error instanceof port.NotePortError, true, 'NotePortError constructs through its class');
});

test('CardSnapshot codec round-trips every field and keeps updatedAt in the envelope', () => {
  const snapshot = {
    todayReviewCount: 9,
    streakDays: 4,
    newUnitCount: 12,
    masteredRatio: 0.42,
    updatedAt: 111,
  };
  const raw = encodeCardSnapshot(snapshot, 222);
  const decoded = decodeCardSnapshot(raw);
  assert.equal(decoded.ok, true, 'a valid envelope must decode');
  assert.equal(decoded.stale, false, 'schemaVersion 1 is current, so stale is false');
  // 逐字段比较：decoded 的普通对象来自 vm realm，跨 realm 的 deepStrictEqual 会因原型不同失败。
  assert.equal(decoded.envelope.snapshot.todayReviewCount, 9, 'round-trip preserves todayReviewCount');
  assert.equal(decoded.envelope.snapshot.streakDays, 4, 'round-trip preserves streakDays');
  assert.equal(decoded.envelope.snapshot.newUnitCount, 12, 'round-trip preserves newUnitCount');
  assert.equal(decoded.envelope.snapshot.masteredRatio, 0.42, 'round-trip preserves masteredRatio');
  assert.equal(decoded.envelope.snapshot.updatedAt, 111, 'round-trip preserves snapshot.updatedAt');
  assert.equal(decoded.envelope.updatedAt, 222, 'envelope updatedAt is the projection timestamp');
  assert.equal(decoded.envelope.schemaVersion, 1, 'encode stamps CARD_SNAPSHOT_SCHEMA_VERSION');
});

test('CardSnapshot codec rejects unknown schemaVersion as stale without throwing', () => {
  const raw = JSON.stringify({
    schemaVersion: 99,
    updatedAt: 1,
    snapshot: { todayReviewCount: 1, streakDays: 2, newUnitCount: 3, masteredRatio: 0.5, updatedAt: 1 },
  });
  const decoded = decodeCardSnapshot(raw);
  assert.equal(decoded.ok, false, 'unknown schemaVersion is not decodable by this caller');
  assert.equal(decoded.stale, true, 'unknown schemaVersion tells the caller to fall back');
});

test('CardSnapshot codec reports empty and malformed input without throwing', () => {
  const empty = decodeCardSnapshot('');
  assert.equal(empty.ok, false, 'empty raw is not a snapshot');
  assert.equal(empty.stale, true, 'empty raw signals fallback');
  assert.equal(empty.error, 'EMPTY', 'empty raw uses the EMPTY error code');

  const missing = decodeCardSnapshot(undefined);
  assert.equal(missing.ok, false, 'undefined raw is not a snapshot');
  assert.equal(missing.stale, true, 'undefined raw signals fallback');
  assert.equal(missing.error, 'EMPTY', 'undefined raw uses the EMPTY error code');

  const malformed = decodeCardSnapshot('{not-json');
  assert.equal(malformed.ok, false, 'malformed JSON must not throw');
  assert.equal(malformed.stale, false, 'malformed JSON is corruption, not an old schema');
  assert.equal(malformed.error, 'MALFORMED', 'malformed JSON uses the MALFORMED error code');
});

test('CardSnapshot codec falls back envelope.updatedAt to snapshot.updatedAt', () => {
  const raw = JSON.stringify({ schemaVersion: 1, snapshot: { updatedAt: 111 } });
  const decoded = decodeCardSnapshot(raw);
  assert.equal(decoded.ok, true, 'schemaVersion 1 without envelope.updatedAt is still readable');
  assert.equal(decoded.stale, false, 'missing envelope.updatedAt is not a schema mismatch');
  assert.equal(decoded.envelope.updatedAt, 111, 'envelope.updatedAt falls back to snapshot.updatedAt');
  assert.equal(decoded.envelope.snapshot.updatedAt, 111, 'snapshot.updatedAt is preserved');
});

test('CardSnapshot codec rejects non-finite numbers instead of leaking Infinity', () => {
  const raw = '{"schemaVersion":1,"updatedAt":1,"snapshot":{"todayReviewCount":1e999}}';
  const decoded = decodeCardSnapshot(raw);
  assert.equal(decoded.ok, true, 'the envelope is still readable');
  assert.equal(decoded.envelope.snapshot.todayReviewCount, 0, 'non-finite values fall back to 0');
});

test('CardSnapshot codec fills missing fields of an old snapshot with defaults', () => {
  const raw = JSON.stringify({ schemaVersion: 1, updatedAt: 77, snapshot: { todayReviewCount: 5 } });
  const decoded = decodeCardSnapshot(raw);
  assert.equal(decoded.ok, true, 'schemaVersion 1 with partial fields is still readable');
  assert.equal(decoded.stale, false, 'partial current-schema snapshot is not stale');
  assert.equal(decoded.envelope.snapshot.todayReviewCount, 5, 'present fields are preserved');
  assert.equal(decoded.envelope.snapshot.streakDays, 0, 'missing streakDays defaults to 0');
  assert.equal(decoded.envelope.snapshot.newUnitCount, 0, 'missing newUnitCount defaults to 0');
  assert.equal(decoded.envelope.snapshot.masteredRatio, 0, 'missing masteredRatio defaults to 0');
  assert.equal(decoded.envelope.snapshot.updatedAt, 77, 'missing snapshot.updatedAt falls back to envelope');
});
