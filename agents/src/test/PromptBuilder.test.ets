/**
 * PromptBuilder.test.ets — spec 015 PR2: 提示词构造实体化后的服务级测试。
 */

import { describe, it, expect } from '@ohos/hypium';
import { PromptBuilder } from '../main/ets/agents/PromptBuilder';

function createBuilder(): PromptBuilder {
  return new PromptBuilder();
}

export default function promptBuilderTest(): void {
  describe('PromptBuilder.prompt_test', () => {
    it('buildPrompt_contains_all_categories', 0, () => {
      const pb: PromptBuilder = createBuilder();
      const prompt: string = pb.buildPrompt('test');
      expect(prompt).assertContain('category');
      expect(prompt).assertContain('概念');
      expect(prompt).assertContain('定理');
      expect(prompt).assertContain('公式');
      expect(prompt).assertContain('证明题');
      expect(prompt).assertContain('计算题');
      expect(prompt).assertContain('定义');
      expect(prompt).assertContain('陈述');
      expect(prompt).assertContain('表达式');
      expect(prompt).assertContain('命题');
      expect(prompt).assertContain('常见错误');
    });

    it('buildPrompt_contains_json_requirements', 0, () => {
      const pb: PromptBuilder = createBuilder();
      const prompt: string = pb.buildPrompt('test');
      expect(prompt).assertContain('difficulty');
      expect(prompt).assertContain('importance');
      expect(prompt).assertContain('JSON');
    });
  });
}
