/**
 * ConversationIdentity.ets - Conversation identity generation and validation.
 *
 * Path: entry/src/main/ets/services/ConversationIdentity.ets
 * Responsibility: Own the distinct policies for session, run, and UI message identities.
 * Dependencies: None.
 *
 * Data flow:
 *   Clock/entropy source -> narrow identity policy -> validated identity
 *
 * ArkTS 1.1 strict adaptation:
 *   - Each identity domain has an explicit policy instead of a generic validator.
 */

export type ConversationIdentityKind = 'session' | 'run' | 'message' | 'profile-scope';
export type ConversationIdentityErrorCode =
  | 'INVALID_SESSION_ID'
  | 'INVALID_CONVERSATION_RUN_ID'
  | 'INVALID_CHAT_MESSAGE_ID'
  | 'INVALID_PROFILE_SCOPE_ID';

export interface ConversationRunRef {
  readonly sessionId: string;
  readonly runId: string;
}

export interface ConversationIdentitySource {
  nowMs(): number;
  entropy(): number;
}

export class ConversationIdentityError extends Error {
  readonly code: ConversationIdentityErrorCode;
  readonly kind: ConversationIdentityKind;

  constructor(code: ConversationIdentityErrorCode, kind: ConversationIdentityKind) {
    super(code + ': invalid ' + kind + ' identity');
    this.name = 'ConversationIdentityError';
    this.code = code;
    this.kind = kind;
  }
}

class SystemConversationIdentitySource implements ConversationIdentitySource {
  nowMs(): number {
    return Date.now();
  }

  entropy(): number {
    return Math.floor(Math.random() * 1679616);
  }
}

class MonotonicTextIdentityGenerator {
  private readonly prefix: string;
  private readonly source: ConversationIdentitySource;
  private lastTime: number = -1;
  private sequence: number = 0;

  constructor(prefix: string, source: ConversationIdentitySource) {
    this.prefix = prefix;
    this.source = source;
  }

  create(): string {
    const observed: number = Math.min(Number.MAX_SAFE_INTEGER, Math.max(0, Math.floor(this.source.nowMs())));
    if (observed > this.lastTime) {
      this.lastTime = observed;
      this.sequence = 0;
    } else {
      this.sequence += 1;
    }
    const entropy: number = Math.min(2176782335, Math.max(0, Math.floor(this.source.entropy())));
    const timePart: string = this.lastTime.toString(36).padStart(11, '0');
    const entropyPart: string = entropy.toString(36).padStart(6, '0');
    const sequencePart: string = this.sequence.toString(36).padStart(11, '0');
    return this.prefix
      + timePart
      + entropyPart
      + sequencePart;
  }
}

const SESSION_ID_PATTERN: RegExp = /^[0-9a-z]{2,64}$/;
const RUN_ID_PATTERN: RegExp = /^r[0-9a-z]{2,63}$/;
export const PROFILE_GLOBAL_SCOPE_ID: string = '__global__';

export class SessionIdPolicy {
  private readonly generator: MonotonicTextIdentityGenerator;

  constructor(source: ConversationIdentitySource = new SystemConversationIdentitySource()) {
    this.generator = new MonotonicTextIdentityGenerator('s', source);
  }

  create(): string {
    const id: string = this.generator.create();
    return SessionIdPolicy.requireValid(id);
  }

  static isValid(value: string): boolean {
    return SESSION_ID_PATTERN.test(value);
  }

  static requireValid(value: string): string {
    if (!SessionIdPolicy.isValid(value)) {
      throw new ConversationIdentityError('INVALID_SESSION_ID', 'session');
    }
    return value;
  }
}

export class ConversationRunIdPolicy {
  private readonly generator: MonotonicTextIdentityGenerator;

  constructor(source: ConversationIdentitySource = new SystemConversationIdentitySource()) {
    this.generator = new MonotonicTextIdentityGenerator('r', source);
  }

  create(): string {
    const id: string = this.generator.create();
    return ConversationRunIdPolicy.requireValid(id);
  }

  static isValid(value: string): boolean {
    return RUN_ID_PATTERN.test(value);
  }

  static requireValid(value: string): string {
    if (!ConversationRunIdPolicy.isValid(value)) {
      throw new ConversationIdentityError('INVALID_CONVERSATION_RUN_ID', 'run');
    }
    return value;
  }
}

export class ChatMessageIdPolicy {
  private readonly source: ConversationIdentitySource;
  private lastId: number = 0;

  constructor(source: ConversationIdentitySource = new SystemConversationIdentitySource()) {
    this.source = source;
  }

  create(): number {
    const observed: number = Math.max(1, Math.floor(this.source.nowMs()) * 1000);
    const candidate: number = observed > this.lastId ? observed : this.lastId + 1;
    this.lastId = ChatMessageIdPolicy.requireValid(candidate);
    return this.lastId;
  }

  static isValid(value: number): boolean {
    return Number.isSafeInteger(value) && value > 0;
  }

  static requireValid(value: number): number {
    if (!ChatMessageIdPolicy.isValid(value)) {
      throw new ConversationIdentityError('INVALID_CHAT_MESSAGE_ID', 'message');
    }
    return value;
  }
}

export class ProfileScopePolicy {
  static isValid(value: string): boolean {
    return value === PROFILE_GLOBAL_SCOPE_ID || SessionIdPolicy.isValid(value);
  }

  static requireValid(value: string): string {
    if (!ProfileScopePolicy.isValid(value)) {
      throw new ConversationIdentityError('INVALID_PROFILE_SCOPE_ID', 'profile-scope');
    }
    return value;
  }
}

export function requireConversationRunRef(ref: ConversationRunRef): ConversationRunRef {
  SessionIdPolicy.requireValid(ref.sessionId);
  ConversationRunIdPolicy.requireValid(ref.runId);
  return ref;
}

export function createConversationRunRef(sessionId: string, runId: string): ConversationRunRef {
  const ref: ConversationRunRef = { sessionId: sessionId, runId: runId };
  requireConversationRunRef(ref);
  return ref;
}

export const sessionIdPolicy: SessionIdPolicy = new SessionIdPolicy();
export const conversationRunIdPolicy: ConversationRunIdPolicy = new ConversationRunIdPolicy();
export const chatMessageIdPolicy: ChatMessageIdPolicy = new ChatMessageIdPolicy();
