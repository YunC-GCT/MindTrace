import { common } from '@kit.AbilityKit';
import { ConversationProgressStep } from './ConversationState';
import { NoteDraftReadyEvent } from 'common';

export interface ConversationWorkflowCallbacks {
  addAiMsg(content: string): void;
  addAiMsgEmpty(): number;
  appendAiMsg(id: number, delta: string, kind?: 'reasoning' | 'content'): void;
  finishAiMsg(id: number): void;
  onStart(): void;
  onProgress(step: ConversationProgressStep): void;
  onFinish(): void;
  getContext(): common.UIAbilityContext;
  getConversationText(excludeLatestUser: boolean): string;
  getSessionId(): string;
  onDraftReady(event: NoteDraftReadyEvent): void;
}
