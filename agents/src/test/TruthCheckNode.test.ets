/**
 * TruthCheckNode.test.ets — TruthCheckNode 候选输入隔离与错误传播行为测试
 *
 * 路径: agents/src/test/TruthCheckNode.test.ets
 * 职责: 验证 TruthCheckNode 的真值检查输入包含 knowledgeUnit.content,
 *   以及失败结果向 state.error 的传播
 * 依赖: @ohos/hypium, common (KnowledgeUnit / TruthCheckResult / DifficultyLevel / ReviewStatus)
 *
 * 数据流:
 *   TruthCheckNodeFactory.create(capturingService) → node(state) → 断言 service.lastInput / state.error
 *
 * 背景: P1-C 修复 — 原条件要求 generationRequest 或 preparedCandidate 存在才拼接
 * unit 内容, 导致正常拍照路径 (只产 knowledgeUnit) 落库内容从未被真值校验;
 * 2026-09-29: 有 knowledgeUnit 时只检查候选 content；原始 captureText 保留给来源核验。
 *
 * ArkTS 1.1 strict 适配:
 *   - CapturingTruthCheckService 用子类覆写 check() 捕获输入, 避免侵入真实服务
 */

import { describe, it, expect } from '@ohos/hypium';
import { TruthCheckNodeFactory } from '../main/ets/graph/nodes/TruthCheckNode';
import { TruthCheckService } from '../main/ets/agents/TruthCheckService';
import { AgentState } from '../main/ets/graph/AgentState';
import { MvpTruthCheckResult, MvpTruthCheckItem } from '../main/ets/models/TruthCheckResult';
import { KnowledgeUnit, DifficultyLevel, ReviewStatus } from 'common';

class CapturingTruthCheckService extends TruthCheckService {
  public lastInput: string = '';
  public resultToReturn: MvpTruthCheckResult = {
    truthFlag: true,
    details: [],
    correctedText: undefined,
  };

  check(input: string): MvpTruthCheckResult {
    this.lastInput = input;
    return this.resultToReturn;
  }
}

function unit(): KnowledgeUnit {
  const u: KnowledgeUnit = {
    id: 'unit-tc',
    title: '测试单元',
    content: '落库内容包含矛盾等式 1=0 用于触发真值检查',
    summary: '',
    tags: [],
    subject: '高等数学',
    category: '定理',
    chapter: '测试',
    difficulty: DifficultyLevel.EASY,
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

function state(u?: KnowledgeUnit): AgentState {
  const s: AgentState = {
    captureText: 'x + 1 = 2',
    source: 'camera_capture',
    currentStep: 'truth_check',
    persist: true,
    analysisOnly: false,
  };
  if (u !== undefined) {
    s.knowledgeUnit = u;
  }
  return s;
}

export default function truthCheckNodeTest(): void {
  describe('TruthCheckNode.input_composition', () => {
    it('unit_content_included_in_check_input_on_capture_path', 0, async () => {
      const service: CapturingTruthCheckService = new CapturingTruthCheckService();
      const node = TruthCheckNodeFactory.create(service);
      const candidate: KnowledgeUnit = unit();
      const result = await node(state(candidate));
      expect(service.lastInput).assertEqual(candidate.content);
      expect(result.state.captureText).assertEqual('x + 1 = 2');
    });

    it('capture_text_only_when_no_knowledge_unit', 0, async () => {
      const service: CapturingTruthCheckService = new CapturingTruthCheckService();
      const node = TruthCheckNodeFactory.create(service);
      await node(state(undefined));
      expect(service.lastInput).assertEqual('x + 1 = 2');
    });

    it('failed_check_sets_truth_check_error', 0, async () => {
      const service: CapturingTruthCheckService = new CapturingTruthCheckService();
      const failingItem: MvpTruthCheckItem = {
        checkName: 'equationCheck',
        passed: false,
        issues: ['contradictory equation: 1=0'],
      };
      service.resultToReturn = {
        truthFlag: false,
        details: [failingItem],
        correctedText: undefined,
      };
      const node = TruthCheckNodeFactory.create(service);
      const result = await node(state(unit()));
      expect(result.state.truthCheck !== undefined).assertTrue();
      expect(result.state.truthCheck?.passed).assertFalse();
      expect(result.state.error !== undefined).assertTrue();
      expect(result.state.error?.kind).assertEqual('TRUTH_CHECK_ERROR');
      expect(result.state.error?.message).assertContain('contradictory equation: 1=0');
      expect(result.state.error?.step).assertEqual('truth_check');
      expect(result.state.error?.retriable).assertFalse();
    });
  });

  // 本地规则不推测积分变量；微元缺失由上下文语义校验判断。
  describe('TruthCheckService.integral_preservation', () => {
    it('correct_integral_with_integrand_before_dx_passes', 0, () => {
      const service: TruthCheckService = new TruthCheckService();
      const result: MvpTruthCheckResult = service.truthCheck('$\\int_{-\\infty}^{\\infty} f(x)\\,dx=1$');
      expect(result.truthFlag).assertTrue();
      expect(result.correctedText).assertUndefined();
    });

    it('change_of_variable_integral_with_du_passes', 0, () => {
      const service: TruthCheckService = new TruthCheckService();
      const result: MvpTruthCheckResult = service.truthCheck('$\\int_{-\\infty}^{\\infty}\\varphi(u)\\,du=1$');
      expect(result.truthFlag).assertTrue();
      expect(result.correctedText).assertUndefined();
    });

    it('missing_differential_does_not_invent_an_integration_variable', 0, () => {
      const service: TruthCheckService = new TruthCheckService();
      const result: MvpTruthCheckResult = service.truthCheck('$\\int_{0}^{1} x^2 = 1/3$');
      expect(result.truthFlag).assertTrue();
      expect(result.correctedText).assertUndefined();
    });
  });
}
