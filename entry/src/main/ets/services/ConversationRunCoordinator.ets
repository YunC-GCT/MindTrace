/**
 * ConversationRunCoordinator.ets - Single owner of conversation run admission and terminal state.
 *
 * Path: entry/src/main/ets/services/ConversationRunCoordinator.ets
 * Responsibility: Admit one active run per session and reject stale lifecycle events.
 * Dependencies: ConversationIdentity.
 *
 * Data flow:
 *   Validated session ID -> start/current/finish -> immutable ConversationRunRef.
 *
 * ArkTS 1.1 strict adaptation:
 *   - Lifecycle results use explicit interfaces and string unions.
 */

import {
  ConversationRunIdPolicy,
  ConversationRunRef,
  SessionIdPolicy,
  createConversationRunRef,
  conversationRunIdPolicy,
} from './ConversationIdentity';

export type ConversationRunTerminal = 'completed' | 'failed' | 'cancelled';

export interface ConversationRunStartResult {
  accepted: boolean;
  ref?: ConversationRunRef;
  diagnostic: string;
}

export type ConversationRunRequestKind =
  | 'image'
  | 'text'
  | 'regenerate'
  | 'confirm-draft'
  | 'restore-draft'
  | 'retry-draft'
  | 'cancel-draft';

export interface ConversationRunRequest {
  readonly kind: ConversationRunRequestKind;
}

interface ActiveConversationRun {
  readonly sessionId: string;
  readonly runId: string;
  readonly requestKind: ConversationRunRequestKind;
}

export class ConversationRunCoordinator {
  private readonly active: Map<string, ActiveConversationRun> = new Map<string, ActiveConversationRun>();

  start(sessionId: string, request: ConversationRunRequest): ConversationRunStartResult {
    try {
      SessionIdPolicy.requireValid(sessionId);
    } catch (_error) {
      return { accepted: false, diagnostic: 'code=INVALID_SESSION_ID' };
    }
    if (this.active.has(sessionId)) {
      return { accepted: false, diagnostic: 'code=RUN_BUSY' };
    }
    const ref: ConversationRunRef = createConversationRunRef(sessionId, conversationRunIdPolicy.create());
    this.active.set(sessionId, {
      sessionId: ref.sessionId,
      runId: ref.runId,
      requestKind: request.kind,
    });
    return { accepted: true, ref: ref, diagnostic: 'code=ACCEPTED' };
  }

  isCurrent(ref: ConversationRunRef): boolean {
    if (!SessionIdPolicy.isValid(ref.sessionId) || !ConversationRunIdPolicy.isValid(ref.runId)) {
      return false;
    }
    const current: ActiveConversationRun | undefined = this.active.get(ref.sessionId);
    return current !== undefined && current.runId === ref.runId;
  }

  activeCount(): number {
    return this.active.size;
  }

  currentRef(sessionId: string): ConversationRunRef | undefined {
    if (!SessionIdPolicy.isValid(sessionId)) { return undefined; }
    const current: ActiveConversationRun | undefined = this.active.get(sessionId);
    return current === undefined
      ? undefined
      : createConversationRunRef(current.sessionId, current.runId);
  }

  finish(ref: ConversationRunRef, _terminal: ConversationRunTerminal): boolean {
    const current: ActiveConversationRun | undefined = this.active.get(ref.sessionId);
    if (current === undefined || current.runId !== ref.runId) {
      return false;
    }
    this.active.delete(ref.sessionId);
    return true;
  }
}
