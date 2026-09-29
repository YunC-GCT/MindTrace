/**
 * ConversationTitleService.test.ets - First-message title policy tests.
 *
 * Path: entry/src/test/ConversationTitleService.test.ets
 * Responsibility: Verify normalized, bounded, and stable title derivation.
 */
import { describe, expect, it } from '@ohos/hypium';
import {
  ConversationTitleService,
  MAX_CONVERSATION_TITLE_LENGTH,
} from '../main/ets/services/ConversationTitleService';

export default function conversationTitleServiceTest(): void {
  describe('ConversationTitleService.first_message_title', () => {
    it('should normalize whitespace and cap a text title at ten characters', 0, () => {
      const title: string = ConversationTitleService.fromFirstMessage('  极限   与   连续性问题：求导  ');
      expect(title).assertEqual('极限 与 连续性问题');
      expect(title.length <= MAX_CONVERSATION_TITLE_LENGTH).assertTrue();
    });

    it('should provide a useful title for an image-only first message', 0, () => {
      expect(ConversationTitleService.fromFirstMessage('[图片]')).assertEqual('图片对话');
    });

    it('should not split a surrogate pair while truncating', 0, () => {
      const title: string = ConversationTitleService.fromFirstMessage('😀😀😀😀😀😀😀😀😀😀😀');
      expect(title).assertEqual('😀😀😀😀😀😀😀😀😀😀');
    });
  });
}
