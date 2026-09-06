import {
  KnowledgeUnit,
  ClassificationResult,
  LlmClient,
  LlmConfig,
  ChatMessage,
  LlmGuard,
  ContentProtocol,
  JSON_ONLY_RULES,
  LATEX_GENERATION_RULES,
} from 'common';
import type { ContentValidationResult, LlmCallResult, LlmGuardJsonResult, LlmGuardValidationResult } from 'common';
import { common } from '@kit.AbilityKit';
import { AiService } from './AiService';
import { AgentMemoryService } from './AgentMemoryService';
import type { ChatStatusMeta, ChatStatusStep } from '../overlays/AgentFloatWindow/chat/ChatModels';

type TextIntent = 'note_generation' | 'chat';

export interface AgentChatCallbacks {
  addAiMsg: (content: string) => void;
  // 流式回调: 创建空 AI 消息,返回 msgId (用于后续增量追加)
  addAiMsgEmpty: () => number;
  // 流式回调: 向指定 msgId 追加 delta 文本 (kind 区分思考/正式回答, 默认 content)
  appendAiMsg: (id: number, delta: string, kind?: 'reasoning' | 'content') => void;
  // 流式回调: 标记流式消息完成
  finishAiMsg: (id: number) => void;
  bumpNotesVersion: () => void;
  setBusy: (v: boolean) => void;
  setStatusMeta: (meta: ChatStatusMeta | null) => void;
  getContext: () => common.UIAbilityContext;
  getConversationText: (excludeLatestUser: boolean) => string;
  getSessionId: () => string;
}

export class AgentChatService {
  private cbs: AgentChatCallbacks;
  private memory: AgentMemoryService | null = null;
  private contentProtocol: ContentProtocol = new ContentProtocol();

  constructor(callbacks: AgentChatCallbacks) {
    this.cbs = callbacks;
  }

  async captureReply(imageUri: string, userText: string): Promise<void> {
    const sessionId: string = this.currentSessionId();
    this.cbs.setBusy(true);
    this.setStep('image_message_save');
    try {
      await this.safeSaveUserMessage(sessionId, userText.trim().length > 0 ? userText : '[图片]');
      this.setStep('image_recognize');
      const result: ClassificationResult = await new AiService(this.cbs.getContext()).analyzeImage(imageUri, userText);
      this.setStep('image_material_save');
      await this.safeSaveOcrResult(sessionId, imageUri, userText, result);
      const reply: string = this.formatAnalyzeReply(result);
      await this.addAiMessage(sessionId, reply);
      this.setStep('completed');
    } catch (e) {
      await this.addAiMessage(sessionId, '图片识别失败: ' + AgentChatService.errorMessage(e).substring(0, 120));
    } finally {
      this.finishBusy();
    }
  }

