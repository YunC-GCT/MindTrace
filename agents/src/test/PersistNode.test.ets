/**
 * PersistNode.test.ets — PersistNode insertWithCommitKey 结果检查行为测试
 *
 * 路径: agents/src/test/PersistNode.test.ets
 * 职责: 验证 PersistNode 对 insertWithCommitKey 返回结果的分支处理
 *   (成功 / 幂等 duplicate / success=false 失败 / 缺省 errorCode / 失败保留 payload)
 * 依赖: @ohos/hypium, common (KnowledgeUnit / NoteGenerationCommitResult / PreparedCandidate)
 *
 * 数据流:
 *   PersistNodeFactory.create(fakeDao) → node(state) → 断言 state.error / state.commitResult
 *
 * 背景: P1-A 修复 — insert 分支原先不检查 success === false, 数据库写入失败会被当成
 * 成功继续走 END, 造成 "假成功" (更新分支自 D2 起已有对称检查)。
 *
 * ArkTS 1.1 strict 适配:
 *   - FakeInsertDao 用类实现 NoteDaoInterface, 避免对象字面量结构类型
 */

import { describe, it, expect } from '@ohos/hypium';
import { PersistNodeFactory } from '../main/ets/graph/nodes/PersistNode';
import { AgentState } from '../main/ets/graph/AgentState';
import { NoteDaoInterface, NoteCommitResult } from '../main/ets/models/NoteDaoInterface';
import {
  KnowledgeUnit,
  NoteGenerationCommitResult,
  PreparedCandidate,
  DifficultyLevel,
  ReviewStatus,
} from 'common';

class FakeInsertDao implements NoteDaoInterface {
  public result: NoteCommitResult = {
    commitKey: 'ck-test',
    rowId: 1,
    noteId: 'note-1',
    version: 1,
    duplicate: false,
    success: true,
  };

  insert(unit: KnowledgeUnit): Promise<number> {
    return Promise.resolve(1);
  }

  insertWithCommitKey(unit: KnowledgeUnit, commit: NoteGenerationCommitResult): Promise<NoteCommitResult> {
    return Promise.resolve(this.result);
  }
}

function unit(): KnowledgeUnit {
  const u: KnowledgeUnit = {
    id: 'unit-1',
    title: '微分中值定理',
    content: '若 f 在 [a,b] 连续且在 (a,b) 可导...',
    summary: '连续 + 可导 ⇒ 存在 ξ 使 f\'(ξ) = (f(b)-f(a))/(b-a)',
    tags: ['微分学'],
    subject: '高等数学',
    category: '定理',
    chapter: '微分中值定理',
    difficulty: DifficultyLevel.MEDIUM,
    source: 'manual',
    createdAt: 1700000000000,
    updatedAt: 1700000000000,
    reviewStatus: ReviewStatus.NEW,
    nextReviewAt: 1700000000000,
    intervalDays: 0,
    easeFactor: 2.5,
    repetitions: 0,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: 'user-1',
    version: 1,
  };
  return u;
}

function state(u: KnowledgeUnit): AgentState {
  const candidate: PreparedCandidate = {
    runId: 'run-1',
    checkpointId: 'cp-1',
    candidateHash: 'hash-1',
    candidate: u,
    commitKey: 'ck-test',
    pendingSourceIds: ['src-1'],
    updateExisting: false,
  };
  const s: AgentState = {
    captureText: 'x + 1 = 2',
    source: 'manual',
    currentStep: 'persist',
    persist: true,
    analysisOnly: false,
    knowledgeUnit: u,
    preparedCandidate: candidate,
  };
  return s;
}

export default function persistNodeTest(): void {
  describe('PersistNode.insert_commit_result', () => {
    it('insert_success_sets_commit_result_without_error', 0, async () => {
      const dao: FakeInsertDao = new FakeInsertDao();
      dao.result = {
        commitKey: 'ck-test',
        rowId: 7,
        noteId: 'unit-1',
        version: 1,
        duplicate: false,
        success: true,
      };
      const u: KnowledgeUnit = unit();
      const node = PersistNodeFactory.create(dao);
      const result = await node(state(u));
      expect(result.state.error === undefined).assertTrue();
      expect(result.state.commitResult !== undefined).assertTrue();
      expect(result.state.commitResult?.rowId).assertEqual(7);
    });

    it('insert_duplicate_with_success_is_idempotent_success', 0, async () => {
      const dao: FakeInsertDao = new FakeInsertDao();
      dao.result = {
        commitKey: 'ck-test',
        rowId: 1,
        noteId: 'unit-1',
        version: 1,
        duplicate: true,
        success: true,
      };
      const u: KnowledgeUnit = unit();
      const node = PersistNodeFactory.create(dao);
      const result = await node(state(u));
      expect(result.state.error === undefined).assertTrue();
      expect(result.state.commitResult !== undefined).assertTrue();
      expect(result.state.commitResult?.duplicate).assertTrue();
    });

    it('insert_failure_sets_persist_error_with_code', 0, async () => {
      const dao: FakeInsertDao = new FakeInsertDao();
      dao.result = {
        commitKey: 'ck-test',
        rowId: -1,
        noteId: 'unit-1',
        version: 1,
        duplicate: false,
        success: false,
        errorCode: 'PERSIST_CONFLICT',
        errorMessage: 'commit key conflict',
      };
      const u: KnowledgeUnit = unit();
      const node = PersistNodeFactory.create(dao);
      const result = await node(state(u));
      expect(result.state.error !== undefined).assertTrue();
      expect(result.state.error?.kind).assertEqual('PERSIST_CONFLICT');
      expect(result.state.error?.message).assertEqual('commit key conflict');
      expect(result.state.error?.step).assertEqual('persist');
      expect(result.state.error?.retriable).assertFalse();
      expect(result.state.commitResult === undefined).assertTrue();
    });

    it('insert_failure_without_code_defaults_to_persist_error', 0, async () => {
      const dao: FakeInsertDao = new FakeInsertDao();
      dao.result = {
        commitKey: 'ck-test',
        rowId: -1,
        noteId: 'unit-1',
        version: 1,
        duplicate: false,
        success: false,
      };
      const u: KnowledgeUnit = unit();
      const node = PersistNodeFactory.create(dao);
      const result = await node(state(u));
      expect(result.state.error !== undefined).assertTrue();
      expect(result.state.error?.kind).assertEqual('PERSIST_ERROR');
      expect(result.state.error?.message).assertEqual('KnowledgeUnit insert failed');
    });

    it('insert_failure_keeps_knowledge_unit_payload', 0, async () => {
      const dao: FakeInsertDao = new FakeInsertDao();
      dao.result = {
        commitKey: 'ck-test',
        rowId: -1,
        noteId: 'unit-1',
        version: 1,
        duplicate: false,
        success: false,
        errorCode: 'PERSIST_CONFLICT',
        errorMessage: 'commit key conflict',
      };
      const u: KnowledgeUnit = unit();
      const node = PersistNodeFactory.create(dao);
      const result = await node(state(u));
      expect(result.state.knowledgeUnit !== undefined).assertTrue();
      expect(result.state.knowledgeUnit?.id).assertEqual('unit-1');
      expect(result.state.persist).assertTrue();
    });
  });
}
