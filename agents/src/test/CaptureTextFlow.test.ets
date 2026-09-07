// MindTrace - CaptureGraph capture 节点文本流转回归测试
// 2026-09-06 · OcrNode payload→state 管线修复的回归守门 (原红色证据测试, 修复后转绿)
//
// 历史背景: 修复前 OcrNode.ets:9 把字符串 captureText "as never" 传给
// recognizeText(DispatchPayload), extractText 按 payload.kind 分支对字符串
// 全部落空返回 '', capture 节点把 captureText 覆写为空; image/file 的 URI 因
// AgentState 无 payload 字段而从未进图 (handoff-2026-09-06 §2 真机未验的根因)。
//
// 修复后契约 (本文件锁定):
//   1. Dispatcher START 节点把 req.payload 种入 AgentState.payload
//   2. OcrNode 读 input.payload 触达 recognizeText — text 全文过 capture 不丢失
//   3. payload 缺失 = 编程错误 → CaptureGraphError(CAPTURE_NO_PAYLOAD), 不兜底
//
// Hypium 仅 DevEco GUI 可跑; 本套件应全绿。

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
      // 图只含 START→capture→END, 不触 LLM/OCR 网络, 专测 OcrNode ↔ payload 这一环。
      const graph: CaptureGraph = new CaptureGraph();
      graph.addNode('START', startSeedNode);
      graph.addNode('capture', OcrNodeFactory.create(new TypeClassifier()));
      graph.addEdge('START', 'capture');
      graph.addEdge('capture', 'END');
      const initial: AgentState = {
        captureText: '已知函数 f(x)=x^2 求它在 x=1 处的导数',
        payload: {
          kind: 'text',
          text: '已知函数 f(x)=x^2 求它在 x=1 处的导数',
        },
        currentStep: 'START',
        persist: false,
      };
      const result: AgentState = await graph.run(initial);
      expect(result.error === undefined).assertTrue();
      expect(result.captureText.length > 0).assertTrue();
      expect(result.captureText).assertContain('f(x)=x^2');
    });

    it('missing_payload_fails_fast_with_capture_no_payload', 0, async () => {
      // payload 缺失 = 编程错误 → 结构化报错, 不兜底不吞错 (spec 011 §9)
      const graph: CaptureGraph = new CaptureGraph();
      graph.addNode('START', startSeedNode);
      graph.addNode('capture', OcrNodeFactory.create(new TypeClassifier()));
      graph.addEdge('START', 'capture');
      graph.addEdge('capture', 'END');
      const initial: AgentState = {
        captureText: '',
        currentStep: 'START',
        persist: false,
      };
      const result: AgentState = await graph.run(initial);
      expect(result.error !== undefined).assertTrue();
      expect(result.error?.kind).assertEqual('CAPTURE_NO_PAYLOAD');
      expect(result.error?.step).assertEqual('capture');
    });
  });
}