  async realReply(userContent: string): Promise<void> {
    const sessionId: string = this.currentSessionId();
    this.cbs.setBusy(true);
    this.setStep('intent_check');
    try {
      const intent: TextIntent = await this.classifyTextIntent(userContent);
      if (intent === 'note_generation') {
        const generated: boolean = await this.generateNoteFromConversation(sessionId, userContent);
        if (generated) {
          this.setStep('completed');
        } else {
          this.setStep('completed');
        }
        return;
      }

      this.setStep('reply_context_load');
      const memoryContext: string = await this.safeGetContextForReply(sessionId);
      const learnerProfileContext: string = await this.safeGetLearnerProfileContext(sessionId);
      await this.safeSaveUserMessage(sessionId, userContent);
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
        this.setStep('completed');
        return;
      }
      this.setStep('reply_model_call');
      const reply: string = await this.callChatAnswerWithRetry(memoryContext, learnerProfileContext, userContent);
      await this.addAiMessage(sessionId, reply);
      this.finishBusy();
      await this.safeUpdateLearnerProfileIfNeeded(sessionId);
      await this.safeSummarizeIfNeeded(sessionId);
    } catch (e) {
      const errMsg: string = AgentChatService.errorMessage(e);
      if (errMsg.indexOf('NO_API_KEY') >= 0) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
      } else if (errMsg.indexOf('NETWORK_ERROR') >= 0) {
        await this.addAiMessage(sessionId, '⚠️ 网络连接失败，请检查网络后重试');
      } else {
        await this.addAiMessage(sessionId, '⚠️ AI 回复异常: ' + errMsg.substring(0, 100));
      }
    } finally {
      this.finishBusy();
    }
  }

  /**
   * 流式回复 — 基于 DeepSeek SSE,逐 token 实时推送 UI
   * 非流式 realReply() 作为回退保留,当 callStream 失败时自动降级
   */
  async realReplyStream(userContent: string): Promise<void> {
    const sessionId: string = this.currentSessionId();
    this.cbs.setBusy(true);
    this.setStep('intent_check');
    try {
      const intent: TextIntent = await this.classifyTextIntent(userContent);
      if (intent === 'note_generation') {
        // 笔记生成目前仍走非流式
        const generated: boolean = await this.generateNoteFromConversation(sessionId, userContent);
        if (generated) {
          this.setStep('completed');
        } else {
          this.setStep('completed');
        }
        return;
      }

      this.setStep('reply_context_load');
      const memoryContext: string = await this.safeGetContextForReply(sessionId);
      const learnerProfileContext: string = await this.safeGetLearnerProfileContext(sessionId);
      await this.safeSaveUserMessage(sessionId, userContent);
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
        this.setStep('completed');
        return;
      }

      // 创建空消息占位,拿到 msgId
      const msgId: number = this.cbs.addAiMsgEmpty();
      this.setStep('reply_model_call');

      const client: LlmClient = new LlmClient();
      let accumulatedContent: string = '';

      try {
        // 优先真流式 (SSE requestInStream),失败时降级非流式
        await client.call({
          messages: this.buildReplyMessages(memoryContext, learnerProfileContext, userContent),
          stream: true,
          onDelta: (delta: string, kind: 'reasoning' | 'content'): void => {
            if (kind !== 'content') { return; }
            accumulatedContent += delta;
            this.cbs.appendAiMsg(msgId, delta, 'content');
          },
          maxTokens: 4096,
          timeoutMs: 120000,
          enableThinking: LlmConfig.getInstance().getEnableThinking(),
        });
        this.setStep('completed');
        this.cbs.finishAiMsg(msgId);
      } catch (streamErr) {
        // 流式失败: 保留已展示的部分内容 + 追加错误提示
        if (accumulatedContent.length > 0) {
          this.cbs.appendAiMsg(msgId, '\n\n⚠️ *AI 回复中断，请重试*');
          this.cbs.finishAiMsg(msgId);
          // 保存已收到的部分内容
          await this.safeSaveAssistantMessage(sessionId, accumulatedContent);
          return;  // 阻止 fall-through 到成功路径导致的 double-finish
        } else {
          // 完全失败,降级到非流式
          this.cbs.finishAiMsg(msgId);
          const fallbackResult: LlmCallResult = await client.call({
            messages: this.buildReplyMessages(memoryContext, learnerProfileContext, userContent),
            maxTokens: 4096,
            timeoutMs: 120000,
          });
          await this.addAiMessage(sessionId, fallbackResult.text ?? '');
          this.finishBusy();
          return;
        }
      }

      // 异步持久化完整内容
      await this.safeSaveAssistantMessage(sessionId, accumulatedContent);
      await this.safeUpdateLearnerProfileIfNeeded(sessionId);
      await this.safeSummarizeIfNeeded(sessionId);
    } catch (e) {
      const errMsg: string = AgentChatService.errorMessage(e);
      if (errMsg.indexOf('NO_API_KEY') >= 0) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
      } else if (errMsg.indexOf('NETWORK_ERROR') >= 0) {
        await this.addAiMessage(sessionId, '⚠️ 网络连接失败，请检查网络后重试');
      } else {
        await this.addAiMessage(sessionId, '⚠️ AI 回复异常: ' + errMsg.substring(0, 100));
      }
    } finally {
      this.finishBusy();
    }
  }

  private async generateNoteFromConversation(sessionId: string, userInstruction: string): Promise<boolean> {
    this.setStep('note_intent_check');
    const intent: TextIntent = await this.classifyTextIntent(userInstruction);
    if (intent !== 'note_generation') {
      console.warn('[AgentChatService] blocked note generation without explicit intent');
      return false;
    }
    this.setStep('note_context_load');
    const memoryContext: string = await this.safeGetContextForNoteGeneration(sessionId);
    this.setStep('note_source_prepare');
    await this.safeSaveUserMessage(sessionId, userInstruction);
    try {
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
        return false;
      }

      let conversation: string = memoryContext.trim();
      if (conversation.length === 0) {
        conversation = this.cbs.getConversationText(true).trim();
      }
      if (conversation.length === 0) {
        conversation = this.inlineNoteMaterial(userInstruction);
      }
      if (conversation.length === 0) {
        await this.addAiMessage(sessionId, '当前会话还没有可整理的内容');
        return false;
      }

      this.setStep('note_material_summary');
      const summary: string = await this.summarizeConversation(conversation, userInstruction);
      this.setStep('note_structure_save');
      const unit: KnowledgeUnit = await new AiService(this.cbs.getContext()).captureText(summary);
      this.cbs.bumpNotesVersion();
      this.setStep('note_finalize');
      await this.safeMarkPendingMaterialUsed(sessionId);
      await this.addAiMessage(sessionId, '已生成笔记：' + unit.title);
      await this.safeSummarizeIfNeeded(sessionId);
      return true;
    } catch (e) {
      const errMsg: string = AgentChatService.errorMessage(e);
      await this.addAiMessage(sessionId, '生成笔记失败: ' + errMsg.substring(0, 120));
      return false;
    }
  }

  private async summarizeConversation(conversation: string, userInstruction: string): Promise<string> {
    const clipped: string = this.clip(conversation, 32000);
    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: '你负责把 MindTrace 当前对话整理成 KnowledgeModel.structure 可直接使用的“完整笔记原材料”，不是短摘要。请用稳定、结构化的中文输出，包含：主题/标题候选、原题或原始材料、关键公式、推导/步骤、结论、易错点、用户补充、上下文来源。不要丢数学细节，不要只给一句总结，不要输出 markdown 代码块，不要编造对话中没有的信息；无法确定的内容标注为“未提供”或省略。',
      },
      {
        role: 'user',
        content: '用户生成指令:\n' + userInstruction + '\n\n当前记忆上下文:\n' + clipped,
      },
    ];
    const client: LlmClient = new LlmClient();
    const result: LlmCallResult = await client.call({
      messages: messages,
      maxTokens: 8192,
      timeoutMs: 120000,
    });
    return result.text ?? '';
  }

  private buildReplyMessages(memoryContext: string, learnerProfileContext: string, userContent: string): ChatMessage[] {
    let systemPrompt: string = '你是 MindTrace AI 数学助手。回答要求：\n'
      + '1. 先判断用户当前意图，再结合 Learner profile 的生效水平调整解释密度；不要把所有问题套成同一种结构。\n'
      + '2. 当前用户明确要求“详细讲”“像小白一样讲”“直接给答案”“不要展开”时，本轮优先服从当前指令，而不是画像。\n'
      + '3. beginner：少术语，多直观解释、例子和关键易错点；步骤可以更细，但仍要避免空泛寒暄。\n'
      + '4. novice：默认给思路、必要步骤和结论；只在概念题、用户困惑或关键门槛处补直观解释，不要每题都写完整四段式。\n'
      + '5. advanced：默认直接给公式、推导主线、结论和边界条件；压缩基础定义、直观比喻和常见误区，除非用户要求展开。\n'
      + '6. 简单事实或短计算：先给答案，再用 1-3 个短步骤说明理由。\n'
      + '7. 总结/整理/复盘：使用标题和要点，覆盖核心结论、原因、方法、待补充内容；不要只输出一句总结。\n'
      + '8. 信息不足时先说明缺少什么，可以基于上文给出合理假设；无法确定时追问，不编造题目或结论。\n'
      + '9. 不要主动生成笔记；只有系统已判定用户明确要保存/生成笔记时，才会走笔记生成链路。\n'
      + '10. 只输出严格 JSON 对象，格式固定为 {"answer":"..."}；不要输出 JSON 代码块、解释或额外文本。\n'
      + '11. answer 字段采用 MM-MD-v1 子集：只使用标题、段落、单层有序/无序列表、加粗、行内代码和代码块；不要输出原始 HTML、Markdown 表格、任务列表、脚注或 Mermaid。\n'
      + '12. 短公式必须融入文字并用单个美元符定界，例如 $a>0$；不要输出裸 \\mu、\\sigma、\\Phi、\\operatorname，也不要使用单独的 [ ] 充当公式边界。\n'
      + '13. 重要公式、长公式和多行推导使用展示公式，起止 $$ 必须各占独立一行；不要写成 $$公式$$，不要在 $$ 内嵌套单个美元符，也不要用 Markdown 代码块包公式。\n'
      + '14. 多行公式只能在独立的 $$ 块内使用 \\begin{aligned}...\\end{aligned}；不要使用 align 或 align* 环境。\n'
      + '15. 列表项内只允许短行内公式；长公式和 $$ 定界符必须移到列表外，绝不能写成“1. $$”“2. 公式”“3. $$”。如需分步推导，用“第 1 步：”文字段落，再另起独立 $$ 块。\n\n'
      + JSON_ONLY_RULES + '\n'
      + LATEX_GENERATION_RULES;
    const profileContext: string = learnerProfileContext.trim();
    if (profileContext.length > 0) {
      systemPrompt += '\n\n用户画像如下，只用于控制解释密度和回答粒度，不要在回答中复述画像：\n' + profileContext;
    }
    const context: string = memoryContext.trim();
    if (context.length > 0) {
      systemPrompt += '\n\n可参考的会话记忆如下，只在相关时使用，不要主动生成笔记：\n' + this.clip(context, 12000);
    }
    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: systemPrompt,
      },
      {
        role: 'user',
        content: userContent,
      },
    ];
    return messages;
  }

  private async callChatAnswerWithRetry(
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
  ): Promise<string> {
    const guarded: LlmGuardJsonResult = await new LlmGuard().callJsonWithRetry(
      this.buildReplyMessages(memoryContext, learnerProfileContext, userContent),
      {
        maxTokens: 4096,
        timeoutMs: 120000,
        label: 'chat answer',
      },
      (json: Record<string, Object>): LlmGuardValidationResult => this.validateChatAnswerJson(json),
    );
    const answerValue: Object | undefined = guarded.json['answer'];
    const answer: string = typeof answerValue === 'string' ? answerValue : '';
    const protocolResult: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(answer);
    return protocolResult.normalizedText.length > 0 ? protocolResult.normalizedText : answer;
  }

  private validateChatAnswerJson(json: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    const answerValue: Object | undefined = json['answer'];
    if (typeof answerValue !== 'string') {
      issues.push('answer must be a non-empty string containing the final Markdown reply');
      return { ok: false, issues: issues };
    }
    const answer: string = answerValue.trim();
    if (answer.length === 0) {
      issues.push('answer must not be empty');
      return { ok: false, issues: issues };
    }
    if (this.hasFormulaInCodeBlock(answer)) {
      issues.push('do not wrap formulas in Markdown code fences; use $...$ or independent $$ blocks');
    }
    if (this.hasMermaidCodeBlock(answer)) {
      issues.push('Mermaid blocks are not supported in answer');
    }
    const contentResult: ContentValidationResult = this.contentProtocol.validateNoteMarkdown(answer);
    if (!contentResult.ok) {
      issues.push('answer violates MM-MD-v1: ' + this.describeContentIssues(contentResult));
    }
    return {
      ok: issues.length === 0,
      issues: issues,
    };
  }

  private describeContentIssues(result: ContentValidationResult): string {
    const descriptions: string[] = [];
    for (const issue of result.issues) {
      if (issue === 'list_marker_on_display_delimiter') {
        descriptions.push('display formula fence must not be inside numbered or bullet lists');
      } else if (issue === 'display_formula_inside_text') {
        descriptions.push('display formulas must be separated from surrounding text by blank lines');
      } else if (issue === 'inline_display_fence') {
        descriptions.push('do not write $$formula$$ on one line');
      } else if (issue === 'unclosed_display_delimiter') {
        descriptions.push('display formula $$ block is not closed');
      } else if (issue === 'unclosed_inline_delimiter') {
        descriptions.push('inline formula $...$ is not closed');
      } else if (issue === 'display_delimiter_not_independent') {
        descriptions.push('$$ delimiters must occupy independent lines');
      } else if (issue === 'markdown_table_not_supported') {
        descriptions.push('Markdown tables are not supported');
      } else if (issue === 'raw_html_not_supported') {
        descriptions.push('raw HTML is not supported');
      } else {
        descriptions.push(issue);
      }
    }
    return descriptions.join('; ');
  }

  private hasFormulaInCodeBlock(text: string): boolean {
    let inCode: boolean = false;
    for (const rawLine of text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')) {
      const trimmed: string = rawLine.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
        continue;
      }
      if (inCode && this.contentProtocol.hasFormulaSyntax(rawLine)) {
        return true;
      }
    }
    return false;
  }

  private hasMermaidCodeBlock(text: string): boolean {
    for (const rawLine of text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')) {
      const trimmed: string = rawLine.trim().toLowerCase();
      if (trimmed === '```mermaid') {
        return true;
      }
    }
    return false;
  }

  private async classifyTextIntent(userContent: string): Promise<TextIntent> {
    const normalized: string = userContent.trim();
    if (normalized.length === 0) { return 'chat'; }
    if (this.hasNoteGenerationDenyIntent(normalized)) { return 'chat'; }
    if (this.hasExplicitNoteGenerationIntent(normalized)) { return 'note_generation'; }
    if (!this.shouldUseRemoteIntentClassifier(normalized)) { return 'chat'; }

    try {
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) { return 'chat'; }
      const messages: ChatMessage[] = this.buildIntentMessages(normalized);
      const result = await new LlmGuard().callJsonWithRetry(messages, {
        maxTokens: 80,
        timeoutMs: 30000,
        responseFormat: { type: 'json_object' },
        label: 'text intent classification',
      }, (json: Record<string, Object>): LlmGuardValidationResult => this.validateTextIntentJson(json));
      return this.parseTextIntent(result.raw);
    } catch (e) {
      console.warn('[AgentChatService] text intent classify failed: ' + AgentChatService.errorMessage(e));
      return 'chat';
    }
  }

  private buildIntentMessages(userContent: string): ChatMessage[] {
    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: 'Classify the MindTrace user message intent. Return strict JSON only: {"intent":"note_generation"} or {"intent":"chat"}. note_generation means the user wants current/previous/provided content turned into saveable learning material, such as a note, knowledge point, notebook entry, retained problem record, or material to store for later review. This includes natural requests like remembering/saving the above problem as study material even if the wording is informal. Return chat for normal Q&A, explanation, calculation, practice generation, casual chat, or temporary summarization/organization where the user only wants an answer and does not imply saving or forming reusable learning material. If uncertain, return chat.',
      },
      {
        role: 'user',
        content: userContent,
      },
    ];
    return messages;
  }

  private parseTextIntent(raw: string): TextIntent {
    const jsonText: string = this.extractJsonObject(raw);
    if (jsonText.length === 0) { return 'chat'; }
    try {
      const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
      const value: Object | undefined = parsed['intent'];
      if (typeof value === 'string' && value === 'note_generation') {
        return 'note_generation';
      }
    } catch (e) {
      console.warn('[AgentChatService] parse intent json failed: ' + AgentChatService.errorMessage(e));
    }
    return 'chat';
  }

  private validateTextIntentJson(json: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    const intent: Object | undefined = json['intent'];
    if (typeof intent !== 'string') {
      issues.push('intent must be a string');
    } else if (intent !== 'note_generation' && intent !== 'chat') {
      issues.push('intent must be note_generation or chat');
    }
    return {
      ok: issues.length === 0,
      issues: issues,
    };
  }

  private extractJsonObject(raw: string): string {
    const trimmed: string = raw.trim();
    const codeMatch: RegExpMatchArray | null = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
    let source: string = trimmed;
    if (codeMatch !== null && codeMatch.length >= 2) {
      source = codeMatch[1].trim();
    }
    const braceMatch: RegExpMatchArray | null = source.match(/\{[\s\S]*\}/);
    if (braceMatch !== null && braceMatch.length > 0) {
      return braceMatch[0];
    }
    return '';
  }

  private shouldUseRemoteIntentClassifier(text: string): boolean {
    const intentWords: string[] = [
      '生成',
      '创建',
      '新建',
      '整理',
      '保存',
      '存',
      '记',
      '总结',
      '归纳',
      '提炼',
      '收进',
      '加入',
      '转成',
      '转为',
      '做成',
      '笔记',
      '知识点',
      '上面',
      '上文',
      '刚才',
      '这段',
      '这些',
      '内容',
    ];
    return this.includesAny(text, intentWords);
  }

  private hasNoteGenerationDenyIntent(text: string): boolean {
    const denyPhrases: string[] = [
      '不要生成',
      '别生成',
      '无需生成',
      '不用生成',
      '不要创建',
      '别创建',
      '不要保存',
      '别保存',
      '不要记',
      '别记',
      '不用记',
      '不要笔记',
      '不用笔记',
      '无需笔记',
    ];
    return this.includesAny(text, denyPhrases);
  }

  private hasExplicitNoteGenerationIntent(text: string): boolean {
    const phrases: string[] = [
      '生成笔记',
      '创建笔记',
      '新建笔记',
      '整理成笔记',
      '整理为笔记',
      '保存为笔记',
      '保存成笔记',
      '总结成笔记',
      '总结为笔记',
      '归纳成笔记',
      '归纳为笔记',
      '做成笔记',
      '转成笔记',
      '转为笔记',
      '记一下',
      '记下',
      '记下来',
      '帮我记下来',
      '这个记下来',
      '把这个记下来',
      '把这题记下来',
      '把上面记下来',
      '把刚才记下来',
      '收进笔记',
      '加入笔记',
      '存到笔记',
      '存进笔记',
      '留作笔记',
      '保存这个知识点',
      '把这个知识点存起来',
      '这个知识点存起来',
      '知识点存起来',
      '生成知识点',
      '整理成知识点',
      '整理为知识点',
      '总结成知识点',
      '总结为知识点',
      '提炼成知识点',
      '提炼为知识点',
    ];
    if (this.includesAny(text, phrases)) { return true; }

    const createActions: string[] = ['生成', '创建', '新建'];
    const transformActions: string[] = ['整理成', '整理为', '保存为', '保存成', '总结成', '总结为', '归纳成', '归纳为', '做成', '转成', '转为', '提炼成', '提炼为', '收进', '加入', '存到', '存进', '留作'];
    const noteTargets: string[] = ['笔记', '知识点'];
    const rememberActions: string[] = ['记', '保存', '存'];
    const currentTargets: string[] = ['这个', '这题', '上面', '上文', '刚才', '这段', '这些', '知识点'];
    return this.hasActionNearTarget(text, createActions, noteTargets, 4)
      || this.hasActionNearTarget(text, transformActions, noteTargets, 6)
      || this.hasActionNearTarget(text, currentTargets, rememberActions, 8);
  }

  private inlineNoteMaterial(userInstruction: string): string {
    let text: string = userInstruction.trim();
    const separators: string[] = ['：', ':', '\n'];
    for (const separator of separators) {
      const idx: number = text.indexOf(separator);
      if (idx >= 0 && idx + separator.length < text.length) {
        const tail: string = text.substring(idx + separator.length).trim();
        if (tail.length >= 8) {
          return tail;
        }
      }
    }

    const removablePhrases: string[] = [
      '请帮我',
      '帮我',
      '把这个',
      '把这题',
      '把这段',
      '把上面',
      '把刚才',
      '生成笔记',
      '创建笔记',
      '新建笔记',
      '整理成笔记',
      '整理为笔记',
      '保存为笔记',
      '保存成笔记',
      '总结成笔记',
      '总结为笔记',
      '归纳成笔记',
      '归纳为笔记',
      '做成笔记',
      '转成笔记',
      '转为笔记',
      '收进笔记',
      '加入笔记',
      '存到笔记',
      '存进笔记',
      '留作笔记',
      '记一下',
      '记下来',
      '记下',
    ];
    for (const phrase of removablePhrases) {
      text = text.replace(phrase, ' ');
    }
    text = text.replace(/\s+/g, ' ').trim();
    if (text.length >= 12) {
      return text;
    }
    return '';
  }

  private formatAnalyzeReply(result: ClassificationResult): string {
    const ocrText: string = (result.ocrText ?? '').trim();
    const body: string = ocrText.length > 0 ? this.clip(ocrText, 1600) : '未识别到可展示文本';
    const chapter: string = result.chapter !== undefined && result.chapter.length > 0 ? result.chapter : '未识别';
    return '已识别内容，暂不生成笔记。\n\n'
      + '类型：' + result.type + '\n'
      + '学科：' + result.subject + '\n'
      + '章节：' + chapter + '\n'
      + '置信度：' + result.confidence.toString() + '\n\n'
      + '识别内容：\n' + body + '\n\n'
      + '需要保存时，请发送“生成笔记”或“整理成笔记”。';
  }

  private includesAny(text: string, phrases: string[]): boolean {
    for (const phrase of phrases) {
      if (text.indexOf(phrase) >= 0) { return true; }
    }
    return false;
  }

  private hasActionNearTarget(text: string, actions: string[], targets: string[], maxGap: number): boolean {
    for (const action of actions) {
      let actionIndex: number = text.indexOf(action);
      while (actionIndex >= 0) {
        const afterAction: number = actionIndex + action.length;
        for (const target of targets) {
          const targetIndex: number = text.indexOf(target, afterAction);
          if (targetIndex >= 0 && targetIndex - afterAction <= maxGap) {
            return true;
          }
        }
        actionIndex = text.indexOf(action, afterAction);
      }
    }
    return false;
  }

  private clip(text: string, limit: number): string {
    if (text.length <= limit) { return text; }
    return text.substring(0, limit) + '\n...';
  }

  private setStep(step: ChatStatusStep): void {
    this.cbs.setStatusMeta(AgentChatService.statusFromStep(step));
  }

  private finishBusy(): void {
    this.cbs.setStatusMeta(null);
    this.cbs.setBusy(false);
  }

  private static statusFromStep(step: ChatStatusStep): ChatStatusMeta {
    if (step === 'intent_check') {
      return AgentChatService.status(step, '判断任务', '确认这轮是直接回答还是整理成笔记。');
    }
    if (step === 'reply_context_load') {
      return AgentChatService.status(step, '读取上下文', '取当前会话里和问题有关的内容。');
    }
    if (step === 'reply_model_call') {
      return AgentChatService.status(step, '生成回答', '组织结论、步骤和必要条件。');
    }
    if (step === 'image_message_save') {
      return AgentChatService.status(step, '记录图片问题', '先保存本轮图片和补充说明。');
    }
    if (step === 'image_recognize') {
      return AgentChatService.status(step, '识别图片内容', '读取图片里的题目、公式和文字。');
    }
    if (step === 'image_material_save') {
      return AgentChatService.status(step, '整理识别材料', '把识别结果留作后续笔记素材。');
    }
    if (step === 'note_intent_check') {
      return AgentChatService.status(step, '确认整理需求', '确认这轮需要生成可保存的笔记。');
    }
    if (step === 'note_context_load') {
      return AgentChatService.status(step, '读取笔记材料', '读取当前会话、图片识别结果和待整理内容。');
    }
    if (step === 'note_source_prepare') {
      return AgentChatService.status(step, '整理笔记素材', '确定要写进笔记的原题、公式和关键步骤。');
    }
    if (step === 'note_material_summary') {
      return AgentChatService.status(step, '汇总成笔记底稿', '把零散材料合成一份完整底稿。');
    }
    if (step === 'note_structure_save') {
      return AgentChatService.status(step, '生成并保存笔记', '结构化标题、章节、标签和正文。');
    }
    if (step === 'note_finalize') {
      return AgentChatService.status(step, '更新笔记列表', '刷新本地笔记并标记材料已使用。');
    }
    return AgentChatService.status(step, '完成', '本轮处理已结束。');
  }

  private static status(step: ChatStatusStep, title: string, detail: string): ChatStatusMeta {
    return {
      step: step,
      title: title,
      detail: detail,
    };
  }

  private currentSessionId(): string {
    const sessionId: string = this.cbs.getSessionId();
    return sessionId.length > 0 ? sessionId : 's1';
  }

  private getMemory(): AgentMemoryService {
    if (this.memory === null) {
      this.memory = new AgentMemoryService(this.cbs.getContext());
    }
    return this.memory;
  }

  private async addAiMessage(sessionId: string, content: string): Promise<void> {
    const protocolResult: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(content);
    const displayContent: string = protocolResult.fallbackRequired
      ? content
      : protocolResult.normalizedText;
    if (protocolResult.fallbackRequired) {
      console.warn('[AgentChatService] assistant content protocol fallback: ' + protocolResult.issues.join(','));
    }
    this.cbs.addAiMsg(displayContent);
    await this.safeSaveAssistantMessage(sessionId, displayContent);
  }

  private async safeSaveUserMessage(sessionId: string, content: string): Promise<void> {
    try {
      await this.getMemory().saveMessage(sessionId, 'user', content);
    } catch (e) {
      console.warn('[AgentChatService] save user memory failed: ' + AgentChatService.errorMessage(e));
    }
  }

  private async safeSaveAssistantMessage(sessionId: string, content: string): Promise<void> {
    try {
      await this.getMemory().saveMessage(sessionId, 'assistant', content);
    } catch (e) {
      console.warn('[AgentChatService] save assistant memory failed: ' + AgentChatService.errorMessage(e));
    }
  }

  private async safeSaveOcrResult(
    sessionId: string,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<void> {
    try {
      await this.getMemory().saveOcrResult(sessionId, imageUri, userText, result);
    } catch (e) {
      console.warn('[AgentChatService] save ocr memory failed: ' + AgentChatService.errorMessage(e));
    }
  }

  private async safeGetContextForReply(sessionId: string): Promise<string> {
    try {
      return await this.getMemory().getContextForReply(sessionId);
    } catch (e) {
      console.warn('[AgentChatService] load reply memory failed: ' + AgentChatService.errorMessage(e));
      return '';
    }
  }

  private async safeGetContextForNoteGeneration(sessionId: string): Promise<string> {
    try {
      return await this.getMemory().getContextForNoteGeneration(sessionId);
    } catch (e) {
      console.warn('[AgentChatService] load note memory failed: ' + AgentChatService.errorMessage(e));
      return '';
    }
  }

  private async safeGetLearnerProfileContext(sessionId: string): Promise<string> {
    try {
      return await this.getMemory().getLearnerProfileContext(sessionId);
    } catch (e) {
      console.warn('[AgentChatService] load learner profile failed: ' + AgentChatService.errorMessage(e));
      return '';
    }
  }

  private async safeUpdateLearnerProfileIfNeeded(sessionId: string): Promise<void> {
    try {
      await this.getMemory().updateLearnerProfileIfNeeded(sessionId);
    } catch (e) {
      console.warn('[AgentChatService] update learner profile failed: ' + AgentChatService.errorMessage(e));
    }
  }

  private async safeMarkPendingMaterialUsed(sessionId: string): Promise<void> {
    try {
      await this.getMemory().markPendingMaterialUsed(sessionId);
    } catch (e) {
      console.warn('[AgentChatService] mark pending memory failed: ' + AgentChatService.errorMessage(e));
    }
  }

  private async safeSummarizeIfNeeded(sessionId: string): Promise<void> {
    try {
      await this.getMemory().summarizeSessionIfNeeded(sessionId);
    } catch (e) {
      console.warn('[AgentChatService] summarize memory failed: ' + AgentChatService.errorMessage(e));
    }
  }

  private static errorMessage(e: Object): string {
    const message: string | undefined = (e as Error).message;
    if (message !== undefined && message.length > 0) {
      return message;
    }
    return JSON.stringify(e);
  }
}
