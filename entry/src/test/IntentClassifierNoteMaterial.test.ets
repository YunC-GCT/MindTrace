/**
 * IntentClassifierNoteMaterial.test.ets — inline note material extraction regressions
 *
 * 路径: entry/src/test/IntentClassifierNoteMaterial.test.ets
 * 职责: 锁定只有明确分隔符后的文本才会被当作当前笔记素材
 * 依赖: @ohos/hypium; IntentClassifier
 *
 * 数据流:
 *   user instruction → IntentClassifier.inlineNoteMaterial → material assertions
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式返回类型和具名测试断言
 */
import { describe, it, expect } from '@ohos/hypium';
import { IntentClassifier } from '../main/ets/services/IntentClassifier';

export default function intentClassifierNoteMaterialTest(): void {
  describe('IntentClassifier.inlineNoteMaterial', () => {
    it('does_not_treat_plain_save_instruction_as_material', 0, () => {
      const classifier: IntentClassifier = new IntentClassifier();
      expect(classifier.inlineNoteMaterial('保存这条笔记')).assertEqual('');
    });

    it('extracts_material_after_explicit_separator', 0, () => {
      const classifier: IntentClassifier = new IntentClassifier();
      const material: string = classifier.inlineNoteMaterial('整理成笔记：函数连续性描述函数值的变化趋势。');
      expect(material).assertEqual('函数连续性描述函数值的变化趋势。');
    });
  });
}
