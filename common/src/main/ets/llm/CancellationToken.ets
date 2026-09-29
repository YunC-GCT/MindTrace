/**
 * CancellationToken.ets - Cooperative cancellation for conversation work.
 *
 * Path: common/src/main/ets/llm/CancellationToken.ets
 * Responsibility: Own one-shot cancellation state and cleanup listeners shared by workflows and transports.
 * Dependencies: none.
 *
 * Data flow:
 *   ConversationRunCoordinator -> CancellationToken -> workflow/HTTP cleanup listeners.
 *
 * ArkTS 1.1 strict adaptation:
 *   - Listener and state types are explicit; cancellation is idempotent.
 */
export type CancellationListener = () => void;

export class CancellationToken {
  private cancelled: boolean = false;
  private listeners: CancellationListener[] = [];

  isCancelled(): boolean {
    return this.cancelled;
  }

  cancel(): boolean {
    if (this.cancelled) {
      return false;
    }
    this.cancelled = true;
    const listeners: CancellationListener[] = this.listeners.slice(0);
    this.listeners = [];
    for (const listener of listeners) {
      try {
        listener();
      } catch (_error) {
        // Cleanup listeners are isolated from one another.
      }
    }
    return true;
  }

  throwIfCancelled(): void {
    if (this.cancelled) {
      throw new Error('CONVERSATION_CANCELLED');
    }
  }

  onCancel(listener: CancellationListener): () => void {
    if (this.cancelled) {
      listener();
      return (): void => {};
    }
    this.listeners.push(listener);
    let removed: boolean = false;
    return (): void => {
      if (removed) {
        return;
      }
      removed = true;
      this.listeners = this.listeners.filter((candidate: CancellationListener): boolean => candidate !== listener);
    };
  }
}
