import { describe, it, expect } from '@ohos/hypium';
import { ContentProtocol, LlmGuard } from '../main/ets/Index';
import type { ContentValidationResult, LlmCallRequest, LlmCallResult, LlmCaller, LlmGuardValidationResult, ChatMessage } from '../main/ets/Index';

class FakeCaller implements LlmCaller {
  public calls: ChatMessage[][] = [];
  private replies: string[];
  private index: number = 0;

  constructor(replies: string[]) {
    this.replies = replies;
  }

  async call(request: LlmCallRequest): Promise<LlmCallResult> {
    this.calls.push(request.messages.slice(0));
    const reply: string = this.replies[this.index] ?? this.replies[this.replies.length - 1];
    this.index += 1;
    const result: LlmCallResult = { text: reply, streamed: false };
    return result;
  }
}

export default function llmGuardTest(): void {
  describe('LlmGuard.pure_logic_test', () => {
    it('retries_after_validation_failure', 0, async () => {
      const fake: FakeCaller = new FakeCaller([
        '{"intent":"wrong"}',
        '{"intent":"chat"}',
      ]);
      const guard: LlmGuard = new LlmGuard(fake);
      const result = await guard.callJsonWithRetry(
        [{ role: 'system', content: 'test' }, { role: 'user', content: 'hello' }],
        { label: 'intent' },
        (json: Record<string, Object>): LlmGuardValidationResult => {
          const intent: Object | undefined = json['intent'];
          if (typeof intent === 'string' && (intent === 'chat' || intent === 'note_generation')) {
            return { ok: true, issues: [] };
          }
          return { ok: false, issues: ['intent must be chat or note_generation'] };
        },
      );
      expect(result.attempts).assertEqual(2);
      expect(fake.calls.length).assertEqual(2);
      expect(fake.calls[1].length > fake.calls[0].length).assertTrue();
      expect(result.json['intent']).assertEqual('chat');
    });

    it('validateJsonText_reports_missing_object', 0, () => {
      const guard: LlmGuard = new LlmGuard();
      const result = guard.validateJsonText(
        'plain text',
        (_json: Record<string, Object>): LlmGuardValidationResult => ({ ok: true, issues: [] }),
      );
      expect(result.issues.length > 0).assertTrue();
    });

    it('retries_chat_answer_after_mm_md_validation_failure', 0, async () => {
      const fake: FakeCaller = new FakeCaller([
        '{"answer":"2. $$\\n3. \\\\frac{x}{y}\\n4. $$"}',
        '{"answer":"$$\\n\\\\frac{x}{y}\\n$$"}',
      ]);
      const protocol: ContentProtocol = new ContentProtocol();
      const guard: LlmGuard = new LlmGuard(fake);
      const result = await guard.callJsonWithRetry(
        [{ role: 'system', content: 'Return JSON {"answer":"..."}' }, { role: 'user', content: 'test' }],
        { label: 'chat answer' },
        (json: Record<string, Object>): LlmGuardValidationResult => {
          const answer: Object | undefined = json['answer'];
          if (typeof answer !== 'string') {
            return { ok: false, issues: ['answer must be string'] };
          }
          const validation: ContentValidationResult = protocol.validateNoteMarkdown(answer);
          return {
            ok: validation.ok,
            issues: validation.ok ? [] : ['answer violates MM-MD-v1: ' + validation.issues.join(', ')],
          };
        },
      );
      expect(result.attempts).assertEqual(2);
      expect(fake.calls.length).assertEqual(2);
      expect(String(result.json['answer'])).assertEqual('$$\n\\frac{x}{y}\n$$');
      expect(fake.calls[1][fake.calls[1].length - 1].content).assertContain('answer violates MM-MD-v1');
    });
  });
}
