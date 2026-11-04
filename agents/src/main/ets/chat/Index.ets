// agents/chat/Index.ets — chat 子模块：意图分类、回复、模型路由与排版规则
// 路径: agents/src/main/ets/chat/Index.ets
// 职责: 该子模块的对外出口；entry 与其它子模块按此路径导入，避免拉入整个 agents barrel。

export {
  IntentClassifier,
} from './IntentClassifier';
export type {
  ReplyContext, ReplyKind, TextIntent,
} from './IntentClassifier';
export {
  ModelRouter,
} from './ModelRouter';
export type {
  RoutedReply,
} from './ModelRouter';
export {
  CHAT_REPLY_POLICY, ReplyService, configureDebugFaultSource,
} from './ReplyService';
export type {
  LlmCallPolicy, ReplyEventSink, StreamReplyResult,
} from './ReplyService';
export {
  AppIntentRouter,
} from './AppIntentRouter';
export {
  INTENT_KINDS, INTENT_LABELS, buildAppIntentPrompt, classifyAppIntentLocal, isKnownAppIntent, parseAppIntentJson, validateAppIntentJson,
} from './AppIntentRules';
export type {
  AppIntentDecision, AppIntentKind,
} from './AppIntentRules';
export {
  ModelSelector,
} from './ModelSelector';
export type {
  ModelAvailability,
} from './ModelSelector';
export {
  buildMathStyleRules,
} from './ReplyStyleRules';
export type {
  ReplyStyle,
} from './ReplyStyleRules';
export {
  streamErrorText,
} from './StreamErrorText';
