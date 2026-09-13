import { TextIntent } from '../../services/IntentClassifier';

export type ConversationStep =
  | 'START'
  | 'classify_intent'
  | 'load_reply_context'
  | 'save_reply_input'
  | 'image_reply'
  | 'complete_reply'
  | 'stream_reply'
  | 'note_reply'
  | 'regenerate_reply'
  | 'END';

export type ConversationProgressStep =
  | 'intent_check'
  | 'reply_context_load'
  | 'reply_model_call'
  | 'image_message_save'
  | 'image_recognize'
  | 'image_material_save'
  | 'note_intent_check'
  | 'note_context_load'
  | 'note_source_prepare'
  | 'note_structure_save'
  | 'note_finalize'
  | 'completed';

export interface ImageConversationRequest {
  kind: 'image';
  imageUri: string;
  userContent: string;
}

export interface TextConversationRequest {
  kind: 'text';
  userContent: string;
  responseMode: 'complete' | 'stream';
}

export interface RegenerateConversationRequest {
  kind: 'regenerate';
  noteId: string;
  userContent: string;
}

export type ConversationRequest = ImageConversationRequest | TextConversationRequest | RegenerateConversationRequest;

export interface ConversationState {
  request: ConversationRequest;
  sessionId: string;
  currentStep: ConversationStep;
  intent?: TextIntent;
  memoryContext?: string;
  learnerProfileContext?: string;
  draftRunId?: string;
  draftCheckpointId?: string;
  draftCandidateHash?: string;
  draftStatus?: 'ready-preview' | 'user-edit' | 'confirmed' | 'cancelled';
}
