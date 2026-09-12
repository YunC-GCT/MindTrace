import localUnitTest from './LocalUnit.test';
import markdownRendererProtocolTest from './MarkdownRendererProtocol.test';
import knowledgeUnitWriteServiceTest from './KnowledgeUnitWriteService.test';
import incrementalRegenerationTest from './IncrementalRegeneration.test';
import agentChatStreamEventsTest from './AgentChatStreamEvents.test';

export default function testsuite() {
  localUnitTest();
  markdownRendererProtocolTest();
  knowledgeUnitWriteServiceTest();
  incrementalRegenerationTest();
  agentChatStreamEventsTest();
}
