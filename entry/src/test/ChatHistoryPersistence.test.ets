/**
 * ChatHistoryPersistence.test.ets — 聊天历史文件快照持久化行为测试(spec 021 ticket-5, #141)
 *
 * 路径: entry/src/test/ChatHistoryPersistence.test.ets
 * 职责: 验证 Preferences 迁移、文件读取、损坏文件、阻塞路径、FIFO 保存、诊断与重试恢复。
 * 依赖: @ohos/hypium; main/ets/services/ChatHistoryPersistence; ChatModels。
 *
 * 数据流:
 *   FakePreferences/FakeStore → ChatHistoryPersistence → Hypium assertions
 *
 * ArkTS 1.1 strict 适配: fake 使用显式 class/interface,不使用 any/unknown 或动态属性访问。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  CHAT_HISTORY_SCHEMA_VERSION,
  AtomicWriteStage,
  ChatHistoryLoadResult,
  ChatHistoryPersistence,
  ChatHistoryPreferencesPort,
  ChatHistorySaveResult,
  ChatHistoryStorePort,
  STREAM_SAVE_THROTTLE_MS,
} from '../main/ets/services/ChatHistoryPersistence';
import {
  ChatSession,
  copyChatSessionsForMemory,
  copyChatSessionsForPersistence,
} from '../main/ets/overlays/AgentFloatWindow/chat/ChatModels';

const SAMPLE_SESSIONS: ChatSession[] = [{
  id: 's1',
  name: '数学',
  messages: [{ id: 1, role: 'ai', content: '答案', ts: 1, streaming: false, reasoning: '思考' }],
}];

class FakePreferences implements ChatHistoryPreferencesPort {
  readonly raw: string;

  constructor(raw: string) {
    this.raw = raw;
  }

  readSessions(): string {
    return this.raw;
  }
}

class FakeStore implements ChatHistoryStorePort {
  exists: boolean = false;
  raw: string = '';
  failWrites: number = 0;
  failStage: AtomicWriteStage = 'WRITE';
  throwWrites: number = 0;
  writes: string[] = [];
  activeWrites: number = 0;
  maxActiveWrites: number = 0;
  private resolvers: Array<() => void> = [];

  async fileExists(_path: string): Promise<boolean> {
    return this.exists;
  }

  async readSnapshot(_path: string): Promise<string> {
    return this.raw;
  }

  async writeSnapshot(_path: string, sessions: ChatSession[], migratedFrom: string | undefined): Promise<ChatHistorySaveResult> {
    if (this.throwWrites > 0) {
      this.throwWrites -= 1;
      throw new Error('fake-taskpool-unavailable');
    }
    this.activeWrites += 1;
    this.maxActiveWrites = Math.max(this.maxActiveWrites, this.activeWrites);
    const index: number = this.writes.length;
    this.writes.push(JSON.stringify({ schemaVersion: CHAT_HISTORY_SCHEMA_VERSION, sessions: sessions, migratedFrom: migratedFrom }));
    await new Promise<void>((resolve: () => void): void => {
      this.resolvers.push(resolve);
    });
    this.activeWrites -= 1;
    if (this.failWrites > 0) {
      this.failWrites -= 1;
      return {
        success: false,
        state: 'failed',
        stage: this.failStage,
        transport: 'taskpool',
        retryable: true,
        diagnostic: 'stage=' + this.failStage + '; error=fake-failure-' + index.toString()
          + '; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString()
          + '; ts=1',
      };
    }
    this.raw = this.writes[index];
    this.exists = true;
    return {
      success: true,
      state: 'completed',
      stage: 'VERIFY',
      transport: 'taskpool',
      retryable: false,
      diagnostic: 'stage=VERIFY; verified=true; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString() + '; ts=1',
    };
  }

  releaseNext(): void {
    const resolver: (() => void) | undefined = this.resolvers.shift();
    if (resolver !== undefined) {
      resolver();
    }
  }

  releaseAll(): void {
    while (this.resolvers.length > 0) {
      this.releaseNext();
    }
  }
}

function wait(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, milliseconds);
  });
}

export default function chatHistoryPersistenceTest(): void {
  describe('ChatHistoryPersistence.issue141_load_contract', () => {
    it('should migrate preferences only when the new file is absent', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        store,
        new FakePreferences(JSON.stringify(SAMPLE_SESSIONS)),
        'chat-history/sessions.json',
      );
      const loading: Promise<ChatHistoryLoadResult> = persistence.load();
      await wait(0);
      store.releaseNext();
      const result: ChatHistoryLoadResult = await loading;
      expect(result.state).assertEqual('migrated');
      expect(result.diagnostic).assertContain('migratedFrom=preferences');
      expect(store.writes.length).assertEqual(1);
    });

    it('should read a valid file without consulting legacy preferences', 0, async () => {
      const store: FakeStore = new FakeStore();
      store.exists = true;
      store.raw = JSON.stringify({ schemaVersion: 1, sessions: SAMPLE_SESSIONS });
      const result: ChatHistoryLoadResult = await new ChatHistoryPersistence(
        store,
        new FakePreferences('not-json'),
        'chat-history/sessions.json',
      ).load();
      expect(result.state).assertEqual('loaded');
      expect(result.sessions[0].name).assertEqual('数学');
    });

    it('should keep a corrupt new file on the memory error path without legacy fallback', 0, async () => {
      const store: FakeStore = new FakeStore();
      store.exists = true;
      store.raw = '{corrupt';
      const result: ChatHistoryLoadResult = await new ChatHistoryPersistence(
        store,
        new FakePreferences(JSON.stringify([{ id: 'legacy', name: '旧', messages: [] }])),
        'chat-history/sessions.json',
      ).load();
      expect(result.state).assertEqual('corrupt');
      expect(result.sessions[0].id).assertEqual('s1');
      expect(store.writes.length).assertEqual(0);
    });

    it('should expose migration write failure as retryable and preserve legacy data', 0, async () => {
      const store: FakeStore = new FakeStore();
      store.failWrites = 1;
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        store,
        new FakePreferences(JSON.stringify(SAMPLE_SESSIONS)),
        'chat-history/sessions.json',
      );
      const loading: Promise<ChatHistoryLoadResult> = persistence.load();
      await wait(0);
      store.releaseNext();
      const result: ChatHistoryLoadResult = await loading;
      expect(result.state).assertEqual('migrationFailed');
      expect(result.diagnostic).assertContain('retry=true');
      expect(persistence.failureCount()).assertEqual(1);
    });

    it('should carry migration metadata only to the first successful write after migration failure', 0, async () => {
      const store: FakeStore = new FakeStore();
      store.failWrites = 1;
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        store,
        new FakePreferences(JSON.stringify(SAMPLE_SESSIONS)),
        'chat-history/sessions.json',
      );
      const loading: Promise<ChatHistoryLoadResult> = persistence.load();
      await wait(0);
      store.releaseNext();
      const result: ChatHistoryLoadResult = await loading;
      expect(result.state).assertEqual('migrationFailed');
      const save: Promise<ChatHistorySaveResult> = persistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      store.releaseNext();
      const saveResult: ChatHistorySaveResult = await save;
      expect(saveResult.success).assertTrue();
      expect(store.writes[1]).assertContain('migratedFrom');
      const secondSave: Promise<ChatHistorySaveResult> = persistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      store.releaseNext();
      await secondSave;
      expect(store.writes[2].indexOf('migratedFrom') < 0).assertTrue();
    });

    it('should not repeat migratedFrom after the migration snapshot succeeds', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        store,
        new FakePreferences(JSON.stringify(SAMPLE_SESSIONS)),
        'chat-history/sessions.json',
      );
      const loading: Promise<ChatHistoryLoadResult> = persistence.load();
      await wait(0);
      store.releaseNext();
      const result: ChatHistoryLoadResult = await loading;
      expect(result.state).assertEqual('migrated');
      expect(store.writes[0]).assertContain('migratedFrom');
      const save: Promise<ChatHistorySaveResult> = persistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      store.releaseNext();
      await save;
      expect(store.writes[1].indexOf('migratedFrom') < 0).assertTrue();
    });

    it('should block persistence without filesDir instead of falling back to preferences writes', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), '');
      const result: ChatHistorySaveResult = await persistence.save(SAMPLE_SESSIONS, true);
      expect(result.success).assertFalse();
      expect(result.stage).assertEqual('PREPARE');
      expect(result.diagnostic).assertContain('filesDir-unavailable');
      expect(store.writes.length).assertEqual(0);
    });

    it('should keep diagnostics content-safe with schema version and timestamp', 0, async () => {
      const store: FakeStore = new FakeStore();
      store.failWrites = 1;
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), 'sessions.json');
      const save: Promise<ChatHistorySaveResult> = persistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      store.releaseNext();
      const result: ChatHistorySaveResult = await save;
      expect(result.success).assertFalse();
      expect(result.diagnostic).assertContain('schemaVersion=');
      expect(result.diagnostic).assertContain('ts=');
      expect(result.diagnostic.indexOf('答案') < 0).assertTrue();
      expect(result.diagnostic.indexOf('数学') < 0).assertTrue();
      expect(result.diagnostic.indexOf('思考') < 0).assertTrue();
    });

    it('should distinguish an idle flush from an actual write stage', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), 'sessions.json');
      const result: ChatHistorySaveResult = await persistence.flush();
      expect(result.success).assertTrue();
      expect(result.state).assertEqual('idle');
      expect(result.stage === undefined).assertTrue();
      expect(result.diagnostic).assertContain('state=idle');
      expect(store.writes.length).assertEqual(0);
    });

    it('should surface prepare commit and verify stage failures for recovery handling', 0, async () => {
      const prepareStore: FakeStore = new FakeStore();
      prepareStore.failWrites = 1;
      prepareStore.failStage = 'PREPARE';
      const preparePersistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        prepareStore,
        new FakePreferences(''),
        'sessions.json',
      );
      const prepareSave: Promise<ChatHistorySaveResult> = preparePersistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      prepareStore.releaseNext();
      const prepareResult: ChatHistorySaveResult = await prepareSave;
      expect(prepareResult.stage).assertEqual('PREPARE');

      const commitStore: FakeStore = new FakeStore();
      commitStore.failWrites = 1;
      commitStore.failStage = 'COMMIT';
      const commitPersistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        commitStore,
        new FakePreferences(''),
        'sessions.json',
      );
      const commitSave: Promise<ChatHistorySaveResult> = commitPersistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      commitStore.releaseNext();
      const commitResult: ChatHistorySaveResult = await commitSave;
      expect(commitResult.stage).assertEqual('COMMIT');

      const verifyStore: FakeStore = new FakeStore();
      verifyStore.failWrites = 1;
      verifyStore.failStage = 'VERIFY';
      const verifyPersistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        verifyStore,
        new FakePreferences(''),
        'sessions.json',
      );
      const verifySave: Promise<ChatHistorySaveResult> = verifyPersistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      verifyStore.releaseNext();
      const verifyResult: ChatHistorySaveResult = await verifySave;
      expect(verifyResult.stage).assertEqual('VERIFY');
    });

    it('should normalize thrown writer failures as retryable write diagnostics', 0, async () => {
      const store: FakeStore = new FakeStore();
      store.throwWrites = 1;
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(
        store,
        new FakePreferences(''),
        'sessions.json',
      );
      const result: ChatHistorySaveResult = await persistence.save(SAMPLE_SESSIONS, true);
      expect(result.success).assertFalse();
      expect(result.stage).assertEqual('WRITE');
      expect(result.retryable).assertTrue();
      expect(result.diagnostic).assertContain('schemaVersion=');
    });
  });

  describe('ChatHistoryPersistence.issue141_queue_contract', () => {
    it('should coalesce streaming saves into the latest snapshot', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), 'sessions.json');
      persistence.save(SAMPLE_SESSIONS);
      const latest: ChatSession[] = [{ id: 's1', name: '最新', messages: [] }];
      persistence.save(latest);
      await wait(STREAM_SAVE_THROTTLE_MS + 10);
      expect(store.writes.length).assertEqual(1);
      expect(store.writes[0]).assertContain('最新');
      store.releaseAll();
    });

    it('should persist message truth without reasoningExpanded UI state', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), 'sessions.json');
      const sessions: ChatSession[] = [{
        id: 's1',
        name: '数学',
        messages: [{
          id: 1,
          role: 'ai',
          content: '答案',
          ts: 1,
          streaming: false,
          reasoning: '思考',
          reasoningExpanded: false,
        }],
      }];
      const save: Promise<ChatHistorySaveResult> = persistence.save(sessions, true);
      await wait(0);
      store.releaseNext();
      const result: ChatHistorySaveResult = await save;
      expect(result.success).assertTrue();
      expect(store.writes[0].indexOf('reasoningExpanded') < 0).assertTrue();
      expect(store.writes[0]).assertContain('思考');
    });

    it('should retain reasoningExpanded only in the in-memory working copy', 0, () => {
      const sessions: ChatSession[] = [{
        id: 's1',
        name: '数学',
        messages: [{
          id: 1,
          role: 'ai',
          content: '答案',
          ts: 1,
          streaming: true,
          reasoning: '思考',
          reasoningExpanded: false,
        }],
      }];
      const memory: ChatSession[] = copyChatSessionsForMemory(sessions);
      const snapshot: ChatSession[] = copyChatSessionsForPersistence(sessions);
      expect(memory[0].messages[0].reasoningExpanded).assertFalse();
      expect(snapshot[0].messages[0].reasoningExpanded === undefined).assertTrue();
      expect(memory[0].messages[0].streaming).assertTrue();
      expect(snapshot[0].messages[0].reasoning).assertEqual('思考');
    });

    it('should resolve an in-flight flush with the actual write result', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), 'sessions.json');
      persistence.save(SAMPLE_SESSIONS, true);
      await wait(0);
      const flushing: Promise<ChatHistorySaveResult> = persistence.flush();
      store.releaseNext();
      const result: ChatHistorySaveResult = await flushing;
      expect(result.success).assertTrue();
      expect(result.state).assertEqual('completed');
      expect(result.stage).assertEqual('VERIFY');
    });

    it('should keep one FIFO writer and force lifecycle saves through the queue', 0, async () => {
      const store: FakeStore = new FakeStore();
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), 'sessions.json');
      const first: Promise<ChatHistorySaveResult> = persistence.save(SAMPLE_SESSIONS, true);
      const secondSessions: ChatSession[] = [{ id: 's1', name: '第二次', messages: [] }];
      const second: Promise<ChatHistorySaveResult> = persistence.save(secondSessions, true);
      await wait(0);
      expect(store.maxActiveWrites).assertEqual(1);
      expect(store.writes.length).assertEqual(1);
      store.releaseNext();
      await wait(0);
      expect(store.writes.length).assertEqual(2);
      store.releaseNext();
      const firstResult: ChatHistorySaveResult = await first;
      const secondResult: ChatHistorySaveResult = await second;
      expect(firstResult.success).assertTrue();
      expect(secondResult.success).assertTrue();
      expect(store.writes[1]).assertContain('第二次');
    });

    it('should retain the failed snapshot for explicit retry and report recovery', 0, async () => {
      const store: FakeStore = new FakeStore();
      store.failWrites = 3;
      const persistence: ChatHistoryPersistence = new ChatHistoryPersistence(store, new FakePreferences(''), 'sessions.json');
      for (let i: number = 0; i < 3; i += 1) {
        const pending: Promise<ChatHistorySaveResult> = persistence.save(SAMPLE_SESSIONS, true);
        await wait(0);
        store.releaseNext();
        const result: ChatHistorySaveResult = await pending;
        expect(result.success).assertFalse();
      }
      expect(persistence.lastFailureDiagnostic()).assertContain('recovery=required');
      store.failWrites = 0;
      const retry: Promise<ChatHistorySaveResult> = persistence.retry();
      await wait(0);
      store.releaseNext();
      const result: ChatHistorySaveResult = await retry;
      expect(result.success).assertTrue();
      expect(persistence.failureCount()).assertEqual(0);
    });
  });
}
