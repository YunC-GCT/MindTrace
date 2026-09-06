/**
 * KnowledgeModel.test.ets — pure logic tests for KnowledgeModel.
 * structure() is not covered here because it needs LLM configuration.
 * spec 015 PR1: 真值检查方法已实体化到 TruthCheckService,
 * 对应测试迁至 TruthCheckService.test.ets; 此处保留 buildPrompt 与
 * truthCheck 转发路径的行为守卫。
 */

import { describe, it, expect } from '@ohos/hypium';
import { KnowledgeModel } from '../main/ets/agents/KnowledgeModel';
import { MvpTruthCheckResult } from '../main/ets/models/TruthCheckResult';

function createModel(): KnowledgeModel {
  return new KnowledgeModel();
}

export default function knowledgeModelTest(): void {
  describe('KnowledgeModel.pure_logic_test', () => {
    it('buildPrompt_contains_all_categories', 0, () => {
      const km: KnowledgeModel = createModel();
      const prompt: string = km.buildPrompt('test');
      expect(prompt).assertContain('category');
      expect(prompt).assertContain('definition');
      expect(prompt).assertContain('statement');
      expect(prompt).assertContain('expression');
      expect(prompt).assertContain('proposition');
      expect(prompt).assertContain('problem');
    });

    it('buildPrompt_contains_json_requirements', 0, () => {
      const km: KnowledgeModel = createModel();
      const prompt: string = km.buildPrompt('test');
      expect(prompt).assertContain('difficulty');
      expect(prompt).assertContain('importance');
      expect(prompt).assertContain('JSON');
    });

    it('truthCheck_empty_text_fails', 0, () => {
      const km: KnowledgeModel = createModel();
      const r: MvpTruthCheckResult = km.truthCheck('');
      expect(r.truthFlag).assertFalse();
    });

    it('truthCheck_returns_four_details', 0, () => {
      const km: KnowledgeModel = createModel();
      const r: MvpTruthCheckResult = km.truthCheck('a+b=c');
      expect(r.details.length).assertEqual(4);
    });
  });
}