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
import { CancellationToken } from 'common';

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
  readonly cancellation: CancellationToken;
}

export class ConversationRunCoordinator {
  static readonly MAX_ACTIVE_RUNS: number = 2;
  private readonly active: Map<string, ActiveConversationRun> = new Map<string, ActiveConversationRun>();
  private readonly cancellationHooks: Map<string, (() => void)[]> = new Map<string, (() => void)[]>();

  start(sessionId: string, request: ConversationRunRequest): ConversationRunStartResult {
    try {
      SessionIdPolicy.requireValid(sessionId);
    } catch (_error) {
      return { accepted: false, diagnostic: 'code=INVALID_SESSION_ID' };
    }
    if (this.active.has(sessionId)) {
      return { accepted: false, diagnostic: 'code=RUN_BUSY' };
    }
    if (this.active.size >= ConversationRunCoordinator.MAX_ACTIVE_RUNS) {
      return { accepted: false, diagnostic: 'code=RUN_CAPACITY' };
    }
    const ref: ConversationRunRef = createConversationRunRef(sessionId, conversationRunIdPolicy.create());
    const cancellation: CancellationToken = new CancellationToken();
    this.active.set(sessionId, {
      sessionId: ref.sessionId,
      runId: ref.runId,
      requestKind: request.kind,
      cancellation: cancellation,
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

  activeRefs(): ConversationRunRef[] {
    const refs: ConversationRunRef[] = [];
    for (const current of this.active.values()) {
      refs.push(createConversationRunRef(current.sessionId, current.runId));
    }
    return refs;
  }

  cancellationToken(ref: ConversationRunRef): CancellationToken | undefined {
    const current: ActiveConversationRun | undefined = this.active.get(ref.sessionId);
    return current !== undefined && current.runId === ref.runId ? current.cancellation : undefined;
  }

  registerCancellationHook(ref: ConversationRunRef, hook: () => void): () => void {
    const current: ActiveConversationRun | undefined = this.active.get(ref.sessionId);
    if (current === undefined || current.runId !== ref.runId) {
      return (): void => {};
    }
    const hooks: (() => void)[] = this.cancellationHooks.get(ref.runId) ?? [];
    hooks.push(hook);
    this.cancellationHooks.set(ref.runId, hooks);
    return (): void => {
      const remaining: (() => void)[] | undefined = this.cancellationHooks.get(ref.runId);
      if (remaining === undefined) {
        return;
      }
      this.cancellationHooks.set(ref.runId, remaining.filter((candidate: () => void): boolean => candidate !== hook));
    };
  }

  cancel(ref: ConversationRunRef): boolean {
    const current: ActiveConversationRun | undefined = this.active.get(ref.sessionId);
    if (current === undefined || current.runId !== ref.runId) {
      return false;
    }
    current.cancellation.cancel();
    const hooks: (() => void)[] = this.cancellationHooks.get(ref.runId) ?? [];
    this.cancellationHooks.delete(ref.runId);
    for (const hook of hooks) {
      try {
        hook();
      } catch (_error) {
        // Cancellation remains terminal if a child cleanup hook fails.
      }
    }
    this.active.delete(ref.sessionId);
    return true;
  }

  cancelAll(): void {
    for (const ref of this.activeRefs()) {
      this.cancel(ref);
    }
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
    this.cancellationHooks.delete(ref.runId);
    this.active.delete(ref.sessionId);
    return true;
  }
}
