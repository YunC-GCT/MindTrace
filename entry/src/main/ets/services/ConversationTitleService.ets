/**
 * ConversationTitleService.ets - Deterministic first-message title policy.
 *
 * Path: entry/src/main/ets/services/ConversationTitleService.ets
 * Responsibility: Derive a short conversation title without a model request.
 * Dependencies: none.
 */

export const MAX_CONVERSATION_TITLE_LENGTH: number = 10;

export class ConversationTitleService {
  static fromFirstMessage(content: string): string {
    const normalized: string = content.replace(/\s+/g, ' ').trim();
    if (normalized.length === 0) { return '新对话'; }
    if (normalized === '[图片]') { return '图片对话'; }
    return ConversationTitleService.takeCharacters(normalized, MAX_CONVERSATION_TITLE_LENGTH);
  }

  private static takeCharacters(value: string, limit: number): string {
    let index: number = 0;
    let count: number = 0;
    while (index < value.length && count < limit) {
      const code: number = value.charCodeAt(index);
      if (code >= 55296 && code <= 56319 && index + 1 < value.length) {
        const next: number = value.charCodeAt(index + 1);
        if (next >= 56320 && next <= 57343) { index += 1; }
      }
      index += 1;
      count += 1;
    }
    return value.substring(0, index);
  }
}
