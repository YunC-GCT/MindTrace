/**
 * List.test.ets — common 模块本地单元测试入口
 *
 * 汇总注册 common 模块全部 Hypium 测试套件 (LLM 基础设施 / 协议 / 工作流内核 / 模型解析)。
 */

import llmGuardTest from './LlmGuard.test';
import latexRiskNormalizerTest from './LatexRiskNormalizer.test';
import contentProtocolTest from './ContentProtocol.test';
import contentExcerptBuilderTest from './ContentExcerptBuilder.test';
import noteToolsTest from './NoteTools.test';
import llmToolCallingTest from './LlmToolCalling.test';
import stateGraphTest from './StateGraph.test';
import llmStreamEventsTest from './LlmStreamEvents.test';
import noteGenerationModelsTest from './NoteGenerationModels.test';
import llmErrorBodyFormatterTest from './LlmErrorBodyFormatter.test';

export default function testsuite(): void {
  llmGuardTest();
  latexRiskNormalizerTest();
  contentProtocolTest();
  contentExcerptBuilderTest();
  noteToolsTest();
  llmToolCallingTest();
  stateGraphTest();
  llmStreamEventsTest();
  noteGenerationModelsTest();
  llmErrorBodyFormatterTest();
}
