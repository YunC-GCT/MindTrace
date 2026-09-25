import localUnitTest from './LocalUnit.test';
import markdownRendererProtocolTest from './MarkdownRendererProtocol.test';
import knowledgeUnitWriteServiceTest from './KnowledgeUnitWriteService.test';
import incrementalRegenerationTest from './IncrementalRegeneration.test';
import agentChatStreamEventsTest from './AgentChatStreamEvents.test';
import arkWebWarmupServiceTest from './ArkWebWarmupService.test';
import stableChatKeyRefreshTest from './StableChatKeyRefresh.test';
import chatFilesDirSeamTest from './ChatFilesDirSeam.test';
import chatPersistenceCapabilityTest from './ChatPersistenceCapability.test';
import chatHistoryPersistenceTest from './ChatHistoryPersistence.test';
import customSpanPlaceholderSeamTest from './CustomSpanPlaceholderSeam.test';
import dispatcherNoteGenerationTest from './DispatcherNoteGeneration.test';
import rendererSchedulerTest from './RendererScheduler.test';
import renderTickTest from './RenderTick.test';
import streamingReplyDocumentTest from './StreamingReplyDocument.test';
import intentClassifierNoteMaterialTest from './IntentClassifierNoteMaterial.test';
import replyServiceFormatTest from './ReplyServiceFormat.test';

export default function testsuite() {
  localUnitTest();
  markdownRendererProtocolTest();
  knowledgeUnitWriteServiceTest();
  incrementalRegenerationTest();
  agentChatStreamEventsTest();
  arkWebWarmupServiceTest();
  stableChatKeyRefreshTest();
  chatFilesDirSeamTest();
  chatPersistenceCapabilityTest();
  chatHistoryPersistenceTest();
  customSpanPlaceholderSeamTest();
  dispatcherNoteGenerationTest();
  rendererSchedulerTest();
  renderTickTest();
  streamingReplyDocumentTest();
  intentClassifierNoteMaterialTest();
  replyServiceFormatTest();
}
