/**
 * NoteGenerationRepository.ets — recoverable Issue 98 generation artifacts.
 *
 * This repository owns only generation side tables. KnowledgeUnit writes stay
 * in NoteDao and are deliberately not reachable from this class.
 */
import { relationalStore } from '@kit.ArkData';
import {
  NoteGenerationCheckpoint,
  NoteGenerationCoverage,
  NoteGenerationCommitResult,
  NoteGenerationLifecycleLog,
  NoteGenerationRepository as NoteGenerationRepositoryContract,
  NoteGenerationRecovery,
  NoteGenerationRun,
  SourceBundle,
  SourceFragment,
  KnowledgeUnit,
  IncrementalBase,
  IncrementalSection,
  IncrementalManifestSection,
  IncrementalManifest,
  parseIncrementalSections,
} from 'common';
import { NoteGenerationBaseProvider } from '../models/KnowledgeUnitWriteModels';
import { ConversationRunIdPolicy, SessionIdPolicy } from '../services/ConversationIdentity';

export class NoteGenerationRepository implements NoteGenerationRepositoryContract {
  private store: relationalStore.RdbStore;
  private baseProvider: NoteGenerationBaseProvider | undefined;

  constructor(store: relationalStore.RdbStore, baseProvider?: NoteGenerationBaseProvider) {
    this.store = store;
    this.baseProvider = baseProvider;
  }

  async saveRun(run: NoteGenerationRun, bundle: SourceBundle): Promise<void> {
    const runBucket: relationalStore.ValuesBucket = {
      'id': run.id,
      'route': run.route,
      'status': run.status,
      'instruction': run.instruction,
      'source_count': run.sourceCount,
      'token_budget': run.tokenBudget,
      'best_checkpoint_id': run.bestCheckpointId ?? '',
      'stop_reason': run.stopReason ?? '',
      'issue_count': run.issueCount ?? 0,
      'origin_session_id': run.originSessionId ?? '',
      'parent_conversation_run_id': run.parentConversationRunId ?? '',
      'source_ids': JSON.stringify(run.sourceIds ?? []),
      'pending_source_ids': JSON.stringify(run.pendingSourceIds ?? []),
      'source_summary': run.sourceSummary ?? '',
      'created_at': run.createdAt ?? Date.now(),
      'updated_at': run.updatedAt ?? Date.now(),
    };
    const runExists: boolean = await this.hasRow('note_generation_run', 'id', run.id);
    if (runExists) {
      const runPredicates = new relationalStore.RdbPredicates('note_generation_run');
      runPredicates.equalTo('id', run.id);
      await new Promise<void>((resolve, reject) => {
        this.store.update(runBucket, runPredicates, (error: Error, _rows: number): void => {
          if (error) {
            reject(new Error('NoteGenerationRepository.updateRun failed: ' + error.message));
            return;
          }
          resolve();
        });
      });
    } else {
      await this.insertRow('note_generation_run', runBucket);
    }
    for (const fragment of bundle.fragments) {
      const sourceBucket: relationalStore.ValuesBucket = {
        'id': fragment.id,
        'run_id': run.id,
        'kind': fragment.kind,
        'origin_id': fragment.originId,
        'sequence': fragment.sequence,
        'fingerprint': fragment.fingerprint,
        'text': fragment.text,
      };
      if (!(await this.hasSource(run.id, fragment.id))) {
        await this.insertRow('note_generation_source', sourceBucket);
      }
    }
  }

