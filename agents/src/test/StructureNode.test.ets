/**
 * StructureNode.test.ets — StructureNode retriable 映射行为测试
 *
 * 路径: agents/src/test/StructureNode.test.ets
 * 职责: 验证 structure 步骤异常 → CaptureGraphError.retriable 的类型映射
 *   (成功路径 / GenerationJsonError.retriable 透传 / LlmError 网络类可重试 /
 *    LlmError 配置类与普通 Error 不可重试)
 * 依赖: @ohos/hypium, common (KnowledgeUnit / LlmError / ClassificationResult 类型)
 *
 * 数据流:
 *   StructureNodeFactory.create(stubModel) → node(state) → 断言 state.error.retriable
 *
 * 背景: §13.5 轻量修复 (2026-09-19) — 原实现把一切异常拍平为 retriable: false,
 * 网络抖动等可重试失败被误标为终态; 现按 GenerationJsonError.retriable 与
 * LlmError kind (NETWORK_ERROR / TIMEOUT / STREAM_FAILED) 映射。
 *
 * ArkTS 1.1 strict 适配:
 *   - StubStructureModel extends KnowledgeModel 覆写 structure(), 沿用 entry 测试的 Fake 模式
 */

import { describe, it, expect } from '@ohos/hypium';
import { StructureNodeFactory } from '../main/ets/graph/nodes/StructureNode';
import { KnowledgeModel } from '../main/ets/agents/KnowledgeModel';
import { GenerationJsonError } from '../main/ets/agents/GenerationJsonCaller';
import { AgentState } from '../main/ets/graph/AgentState';
import { KnowledgeUnit, LlmError, DifficultyLevel, ReviewStatus } from 'common';

function unit(): KnowledgeUnit {
  const u: KnowledgeUnit = {
    id: 'unit-s1',
    title: '罗尔定理',
    content: '若 f 在 [a,b] 连续, (a,b) 可导且 f(a)=f(b), 则存在 ξ 使 f\'(ξ)=0',
    summary: '闭区间连续 + 开区间可导 + 端点等值',
    tags: ['微分学'],
    subject: '高等数学',
    category: '定理',
    chapter: '微分中值定理',
    difficulty: DifficultyLevel.MEDIUM,
    source: 'camera_capture',
    createdAt: 1700000000000,
    updatedAt: 1700000000000,
    reviewStatus: ReviewStatus.NEW,
    nextReviewAt: 1700000000000,
    intervalDays: 0,
    easeFactor: 2.5,
    repetitions: 0,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: 'user-1',
    version: 1,
  };
  return u;
}

class StubStructureModel extends KnowledgeModel {
  public unit: KnowledgeUnit = unit();
  public errorToThrow: Error | undefined = undefined;
  public calls: number = 0;

  async structure(
    ocrText: string,
    type?: string,
    subject?: string,
    chapter: string = '',
    source: string = 'camera_capture',
  ): Promise<KnowledgeUnit> {
    this.calls += 1;
    if (this.errorToThrow !== undefined) {
      throw this.errorToThrow;
    }
    return this.unit;
  }
}

function state(): AgentState {
  const s: AgentState = {
    captureText: '罗尔定理: 若 f 在 [a,b] 连续...',
    source: 'camera_capture',
    currentStep: 'structure',
    persist: true,
    analysisOnly: false,
  };
  return s;
}

export default function structureNodeTest(): void {
  describe('StructureNode.retriable_mapping', () => {
    it('structure_success_sets_unit_without_error', 0, async () => {
      const model: StubStructureModel = new StubStructureModel();
      const node = StructureNodeFactory.create(model);
      const result = await node(state());
      expect(result.state.error === undefined).assertTrue();
      expect(result.state.knowledgeUnit !== undefined).assertTrue();
      expect(result.state.knowledgeUnit?.id).assertEqual('unit-s1');
      expect(model.calls).assertEqual(1);
    });

    it('generation_json_error_retriable_true_propagates', 0, async () => {
      const model: StubStructureModel = new StubStructureModel();
      model.errorToThrow = new GenerationJsonError(
        'LLM_TRANSPORT', 'light draft transport failed: [NETWORK_ERROR] refused', true,
      );
      const node = StructureNodeFactory.create(model);
      const result = await node(state());
      expect(result.state.error !== undefined).assertTrue();
      expect(result.state.error?.kind).assertEqual('STRUCTURE_ERROR');
      expect(result.state.error?.retriable).assertTrue();
    });

    it('generation_json_error_terminal_maps_false', 0, async () => {
      const model: StubStructureModel = new StubStructureModel();
      model.errorToThrow = new GenerationJsonError(
        'JSON_SCHEMA_ERROR', 'light draft failed after 3 attempts: title missing', false,
      );
      const node = StructureNodeFactory.create(model);
      const result = await node(state());
      expect(result.state.error !== undefined).assertTrue();
      expect(result.state.error?.kind).assertEqual('STRUCTURE_ERROR');
      expect(result.state.error?.retriable).assertFalse();
      expect(result.state.error?.message).assertContain('after 3 attempts');
    });

    it('llm_error_network_timeout_stream_map_retriable_true', 0, async () => {
      const retriableKinds: string[] = ['NETWORK_ERROR', 'TIMEOUT', 'STREAM_FAILED'];
      for (const kind of retriableKinds) {
        const model: StubStructureModel = new StubStructureModel();
        model.errorToThrow = new LlmError('transport issue', kind);
        const node = StructureNodeFactory.create(model);
        const result = await node(state());
        expect(result.state.error !== undefined).assertTrue();
        expect(result.state.error?.kind).assertEqual('STRUCTURE_ERROR');
        expect(result.state.error?.retriable).assertTrue();
      }
    });

    it('llm_error_api_and_generic_error_map_false', 0, async () => {
      const apiModel: StubStructureModel = new StubStructureModel();
      apiModel.errorToThrow = new LlmError('http 500', 'API_ERROR');
      const apiNode = StructureNodeFactory.create(apiModel);
      const apiResult = await apiNode(state());
      expect(apiResult.state.error?.retriable).assertFalse();

      const genericModel: StubStructureModel = new StubStructureModel();
      genericModel.errorToThrow = new Error('unexpected boom');
      const genericNode = StructureNodeFactory.create(genericModel);
      const genericResult = await genericNode(state());
      expect(genericResult.state.error !== undefined).assertTrue();
      expect(genericResult.state.error?.kind).assertEqual('STRUCTURE_ERROR');
      expect(genericResult.state.error?.retriable).assertFalse();
      expect(genericResult.state.error?.message).assertEqual('unexpected boom');
    });
  });
}
