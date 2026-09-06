/**
 * List.test.ets — common 模块本地单元测试入口
 *
 * common 模块暂无可单独运行的单元测试（纯共享类型/工具/LLM 基础设施）。
 * 此空文件确保测试构建系统不会因缺少测试入口而报错。
 */

import llmGuardTest from './LlmGuard.test';
import latexRiskNormalizerTest from './LatexRiskNormalizer.test';
import contentProtocolTest from './ContentProtocol.test';
import contentExcerptBuilderTest from './ContentExcerptBuilder.test';
import noteToolsTest from './NoteTools.test';
import llmToolCallingTest from './LlmToolCalling.test';

export default function testsuite(): void {
  llmGuardTest();
  latexRiskNormalizerTest();
  contentProtocolTest();
  contentExcerptBuilderTest();
  noteToolsTest();
  llmToolCallingTest();
}
