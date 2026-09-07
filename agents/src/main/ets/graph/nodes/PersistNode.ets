// MindTrace - PersistNode
// 2026-09-05 · D2 Ticket #5
import { AgentState, CaptureNode, CaptureGraphError, CaptureNodeResult } from '../AgentState';
import { NoteDaoInterface } from '../../models/NoteDaoInterface';
import { createUnitExt } from '../../models/KnowledgeUnitExt';

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
        const next: AgentState = {
          captureText: input.captureText,
          currentStep: input.currentStep,
          persist: input.persist,
          error: error,
        };
        return { state: next };
      }
      const unit = input.knowledgeUnit;
      const ext = createUnitExt('概念', unit.subject, unit.title, unit.content);
      ext.tags = unit.tags;
      ext.chapter = unit.chapter;
      ext.difficulty = 3;
      ext.importance = 3;
      ext.source = unit.source;
      ext.needsUserInput = [];
      await dao.insert(ext);
      return { state: input };
    };
  }
}
