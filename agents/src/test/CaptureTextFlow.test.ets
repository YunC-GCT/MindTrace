// MindTrace - CaptureGraph capture 节点文本流转证据测试
// 2026-09-06 · OcrNode payload 断链核实 (handoff-2026-09-06 §2 真机未验 TBD 的单测路径证据)
//
// ⚠️ EXPECTED-RED: 本套件当前预期失败 — 它证明的是缺陷本身, payload 断链修复后应转绿。
//    修复前请勿据红误判回归; 修复后此文件即为该缺陷的回归守门。
//
// 断链链路 (现状, 逐行证据):
//   1. Dispatcher.buildGraph START 节点只把 req.payload 折叠成 captureText
//      (agents/core/Dispatcher.ets:104 seedText: kind==='text' 才返回 text, 其余返回 '')
//      → image/file payload 的 imageUri/fileUri/userText 不进入 AgentState。
//   2. AgentState 无 payload 字段 (agents/graph/AgentState.ets:23), OcrNode 无法取回原始 payload。
//   3. OcrNode.ets:9 把字符串 input.captureText "as never" 传给 recognizeText(payload: DispatchPayload)。
//   4. TypeClassifier.extractText (TypeClassifier.ets:136) 三个分支全部判 payload.kind,
//      字符串 .kind 为 undefined → 三分支全跳过 → return ''
//      → capture 节点把 captureText 覆写为 '', 文本内容/图片 URI 在此消失。
//   5. 下游: classify('') 直接落 confidence 0.2 兜底; structure('') 交给 LLM 空输入。
//
// 修复方向 (供后续 bugfix 评估): AgentState 增加 payload 字段, START 种 payload,
//   OcrNode 传 payload (必要时连同 context) 而非 captureText。

import { describe, it, expect } from '@ohos/hypium';
import { CaptureGraph } from '../main/ets/graph/CaptureGraph';
import { AgentState, CaptureNodeResult } from '../main/ets/graph/AgentState';
import { OcrNodeFactory } from '../main/ets/graph/nodes/OcrNode';
import { TypeClassifier } from '../main/ets/agents/TypeClassifier';

async function startSeedNode(input: AgentState): Promise<CaptureNodeResult> {
  const result: CaptureNodeResult = { state: input };
  return result;
}

export default function captureTextFlowTest(): void {
  describe('CaptureGraph.text_flow', () => {
    it('text_payload_text_survives_capture_node', 0, async () => {
      // START 语义按 Dispatcher.seedText 对 text payload 的产物模拟 (真实 START 在 buildGraph 内)。
      // 图只含 START→capture→END, 不触 LLM/OCR 网络, 专测 OcrNode ↔ payload 这一环。
      const graph: CaptureGraph = new CaptureGraph();
      graph.addNode('START', startSeedNode);
      graph.addNode('capture', OcrNodeFactory.create(new TypeClassifier()));
      graph.addEdge('START', 'capture');
      graph.addEdge('capture', 'END');
      const initial: AgentState = {
        captureText: '已知函数 f(x)=x^2 求它在 x=1 处的导数',
        currentStep: 'START',
        persist: false,
      };
      const result: AgentState = await graph.run(initial);
      expect(result.error === undefined).assertTrue();
      expect(result.captureText.length > 0).assertTrue();
      expect(result.captureText).assertContain('f(x)=x^2');
    });
  });
}
