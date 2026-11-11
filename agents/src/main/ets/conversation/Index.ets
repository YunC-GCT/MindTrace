// agents/conversation/Index.ets — conversation 子模块：对话图、节点处理器、端口与状态契约
// 路径: agents/src/main/ets/conversation/Index.ets
// 职责: 该子模块的对外出口；entry 与其它子模块按此路径导入，避免拉入整个 agents barrel。

export type {
  ChatMessageOrigin, ChatMessageOutcome, ConversationProgressStep, ConversationRequest, ConversationState, ConversationStep, ImageConversationRequest, RegenerateConversationRequest, TextConversationRequest,
} from './ConversationState';
export {
  CHAT_TOOL_REPLY_ENABLED, ConversationToolReplyFlags,
} from './ConversationToolReplyFlags';
export {
  ConversationWorkflow,
} from './ConversationWorkflow';
export {
  ConversationWorkflowPorts, ConversationWorkflowPortsFactory,
} from './ConversationWorkflowPorts';
export type {
  ConversationWorkflowPortsInput, IConversationCapturePort, IConversationIntentPort, IConversationNoteRoutePort, IConversationReplyPort, IConversationToolPort,
} from './ConversationWorkflowPorts';
export type {
  IConversationDraftServicePort, IConversationMemoryServicePort,
} from './ConversationServicePorts';
export {
  ConversationDraftWorkflow,
} from './ConversationDraftWorkflow';
export {
  ConversationMemoryProjection,
} from './ConversationMemoryProjection';
export type {
  ConversationErrorMessageEvent, ConversationMessageEvent, ConversationReplaceContentEvent, ConversationRunEventStatus, ConversationStatusMessageEvent, ConversationStreamMessageEvent, ConversationWorkflowCallbacks,
} from './ConversationTypes';
