/**
 * List.test.ets — agents 模块本地单元测试入口
 *
 * 每个参与单元测试的模块都需要一个 src/test/ 目录。
 * 本文件导入 KnowledgeModel 的测试套件。
 */

import truthCheckServiceTest from './TruthCheckService.test';
import promptBuilderTest from './PromptBuilder.test';
import captureGraphTest from './CaptureGraph.test';
import captureTextFlowTest from './CaptureTextFlow.test';

export default function testsuite() {
  truthCheckServiceTest();
  promptBuilderTest();
  captureGraphTest();
  captureTextFlowTest();
}
