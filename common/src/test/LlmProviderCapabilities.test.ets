/**
 * LlmProviderCapabilities.test.ets — LLM provider 能力配置回归测试
 *
 * 路径: common/src/test/LlmProviderCapabilities.test.ets
 * 职责: 锁定 DeepSeek 当前不声明 strict schema response format 可用
 * 依赖: @ohos/hypium; common providers / LlmConfig
 */
import { describe, it, expect } from '@ohos/hypium';
import { DEFAULT_VENDOR_ID, findProvider, LlmConfig } from '../main/ets/Index';
import type { ProviderConfig } from '../main/ets/Index';

export default function llmProviderCapabilitiesTest(): void {
  describe('LlmProviderCapabilities', () => {
    it('deepseek_provider_disables_strict_schema_response_format', 0, () => {
      const provider: ProviderConfig | null = findProvider('deepseek');
      expect(provider !== null).assertTrue();
      if (provider === null) {
        return;
      }
      expect(provider.strictStructuredOutput).assertFalse();
    });

    it('default_deepseek_config_does_not_support_strict_structured_output', 0, () => {
      expect(DEFAULT_VENDOR_ID).assertEqual('deepseek');
      const config: LlmConfig = LlmConfig.getInstance();
      expect(config.getVendorId()).assertEqual('deepseek');
      expect(config.supportsStrictStructuredOutput()).assertFalse();
    });
  });
}