  async saveCheckpoint(checkpoint: NoteGenerationCheckpoint): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'id': checkpoint.id,
      'run_id': checkpoint.runId,
      'iteration': checkpoint.iteration,
      'stage': checkpoint.stage,
      'parent_id': checkpoint.parentId ?? '',
      'candidate_hash': checkpoint.candidateHash,
      'document_json': checkpoint.documentJson,
      'accepted': checkpoint.accepted ? 1 : 0,
      'issue_codes': JSON.stringify(checkpoint.issueCodes ?? []),
      'outline_json': checkpoint.outlineJson ?? '',
      'evidence_json': checkpoint.evidenceJson ?? '',
      'verification_json': checkpoint.verificationJson ?? '',
      'issue_fingerprint': checkpoint.issueFingerprint ?? '',
      'coverage_json': checkpoint.coverage === undefined ? '' : JSON.stringify(checkpoint.coverage),
      'token_cost': checkpoint.tokenCost ?? 0,
      'change_scope': checkpoint.changeScope ?? 0,
      'decision': checkpoint.decision ?? 'rejected',
      'created_at': checkpoint.createdAt ?? Date.now(),
    };
    const exists: boolean = await this.hasRow('note_generation_checkpoint', 'id', checkpoint.id);
    if (exists) {
      // Checkpoints are immutable artifacts. A repeated id is an idempotent save,
      // never an opportunity to replace the candidate or its verification report.
      return;
    }
    await this.insertRow('note_generation_checkpoint', bucket);
  }

  private async hasRow(table: string, column: string, value: string): Promise<boolean> {
    const predicates = new relationalStore.RdbPredicates(table);
    predicates.equalTo(column, value);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, [column]);
    const found: boolean = resultSet.goToFirstRow();
    resultSet.close();
    return found;
  }

  private async hasSource(runId: string, sourceId: string): Promise<boolean> {
    const predicates = new relationalStore.RdbPredicates('note_generation_source');
    predicates.equalTo('run_id', runId);
    predicates.equalTo('id', sourceId);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['id']);
    const found: boolean = resultSet.goToFirstRow();
    resultSet.close();
    return found;
  }

  private async insertRow(table: string, bucket: relationalStore.ValuesBucket): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      this.store.insert(table, bucket, (error: Error, _rowId: number): void => {
        if (error) {
          reject(new Error('NoteGenerationRepository.insert failed: ' + error.message));
          return;
        }
        resolve();
      });
    });
  }

  async restore(runId: string): Promise<NoteGenerationRecovery | undefined> {
    const runPredicates = new relationalStore.RdbPredicates('note_generation_run');
    runPredicates.equalTo('id', runId);
    const runSet: relationalStore.ResultSet = await this.store.query(runPredicates, ['*']);
    if (!runSet.goToFirstRow()) {
      runSet.close();
      return undefined;
    }
    const run: NoteGenerationRun = NoteGenerationRepository.rowToRun(runSet);
    runSet.close();

    const sourcePredicates = new relationalStore.RdbPredicates('note_generation_source');
    sourcePredicates.equalTo('run_id', runId);
    sourcePredicates.orderByAsc('sequence');
    const sourceSet: relationalStore.ResultSet = await this.store.query(sourcePredicates, ['*']);
    const fragments: SourceFragment[] = [];
    if (sourceSet.goToFirstRow()) {
      do {
        fragments.push(NoteGenerationRepository.rowToSource(sourceSet));
      } while (sourceSet.goToNextRow());
    }
    sourceSet.close();

    const checkpointPredicates = new relationalStore.RdbPredicates('note_generation_checkpoint');
    checkpointPredicates.equalTo('run_id', runId);
    checkpointPredicates.orderByAsc('iteration');
    const checkpointSet: relationalStore.ResultSet = await this.store.query(checkpointPredicates, ['*']);
    const checkpoints: NoteGenerationCheckpoint[] = [];
    if (checkpointSet.goToFirstRow()) {
      do {
        checkpoints.push(NoteGenerationRepository.rowToCheckpoint(checkpointSet));
      } while (checkpointSet.goToNextRow());
    }
    checkpointSet.close();
    let bestCheckpoint: NoteGenerationCheckpoint | undefined = undefined;
    if (run.bestCheckpointId !== undefined) {
      for (const checkpoint of checkpoints) {
        if (checkpoint.id === run.bestCheckpointId) {
          bestCheckpoint = checkpoint;
          break;
        }
      }
    }
    const softIssueCodes: string[] = [];
    for (const checkpoint of checkpoints) {
      if (checkpoint.accepted) {
        for (const code of checkpoint.issueCodes ?? []) {
          if (!softIssueCodes.includes(code)) {
            softIssueCodes.push(code);
          }
        }
      }
    }
    if (run.status === 'running') {
      run.status = 'incomplete';
      run.stopReason = 'app_interrupted';
      const interruptedPredicates = new relationalStore.RdbPredicates('note_generation_run');
      interruptedPredicates.equalTo('id', runId);
      const interruptedBucket: relationalStore.ValuesBucket = {
        'status': 'incomplete',
        'stop_reason': 'app_interrupted',
        'updated_at': Date.now(),
      };
      await new Promise<void>((resolve, reject) => {
        this.store.update(interruptedBucket, interruptedPredicates, (error: Error, _rows: number): void => {
          if (error) {
            reject(new Error('NoteGenerationRepository.markInterrupted failed: ' + error.message));
            return;
          }
          resolve();
        });
      });
    }
    return {
      run: run,
      sources: { fragments: fragments },
      checkpoints: checkpoints,
      bestCheckpoint: bestCheckpoint,
      softIssueCodes: softIssueCodes,
    };
  }

  async saveCommitResult(result: NoteGenerationCommitResult): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'commit_key': result.commitKey,
      'run_id': result.runId,
      'checkpoint_id': result.checkpointId,
      'note_id': result.noteId,
      'version': result.version,
      'source_ids': JSON.stringify(result.sourceIds),
      'candidate_json': result.candidateJson ?? '',
      'committed_at': result.committedAt ?? Date.now(),
      'generation_metadata': result.generationMetadata ?? '',
    };
    if (await this.hasRow('note_generation_commit', 'commit_key', result.commitKey)) {
      const predicates = new relationalStore.RdbPredicates('note_generation_commit');
      predicates.equalTo('commit_key', result.commitKey);
      await new Promise<void>((resolve, reject) => {
        this.store.update(bucket, predicates, (error: Error, _rows: number): void => {
          if (error) {
            reject(new Error('NoteGenerationRepository.updateCommitResult failed: ' + error.message));
            return;
          }
          resolve();
        });
      });
    } else {
      await this.insertRow('note_generation_commit', bucket);
    }
    await this.markRunCommitted(result.runId);
  }

  private async markRunCommitted(runId: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('note_generation_run');
    predicates.equalTo('id', runId);
    const bucket: relationalStore.ValuesBucket = {
      'status': 'committed',
      'stop_reason': 'committed',
      'updated_at': Date.now(),
    };
    await new Promise<void>((resolve, reject) => {
      this.store.update(bucket, predicates, (error: Error, _rows: number): void => {
        if (error) {
          reject(new Error('NoteGenerationRepository.markRunCommitted failed: ' + error.message));
          return;
        }
        resolve();
      });
    });
  }

  private async hasCommitForRun(runId: string): Promise<boolean> {
    return await this.hasRow('note_generation_commit', 'run_id', runId);
  }

  async getCommitResult(commitKey: string): Promise<NoteGenerationCommitResult | undefined> {
    const predicates = new relationalStore.RdbPredicates('note_generation_commit');
    predicates.equalTo('commit_key', commitKey);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    if (!resultSet.goToFirstRow()) {
      resultSet.close();
      return undefined;
    }
    const sourceText: string = resultSet.getString(resultSet.getColumnIndex('source_ids'));
    let sourceIds: string[] = [];
    try {
      sourceIds = JSON.parse(sourceText) as string[];
    } catch (e) {
      sourceIds = [];
    }
    const result: NoteGenerationCommitResult = {
      commitKey: resultSet.getString(resultSet.getColumnIndex('commit_key')),
      runId: resultSet.getString(resultSet.getColumnIndex('run_id')),
      checkpointId: resultSet.getString(resultSet.getColumnIndex('checkpoint_id')),
      noteId: resultSet.getString(resultSet.getColumnIndex('note_id')),
      version: resultSet.getLong(resultSet.getColumnIndex('version')),
      sourceIds: sourceIds,
      candidateJson: resultSet.getString(resultSet.getColumnIndex('candidate_json')),
      committedAt: resultSet.getLong(resultSet.getColumnIndex('committed_at')),
    };
    resultSet.close();
    return result;
  }

  async cancelRun(runId: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('note_generation_run');
    predicates.equalTo('id', runId);
    const bucket: relationalStore.ValuesBucket = { 'status': 'cancelled', 'updated_at': Date.now(), 'stop_reason': 'cancelled' };
    await new Promise<void>((resolve, reject) => {
      this.store.update(bucket, predicates, (error: Error, _rows: number): void => {
        if (error) {
          reject(new Error('NoteGenerationRepository.cancelRun failed: ' + error.message));
          return;
        }
        resolve();
      });
    });
  }

  async appendLifecycleLog(log: NoteGenerationLifecycleLog): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'run_id': log.runId,
      'event': log.event,
      'checkpoint_id': log.checkpointId ?? '',
      'issue_count': log.issueCount ?? 0,
      'source_count': log.sourceCount ?? 0,
      'round': log.round ?? 0,
      'stop_reason': log.stopReason ?? '',
      'rollback': log.rollback === true ? 1 : 0,
      'created_at': log.createdAt ?? Date.now(),
    };
    await this.insertRow('note_generation_log', bucket);
  }

  async listRecoverableRuns(): Promise<NoteGenerationRun[]> {
    const predicates = new relationalStore.RdbPredicates('note_generation_run');
    predicates.orderByDesc('updated_at');
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    const candidates: NoteGenerationRun[] = [];
    if (resultSet.goToFirstRow()) {
      do {
        const run: NoteGenerationRun = NoteGenerationRepository.rowToRun(resultSet);
        if (run.status === 'running' || run.status === 'ready-preview' || run.status === 'incomplete'
          || run.status === 'failed' || run.status === 'needs-input') {
          candidates.push(run);
        }
      } while (resultSet.goToNextRow());
    }
    resultSet.close();
    const runs: NoteGenerationRun[] = [];
    for (const candidate of candidates) {
      // The KnowledgeUnit and its commit marker are written in one transaction.
      // Treat that durable marker as authoritative even when the process stopped
      // before the generation run could be advanced to its terminal status.
      if (await this.hasCommitForRun(candidate.id)) {
        await this.markRunCommitted(candidate.id);
      } else {
        runs.push(candidate);
      }
    }
    return runs;
  }

  async listIncompleteByOriginSession(sessionId: string): Promise<NoteGenerationRun[]> {
    SessionIdPolicy.requireValid(sessionId);
    const predicates = new relationalStore.RdbPredicates('note_generation_run');
    predicates.equalTo('origin_session_id', sessionId);
    predicates.orderByDesc('updated_at');
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    const runs: NoteGenerationRun[] = [];
    if (resultSet.goToFirstRow()) {
      do {
        const run: NoteGenerationRun = NoteGenerationRepository.rowToRun(resultSet);
        if (run.status !== 'committed') { runs.push(run); }
      } while (resultSet.goToNextRow());
    }
    resultSet.close();
    return runs;
  }

  async listIncompleteByParentRun(sessionId: string, parentConversationRunId: string): Promise<NoteGenerationRun[]> {
    SessionIdPolicy.requireValid(sessionId);
    ConversationRunIdPolicy.requireValid(parentConversationRunId);
    const predicates = new relationalStore.RdbPredicates('note_generation_run');
    predicates.equalTo('origin_session_id', sessionId);
    predicates.equalTo('parent_conversation_run_id', parentConversationRunId);
    predicates.orderByDesc('updated_at');
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    const runs: NoteGenerationRun[] = [];
    if (resultSet.goToFirstRow()) {
      do {
        const run: NoteGenerationRun = NoteGenerationRepository.rowToRun(resultSet);
        if (run.status !== 'committed') { runs.push(run); }
      } while (resultSet.goToNextRow());
    }
    resultSet.close();
    return runs;
  }

  async cancelIncompleteByParentRun(sessionId: string, parentConversationRunId: string): Promise<void> {
    const runs: NoteGenerationRun[] = await this.listIncompleteByParentRun(sessionId, parentConversationRunId);
    for (const run of runs) { await this.cancelRun(run.id); }
  }

  async getRegenerationBase(noteId: string): Promise<IncrementalBase | undefined> {
    if (this.baseProvider === undefined) {
      return undefined;
    }
    const unit = await this.baseProvider.queryCurrentUnit(noteId);
    if (unit === null) {
      return undefined;
    }
    const latest = this.baseProvider.queryLatestGeneratedRevision === undefined
      ? await this.baseProvider.queryLatestRevision(noteId)
      : await this.baseProvider.queryLatestGeneratedRevision(noteId);
    let manifest: IncrementalManifest;
    if (latest !== null && latest.generationMetadata.trim().length > 0) {
      try {
        const parsed: IncrementalManifest = JSON.parse(latest.generationMetadata) as IncrementalManifest;
        if (parsed.noteId === noteId && parsed.sections !== undefined) {
          manifest = parsed;
        } else {
          manifest = this.fallbackManifest(unit);
        }
      } catch (e) {
        manifest = this.fallbackManifest(unit);
      }
    } else {
      manifest = this.fallbackManifest(unit);
    }
    const fragments: SourceFragment[] = [];
    for (const sourceId of manifest.sourceIds) {
      const source = await this.findSource(sourceId);
      if (source !== undefined) {
        fragments.push(source);
      }
    }
    return { unit: unit, manifest: manifest, sources: { fragments: fragments }, baseVersion: unit.version };
  }

  private fallbackManifest(unit: KnowledgeUnit): IncrementalManifest {
    const parsedSections: IncrementalSection[] = parseIncrementalSections(unit.content);
    const manifestSections: IncrementalManifestSection[] = [];
    for (const section of parsedSections) {
      manifestSections.push({
        id: section.id,
        label: section.label,
        generatedHash: section.contentHash,
        sourceIds: section.sourceIds.slice(0),
      });
    }
    const sourceIds: string[] = [];
    for (const section of parsedSections) {
      for (const sourceId of section.sourceIds) {
        if (!sourceIds.includes(sourceId)) {
          sourceIds.push(sourceId);
        }
      }
    }
    return {
      noteId: unit.id,
      baseVersion: unit.version,
      sections: manifestSections,
      sourceIds: sourceIds,
      createdAt: Date.now(),
    };
  }

  private async findSource(sourceId: string): Promise<SourceFragment | undefined> {
    const predicates = new relationalStore.RdbPredicates('note_generation_source');
    predicates.equalTo('id', sourceId);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    if (!resultSet.goToFirstRow()) {
      resultSet.close();
      return undefined;
    }
    const source: SourceFragment = NoteGenerationRepository.rowToSource(resultSet);
    resultSet.close();
    return source;
  }

  private static rowToRun(rs: relationalStore.ResultSet): NoteGenerationRun {
    const sourceText: string = NoteGenerationRepository.readOptionalString(rs, 'source_ids');
    let sourceIds: string[] = [];
    try {
      sourceIds = JSON.parse(sourceText) as string[];
    } catch (e) {
      sourceIds = [];
    }
    const pendingSourceText: string = NoteGenerationRepository.readOptionalString(rs, 'pending_source_ids');
    let pendingSourceIds: string[] = [];
    try {
      pendingSourceIds = JSON.parse(pendingSourceText) as string[];
    } catch (e) {
      pendingSourceIds = [];
    }
    const result: NoteGenerationRun = {
      id: rs.getString(rs.getColumnIndex('id')),
      originSessionId: NoteGenerationRepository.readOptionalString(rs, 'origin_session_id') || undefined,
      parentConversationRunId: NoteGenerationRepository.readOptionalString(rs, 'parent_conversation_run_id') || undefined,
      route: rs.getString(rs.getColumnIndex('route')) as 'light' | 'standard' | 'deep',
      status: rs.getString(rs.getColumnIndex('status')) as 'running' | 'incomplete' | 'ready-preview' | 'needs-input' | 'failed' | 'cancelled' | 'committed',
      instruction: rs.getString(rs.getColumnIndex('instruction')),
      sourceCount: rs.getLong(rs.getColumnIndex('source_count')),
      tokenBudget: rs.getLong(rs.getColumnIndex('token_budget')),
      bestCheckpointId: rs.getString(rs.getColumnIndex('best_checkpoint_id')) || undefined,
      stopReason: rs.getString(rs.getColumnIndex('stop_reason')) || undefined,
      issueCount: rs.getLong(rs.getColumnIndex('issue_count')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at')),
      sourceIds: sourceIds,
      pendingSourceIds: pendingSourceIds,
      sourceSummary: NoteGenerationRepository.readOptionalString(rs, 'source_summary') || undefined,
    };
    return result;
  }

  private static readOptionalString(rs: relationalStore.ResultSet, column: string): string {
    try {
      const index: number = rs.getColumnIndex(column);
      return index >= 0 ? rs.getString(index) : '';
    } catch (e) {
      return '';
    }
  }

  private static rowToSource(rs: relationalStore.ResultSet): SourceFragment {
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      kind: rs.getString(rs.getColumnIndex('kind')) as 'conversation' | 'ocr' | 'summary' | 'existing_note',
      originId: rs.getString(rs.getColumnIndex('origin_id')),
      sequence: rs.getLong(rs.getColumnIndex('sequence')),
      fingerprint: rs.getString(rs.getColumnIndex('fingerprint')),
      text: rs.getString(rs.getColumnIndex('text')),
    };
  }

  private static rowToCheckpoint(rs: relationalStore.ResultSet): NoteGenerationCheckpoint {
    const issueText: string = rs.getString(rs.getColumnIndex('issue_codes'));
    let issueCodes: string[] = [];
    try {
      issueCodes = JSON.parse(issueText) as string[];
    } catch (e) {
      issueCodes = [];
    }
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      runId: rs.getString(rs.getColumnIndex('run_id')),
      iteration: rs.getLong(rs.getColumnIndex('iteration')),
      stage: rs.getString(rs.getColumnIndex('stage')) as 'draft' | 'truth_check',
      parentId: rs.getString(rs.getColumnIndex('parent_id')) || undefined,
      candidateHash: rs.getString(rs.getColumnIndex('candidate_hash')),
      documentJson: rs.getString(rs.getColumnIndex('document_json')),
      accepted: rs.getLong(rs.getColumnIndex('accepted')) === 1,
      issueCodes: issueCodes,
      outlineJson: NoteGenerationRepository.readOptionalString(rs, 'outline_json') || undefined,
      evidenceJson: NoteGenerationRepository.readOptionalString(rs, 'evidence_json') || undefined,
      verificationJson: NoteGenerationRepository.readOptionalString(rs, 'verification_json') || undefined,
      issueFingerprint: NoteGenerationRepository.readOptionalString(rs, 'issue_fingerprint') || undefined,
      coverage: NoteGenerationRepository.readCoverage(rs),
      tokenCost: NoteGenerationRepository.readOptionalNumber(rs, 'token_cost'),
      changeScope: NoteGenerationRepository.readOptionalNumber(rs, 'change_scope'),
      decision: NoteGenerationRepository.readOptionalString(rs, 'decision') as 'best' | 'rejected' | 'initial' | undefined,
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
    };
  }

  private static readOptionalNumber(rs: relationalStore.ResultSet, column: string): number | undefined {
    try {
      const index: number = rs.getColumnIndex(column);
      return index >= 0 ? rs.getLong(index) : undefined;
    } catch (e) {
      return undefined;
    }
  }

  private static readCoverage(rs: relationalStore.ResultSet): NoteGenerationCoverage | undefined {
    const text: string = NoteGenerationRepository.readOptionalString(rs, 'coverage_json');
    if (text.length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(text) as NoteGenerationCoverage;
    } catch (e) {
      return undefined;
    }
  }
}
