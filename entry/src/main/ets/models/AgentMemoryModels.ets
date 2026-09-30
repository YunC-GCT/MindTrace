import { NoteTopicCandidate, SourceBundle } from 'common';

export type ChatRole = 'system' | 'user' | 'assistant';

export interface ChatMessageWriteRequest {
  sessionId: string;
  role: ChatRole;
  content: string;
  messageKey: string;
  sequence: number;
  runId?: string;
  origin: string;
  outcome?: string;
}

export type AgentMemoryType = 'pending_note' | 'summary' | 'ocr_result' | 'profile';

export type LearnerLevel = 'beginner' | 'novice' | 'advanced';

export interface ChatMessageRecord {
  id: string;
  messageKey: string;
  sessionId: string;
  role: ChatRole;
  content: string;
  runId?: string;
  sequence: number;
  origin: string;
  outcome: string;
  createdAt: number;
}

export interface AgentMemoryRecord {
  id: string;
  sessionId: string;
  type: AgentMemoryType;
  content: string;
  source: string;
  used: number;
  createdAt: number;
  updatedAt: number;
}

export interface LearnerProfile {
  globalLevel: LearnerLevel;
  sessionLevel: LearnerLevel;
  effectiveLevel: LearnerLevel;
  confidence: number;
  evidence: string;
  updatedAt: number;
}

export interface AgentMemoryContext {
  summary: string;
  pendingNotes: AgentMemoryRecord[];
  recentMessages: ChatMessageRecord[];
  text: string;
}

export type NoteGenerationContextCandidateKind = 'conversation' | 'ocr' | 'summary';

export interface NoteGenerationContextCandidate {
  id: string;
  kind: NoteGenerationContextCandidateKind;
  originId: string;
  provenanceIds?: string[];
  sequence: number;
  role?: ChatRole;
  outcome?: string;
  text: string;
  createdAt: number;
  priority: number;
}

export interface NoteGenerationContextBuildInput {
  summary?: AgentMemoryRecord;
  pendingNotes: AgentMemoryRecord[];
  recentMessages: ChatMessageRecord[];
  instruction: string;
  inlineMaterial: string;
  currentConversationText: string;
  currentRunId: string;
  contextWindowTokens: number;
}

export interface NoteGenerationContextResult {
  bundle: SourceBundle;
  contextText: string;
  topics: NoteTopicCandidate[];
  requiresClarification: boolean;
  pendingSourceIds: string[];
  contextBudgetTokens: number;
  estimatedTokens: number;
  budgetDeferred: boolean;
}
