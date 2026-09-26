/**
 * NoteGenerationRepository.test.ets — Issue 98 recovery seam tests.
 *
 * TDD red phase: the production contracts are intentionally introduced by
 * this focused test before their implementation.
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  NoteGenerationCheckpoint,
  NoteGenerationRepository,
  NoteGenerationRecovery,
  NoteGenerationRequest,
  NoteGenerationRun,
  NoteGenerationCommitResult,
  NoteGenerationLifecycleLog,
  SourceBundle,
  NoteGenerationCoverage,
  NoteGenerationOutline,
} from 'common';

class FakeNoteGenerationRepository implements NoteGenerationRepository {
  private runs: NoteGenerationRun[] = [];
  private checkpoints: NoteGenerationCheckpoint[] = [];
  private commits: NoteGenerationCommitResult[] = [];

  async saveRun(run: NoteGenerationRun, bundle: SourceBundle): Promise<void> {
    this.runs.push(run);
  }

  async saveCheckpoint(checkpoint: NoteGenerationCheckpoint): Promise<void> {
    const existing: NoteGenerationCheckpoint | undefined = this.checkpoints.find(
      (item: NoteGenerationCheckpoint): boolean => item.id === checkpoint.id,
    );
    if (existing === undefined) {
      this.checkpoints.push(checkpoint);
    }
  }

  async restore(runId: string): Promise<NoteGenerationRecovery | undefined> {
    const run: NoteGenerationRun | undefined = this.runs.find((item: NoteGenerationRun): boolean => item.id === runId);
    if (run === undefined) {
      return undefined;
    }
    const recovery: NoteGenerationRecovery = {
      run: run,
      sources: { fragments: [] },
      checkpoints: this.checkpoints,
      bestCheckpoint: this.checkpoints[0],
      softIssueCodes: [],
    };
    return recovery;
  }

  checkpointCount(): number {
    return this.checkpoints.length;
  }

  async saveCommitResult(_result: NoteGenerationCommitResult): Promise<void> {
    const existing: NoteGenerationCommitResult | undefined = this.commits.find(
      (item: NoteGenerationCommitResult): boolean => item.commitKey === _result.commitKey,
    );
    if (existing === undefined) {
      this.commits.push(_result);
    }
    for (const run of this.runs) {
      if (run.id === _result.runId) {
        run.status = 'committed';
        run.stopReason = 'committed';
      }
    }
  }

  async getCommitResult(_commitKey: string): Promise<NoteGenerationCommitResult | undefined> {
    return this.commits.find((item: NoteGenerationCommitResult): boolean => item.commitKey === _commitKey);
  }

  async cancelRun(_runId: string): Promise<void> {
  }

  async appendLifecycleLog(_log: NoteGenerationLifecycleLog): Promise<void> {
  }

  async listRecoverableRuns(): Promise<NoteGenerationRun[]> {
    const recoverable: NoteGenerationRun[] = [];
    for (const run of this.runs) {
      const committed: NoteGenerationCommitResult | undefined = this.commits.find(
        (item: NoteGenerationCommitResult): boolean => item.runId === run.id,
      );
      if (run.status !== 'committed' && committed === undefined) {
        recoverable.push(run);
      }
    }
    return recoverable;
  }

}

const request: NoteGenerationRequest = {
  runId: 'run-98',
  instruction: '保留公式并给出一个例子',
  mode: 'create',
  sources: {
    fragments: [{
      id: 'source-1',
      kind: 'conversation',
      originId: 'message-1',
      sequence: 0,
      fingerprint: 'fp-1',
      text: '若 f 在闭区间连续，则存在最大值。',
    }],
  },
};

export default function noteGenerationRepositoryTest(): void {
  describe('NoteGenerationRepository', () => {
    it('stores an immutable checkpoint once and restores the run', 0, async () => {
      const repository: NoteGenerationRepository = new FakeNoteGenerationRepository();
      const run: NoteGenerationRun = {
        id: request.runId,
        route: 'light',
        status: 'ready-preview',
        instruction: request.instruction,
        sourceCount: 1,
        tokenBudget: 1200,
        bestCheckpointId: 'checkpoint-1',
      };
      const checkpoint: NoteGenerationCheckpoint = {
        id: 'checkpoint-1',
        runId: request.runId,
        iteration: 0,
        stage: 'draft',
        candidateHash: 'hash-1',
        documentJson: '{}',
        accepted: true,
      };

      await repository.saveRun(run, request.sources);
      await repository.saveCheckpoint(checkpoint);
      await repository.saveCheckpoint(checkpoint);

      const restored: NoteGenerationRecovery | undefined = await repository.restore(request.runId);
      expect(restored?.run.route).assertEqual('light');
      expect(restored?.run.instruction).assertEqual(request.instruction);
      expect((repository as FakeNoteGenerationRepository).checkpointCount()).assertEqual(1);
    });

    it('persists one commit result for repeated confirmation', 0, async () => {
      const repository: NoteGenerationRepository = new FakeNoteGenerationRepository();
      const result: NoteGenerationCommitResult = {
        commitKey: 'run-98:checkpoint-1:hash-1',
        runId: 'run-98',
        checkpointId: 'checkpoint-1',
        noteId: 'note-1',
        version: 1,
        sourceIds: ['source-1'],
      };

      await repository.saveCommitResult(result);
      const first: NoteGenerationCommitResult | undefined = await repository.getCommitResult(result.commitKey);
      const second: NoteGenerationCommitResult | undefined = await repository.getCommitResult(result.commitKey);
      expect(first?.noteId).assertEqual('note-1');
      expect(second?.version).assertEqual(1);
    });

    it('does not recover a run after its note commit is durable', 0, async () => {
      const repository: NoteGenerationRepository = new FakeNoteGenerationRepository();
      const run: NoteGenerationRun = {
        id: 'run-committed-recovery', route: 'light', status: 'ready-preview',
        instruction: 'create note', sourceCount: 1, tokenBudget: 1200,
      };
      const result: NoteGenerationCommitResult = {
        commitKey: 'run-committed-recovery:checkpoint-1:hash-1',
        runId: run.id,
        checkpointId: 'checkpoint-1',
        noteId: 'note-committed-recovery',
        version: 1,
        sourceIds: ['source-1'],
      };

      await repository.saveRun(run, { fragments: [] });
      await repository.saveCommitResult(result);

      const recoverable: NoteGenerationRun[] = await repository.listRecoverableRuns();
      expect(recoverable.length).assertEqual(0);
      const restored: NoteGenerationRecovery | undefined = await repository.restore(run.id);
      expect(restored?.run.status).assertEqual('committed');
    });

    it('keeps a checkpoint immutable when the same id is saved again', 0, async () => {
      const repository: NoteGenerationRepository = new FakeNoteGenerationRepository();
      const first: NoteGenerationCheckpoint = {
        id: 'immutable-101', runId: 'run-98', iteration: 0, stage: 'draft',
        candidateHash: 'first', documentJson: '{"title":"first"}', accepted: true,
        coverage: { mustInclude: 0.5, evidence: 0.5, lockedPreservation: 1 } as NoteGenerationCoverage,
        tokenCost: 100, decision: 'initial', issueFingerprint: 'EVIDENCE:source:section',
      };
      const changed: NoteGenerationCheckpoint = {
        id: 'immutable-101', runId: 'run-98', iteration: 1, stage: 'truth_check',
        candidateHash: 'changed', documentJson: '{"title":"changed"}', accepted: false,
        coverage: { mustInclude: 1, evidence: 1, lockedPreservation: 0 } as NoteGenerationCoverage,
        tokenCost: 900, decision: 'best', issueFingerprint: 'different',
      };
      await repository.saveCheckpoint(first);
      await repository.saveCheckpoint(changed);
      const restored: NoteGenerationRecovery | undefined = await repository.restore('run-98');
      expect(restored?.checkpoints[0].candidateHash).assertEqual('first');
      expect(restored?.checkpoints[0].documentJson).assertEqual('{"title":"first"}');
      expect(restored?.checkpoints[0].tokenCost).assertEqual(100);
      expect(restored?.checkpoints[0].decision).assertEqual('initial');
    });

    it('restores a complete deep outline checkpoint without losing source mapping', 0, async () => {
      const repository: NoteGenerationRepository = new FakeNoteGenerationRepository();
      const outline: NoteGenerationOutline = {
        schemaVersion: 'mindtrace.note-outline.v1',
        sections: [{ id: 'section-proof', label: '证明', order: 0, mustInclude: ['推导'], sourceIds: ['ocr-1'], depth: 0, segmentIds: ['ocr-1#0'] }, {
          id: 'section-tail', label: '尾部结论', order: 1, mustInclude: ['结论'], sourceIds: ['ocr-2'], depth: 1, parentId: 'section-proof', segmentIds: ['ocr-2#0'],
        }],
      };
      const run: NoteGenerationRun = {
        id: 'deep-recovery-103', route: 'deep', status: 'ready-preview', instruction: '完整证明', sourceCount: 2, tokenBudget: 14000,
      };
      const checkpoint: NoteGenerationCheckpoint = {
        id: 'deep-recovery-103:0', runId: run.id, iteration: 0, stage: 'truth_check', candidateHash: 'deep-hash',
        documentJson: '{"tail":"preserved"}', accepted: true, outlineJson: JSON.stringify(outline), issueCodes: [], decision: 'best',
      };
      await repository.saveRun(run, { fragments: [{ id: 'ocr-1', kind: 'ocr', originId: 'page-1', sequence: 0, fingerprint: '1', text: '证明' }, {
        id: 'ocr-2', kind: 'ocr', originId: 'page-2', sequence: 1, fingerprint: '2', text: '尾部结论',
      }] });
      await repository.saveCheckpoint(checkpoint);
      const restored: NoteGenerationRecovery | undefined = await repository.restore(run.id);
      expect(restored?.run.route).assertEqual('deep');
      expect(restored?.sources.fragments.length).assertEqual(0);
      expect(restored?.checkpoints[0].outlineJson).assertEqual(JSON.stringify(outline));
      expect(restored?.checkpoints[0].outlineJson?.includes('ocr-2')).assertTrue();
    });
  });
}
