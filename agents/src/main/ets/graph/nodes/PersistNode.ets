// MindTrace - PersistNode
// 2026-09-05 · D2 Ticket #5
import { AgentState, CaptureNode, CaptureGraphError, CaptureNodeResult, copyAgentState } from '../AgentState';
import { NoteDaoInterface } from '../../models/NoteDaoInterface';
import { NoteGenerationCommitResult } from 'common';

export class PersistNodeFactory {
  static create(dao: NoteDaoInterface): CaptureNode {
    return async (input: AgentState): Promise<CaptureNodeResult> => {
      if (!input.persist) {
        return { state: input };
      }
      if (!input.knowledgeUnit) {
        const error: CaptureGraphError = {
          kind: 'PERSIST_NO_UNIT',
          message: 'persist requested but knowledgeUnit is missing',
          step: 'persist',
          retriable: false,
        };
        const next: AgentState = copyAgentState(input);
        next.error = error;
        return { state: next };
      }
      if (input.preparedCandidate?.commitKey !== undefined && input.preparedCandidate.updateExisting === true
        && dao.updateWithCommitKey !== undefined && input.preparedCandidate.expectedVersion !== undefined) {
        const commit: NoteGenerationCommitResult = {
          commitKey: input.preparedCandidate.commitKey,
          runId: input.preparedCandidate.runId,
          checkpointId: input.preparedCandidate.checkpointId,
          noteId: input.knowledgeUnit.id,
          version: input.preparedCandidate.expectedVersion + 1,
          sourceIds: input.preparedCandidate.pendingSourceIds ?? [],
          candidateJson: JSON.stringify(input.knowledgeUnit),
          committedAt: Date.now(),
          generationMetadata: input.preparedCandidate.incrementalManifest === undefined
            ? '' : JSON.stringify(input.preparedCandidate.incrementalManifest),
        };
        const commitResult = await dao.updateWithCommitKey(input.knowledgeUnit, input.preparedCandidate.expectedVersion, commit);
        const next: AgentState = copyAgentState(input);
        if (commitResult.success === false) {
          next.error = {
            kind: commitResult.errorCode ?? 'PERSIST_ERROR',
            message: commitResult.errorMessage ?? 'KnowledgeUnit update failed',
            step: 'persist',
            retriable: false,
          };
          return { state: next };
        }
        next.commitResult = commitResult;
        return { state: next };
      }
      if (input.preparedCandidate?.updateExisting === true) {
        const next: AgentState = copyAgentState(input);
        next.error = {
          kind: 'PERSIST_UPDATE_UNSUPPORTED',
          message: 'incremental update requires the KnowledgeUnit update seam',
          step: 'persist',
          retriable: false,
        };
        return { state: next };
      }
      if (input.preparedCandidate?.commitKey !== undefined && dao.insertWithCommitKey !== undefined) {
        const commit: NoteGenerationCommitResult = {
          commitKey: input.preparedCandidate.commitKey,
          runId: input.preparedCandidate.runId,
          checkpointId: input.preparedCandidate.checkpointId,
          noteId: input.knowledgeUnit.id,
          version: input.knowledgeUnit.version,
          sourceIds: input.preparedCandidate.pendingSourceIds ?? [],
          candidateJson: JSON.stringify(input.knowledgeUnit),
          committedAt: Date.now(),
          generationMetadata: input.preparedCandidate.incrementalManifest === undefined
            ? '' : JSON.stringify(input.preparedCandidate.incrementalManifest),
        };
        const commitResult = await dao.insertWithCommitKey(input.knowledgeUnit, commit);
        const next: AgentState = copyAgentState(input);
        if (commitResult.success === false) {
          next.error = {
            kind: commitResult.errorCode ?? 'PERSIST_ERROR',
            message: commitResult.errorMessage ?? 'KnowledgeUnit insert failed',
            step: 'persist',
            retriable: false,
          };
          return { state: next };
        }
        next.commitResult = commitResult;
        return { state: next };
      } else {
        await dao.insert(input.knowledgeUnit);
      }
      return { state: input };
    };
  }
}
