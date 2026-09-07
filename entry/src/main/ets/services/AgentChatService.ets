import {
  KnowledgeUnit,
  ClassificationResult,
  LlmClient,
  LlmConfig,
  ChatMessage,
  LlmGuard,
  ContentProtocol,
} from 'common';
import type { ContentValidationResult, LlmCallResult, LlmGuardJsonResult, LlmGuardValidationResult } from 'common';
import { common } from '@kit.AbilityKit';
import { AiService } from './AiService';
import { AgentMemoryService } from './AgentMemoryService';
import type { ChatStatusMeta, ChatStatusStep } from '../overlays/AgentFloatWindow/chat/ChatModels';
import { IntentClassifier } from './IntentClassifier';
import type { TextIntent } from './IntentClassifier';
import { ChatStatusMachine } from './ChatStatusMachine';


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
  private intentClassifier: IntentClassifier = new IntentClassifier();
  private statusMachine: ChatStatusMachine = new ChatStatusMachine();

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
      const intent: TextIntent = await this.intentClassifier.classify(userContent);
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
      const intent: TextIntent = await this.intentClassifier.classify(userContent);
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
          messages: this.intentClassifier.buildReplyMessages(memoryContext, learnerProfileContext, userContent),
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
            messages: this.intentClassifier.buildReplyMessages(memoryContext, learnerProfileContext, userContent),
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
    const intent: TextIntent = await this.intentClassifier.classify(userInstruction);
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
        conversation = this.intentClassifier.inlineNoteMaterial(userInstruction);
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


  private async callChatAnswerWithRetry(
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
  ): Promise<string> {
    const guarded: LlmGuardJsonResult = await new LlmGuard().callJsonWithRetry(
      this.intentClassifier.buildReplyMessages(memoryContext, learnerProfileContext, userContent),
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


  private clip(text: string, limit: number): string {
    if (text.length <= limit) { return text; }
    return text.substring(0, limit) + '\n...';
  }

  private setStep(step: ChatStatusStep): void {
    this.cbs.setStatusMeta(this.statusMachine.advance(step));
  }

  private finishBusy(): void {
    this.cbs.setStatusMeta(null);
    this.cbs.setBusy(false);
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
