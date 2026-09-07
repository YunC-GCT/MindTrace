import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ClassificationResult, ChatMessage, DatabaseHelper, LlmCallResult, LlmClient, LlmConfig, LlmGuard } from 'common';
import type { LlmGuardValidationResult } from 'common';
import { AgentMemoryDao } from '../database/AgentMemoryDao';
import { ChatMessageDao } from '../database/ChatMessageDao';
import {
  AgentMemoryRecord,
  ChatMessageRecord,
  ChatRole,
  LearnerLevel,
  LearnerProfile,
} from '../models/AgentMemoryModels';

const RECENT_REPLY_LIMIT: number = 28;
const RECENT_NOTE_LIMIT: number = 100;
const SUMMARY_THRESHOLD: number = 30;
const SUMMARY_UPDATE_MESSAGE_GAP: number = 16;
const REPLY_CONTEXT_LIMIT: number = 12000;
const NOTE_CONTEXT_LIMIT: number = 32000;
const SUMMARY_CONTEXT_LIMIT: number = 24000;
const PROFILE_GLOBAL_SESSION_ID: string = '__global__';
const PROFILE_SOURCE: string = 'learner_profile';
const PROFILE_UPDATE_USER_MESSAGE_GAP: number = 6;
const PROFILE_CONTEXT_RECENT_LIMIT: number = 24;
const PROFILE_EVIDENCE_LIMIT: number = 160;

export class AgentMemoryService {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async saveMessage(sessionId: string, role: ChatRole, content: string): Promise<void> {
    const text: string = content.trim();
    if (sessionId.length === 0 || text.length === 0) {
      return;
    }
    const now: number = Date.now();
    const record: ChatMessageRecord = {
      id: AgentMemoryService.newId('msg'),
      sessionId: sessionId,
      role: role,
      content: text,
      createdAt: now,
    };
    const store: relationalStore.RdbStore = await this.getStore();
    await new ChatMessageDao(store).insert(record);
  }

  async savePendingNoteMaterial(sessionId: string, content: string, source: string): Promise<void> {
    const text: string = content.trim();
    if (sessionId.length === 0 || text.length === 0) {
      return;
    }
    const now: number = Date.now();
    const record: AgentMemoryRecord = {
      id: AgentMemoryService.newId('mem'),
      sessionId: sessionId,
      type: 'pending_note',
      content: text,
      source: source,
      used: 0,
      createdAt: now,
      updatedAt: now,
    };
    const store: relationalStore.RdbStore = await this.getStore();
    await new AgentMemoryDao(store).insert(record);
  }

  async saveOcrResult(
    sessionId: string,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<void> {
    const lines: string[] = [];
    const instruction: string = userText.trim();
    const ocrText: string = (result.ocrText ?? '').trim();
    const chapter: string = result.chapter !== undefined && result.chapter.length > 0 ? result.chapter : '';
    lines.push('图片识别材料');
    if (instruction.length > 0) {
      lines.push('用户补充: ' + instruction);
    }
    lines.push('类型: ' + result.type);
    lines.push('学科: ' + result.subject);
    if (chapter.length > 0) {
      lines.push('章节: ' + chapter);
    }
    lines.push('置信度: ' + result.confidence.toString());
    if (ocrText.length > 0) {
      lines.push('OCR:');
      lines.push(ocrText);
    }
    await this.savePendingNoteMaterial(sessionId, lines.join('\n'), imageUri);
  }

  async getContextForReply(sessionId: string): Promise<string> {
    const store: relationalStore.RdbStore = await this.getStore();
    const memoryDao: AgentMemoryDao = new AgentMemoryDao(store);
    const messageDao: ChatMessageDao = new ChatMessageDao(store);
    const summary: AgentMemoryRecord | null = await memoryDao.queryLatestSummary(sessionId);
    const messages: ChatMessageRecord[] = await messageDao.queryRecent(sessionId, RECENT_REPLY_LIMIT);
    return AgentMemoryService.buildContextText(summary, [], messages, REPLY_CONTEXT_LIMIT);
  }

  async getContextForNoteGeneration(sessionId: string): Promise<string> {
    const store: relationalStore.RdbStore = await this.getStore();
    const memoryDao: AgentMemoryDao = new AgentMemoryDao(store);
    const messageDao: ChatMessageDao = new ChatMessageDao(store);
    const summary: AgentMemoryRecord | null = await memoryDao.queryLatestSummary(sessionId);
    const pendingNotes: AgentMemoryRecord[] = await memoryDao.queryPendingNotes(sessionId);
    const messages: ChatMessageRecord[] = await messageDao.queryRecent(sessionId, RECENT_NOTE_LIMIT);
    return AgentMemoryService.buildContextText(summary, pendingNotes, messages, NOTE_CONTEXT_LIMIT);
  }

  async getLearnerProfileContext(sessionId: string): Promise<string> {
    const store: relationalStore.RdbStore = await this.getStore();
    const memoryDao: AgentMemoryDao = new AgentMemoryDao(store);
    const globalRecord: AgentMemoryRecord | null =
      await memoryDao.queryLatestProfile(PROFILE_GLOBAL_SESSION_ID, PROFILE_SOURCE);
    const sessionRecord: AgentMemoryRecord | null = await memoryDao.queryLatestProfile(sessionId, PROFILE_SOURCE);
    const globalProfile: LearnerProfile | null = AgentMemoryService.parseLearnerProfile(globalRecord);
    const sessionProfile: LearnerProfile | null = AgentMemoryService.parseLearnerProfile(sessionRecord);
    const profile: LearnerProfile = AgentMemoryService.mergeLearnerProfile(globalProfile, sessionProfile);
    return AgentMemoryService.formatLearnerProfileContext(profile, globalProfile, sessionProfile);
  }

  async updateLearnerProfileIfNeeded(sessionId: string): Promise<void> {
    if (sessionId.length === 0) {
      return;
    }
    const store: relationalStore.RdbStore = await this.getStore();
    const memoryDao: AgentMemoryDao = new AgentMemoryDao(store);
    const messageDao: ChatMessageDao = new ChatMessageDao(store);
    const sessionRecord: AgentMemoryRecord | null = await memoryDao.queryLatestProfile(sessionId, PROFILE_SOURCE);
    const messages: ChatMessageRecord[] = await messageDao.queryAll(sessionId);
    const userMessagesAfterProfile: number = AgentMemoryService.countUserMessagesAfter(messages, sessionRecord);
    if (userMessagesAfterProfile < PROFILE_UPDATE_USER_MESSAGE_GAP) {
      return;
    }

    const configured: boolean = await LlmConfig.getInstance().isConfigured();
    if (!configured) {
      return;
    }

    const globalRecord: AgentMemoryRecord | null =
      await memoryDao.queryLatestProfile(PROFILE_GLOBAL_SESSION_ID, PROFILE_SOURCE);
    const globalProfile: LearnerProfile | null = AgentMemoryService.parseLearnerProfile(globalRecord);
    const sessionProfile: LearnerProfile | null = AgentMemoryService.parseLearnerProfile(sessionRecord);
    const currentProfile: LearnerProfile = AgentMemoryService.mergeLearnerProfile(globalProfile, sessionProfile);
    const recentMessages: ChatMessageRecord[] = await messageDao.queryRecent(sessionId, PROFILE_CONTEXT_RECENT_LIMIT);
    const llmMessages: ChatMessage[] = AgentMemoryService.buildLearnerProfileMessages(currentProfile, recentMessages);
    const raw = await new LlmGuard().callJsonWithRetry(llmMessages, {
      maxTokens: 512,
      timeoutMs: 60000,
      responseFormat: { type: 'json_object' },
      label: 'learner profile update',
    }, (json: Record<string, Object>): LlmGuardValidationResult => AgentMemoryService.validateLearnerProfileJson(json));
    const updated: LearnerProfile | null = AgentMemoryService.parseLearnerProfileJson(raw.raw, Date.now());
    if (updated === null) {
      return;
    }

    await memoryDao.insert(AgentMemoryService.toProfileRecord(
      PROFILE_GLOBAL_SESSION_ID,
      AgentMemoryService.withSessionLevel(updated, updated.globalLevel),
    ));
    await memoryDao.insert(AgentMemoryService.toProfileRecord(sessionId, updated));
  }

  async summarizeSessionIfNeeded(sessionId: string): Promise<void> {
    const store: relationalStore.RdbStore = await this.getStore();
    const memoryDao: AgentMemoryDao = new AgentMemoryDao(store);
    const existingSummary: AgentMemoryRecord | null = await memoryDao.queryLatestSummary(sessionId);

    const messages: ChatMessageRecord[] = await new ChatMessageDao(store).queryAll(sessionId);
    if (messages.length <= SUMMARY_THRESHOLD) {
      return;
    }

    const messagesAfterSummary: ChatMessageRecord[] = AgentMemoryService.messagesAfterSummary(messages, existingSummary);
    if (existingSummary !== null && messagesAfterSummary.length < SUMMARY_UPDATE_MESSAGE_GAP) {
      return;
    }

    const configured: boolean = await LlmConfig.getInstance().isConfigured();
    if (!configured) {
      return;
    }

    const content: string = AgentMemoryService.buildSummarySource(existingSummary, messages, messagesAfterSummary);
    const llmMessages: ChatMessage[] = [
      {
        role: 'system',
        content: '请把 MindTrace 当前会话更新为后续对话可用的 session summary。输出稳定、结构化、信息密集的中文摘要，保留：题目/原始材料、关键公式、用户目标、已识别 OCR 材料、已讲解结论、待整理内容、未解决问题。避免寒暄、评价和重复；不要编造没有出现在材料里的信息；如果某项没有信息可省略。已有 summary 只是参考，请结合新增消息生成一份最新 summary。',
      },
      {
        role: 'user',
        content: content,
      },
    ];
    const summaryResult: LlmCallResult = await new LlmClient().call({
      messages: llmMessages,
      maxTokens: 2048,
      timeoutMs: 120000,
    });
    const summaryText: string = summaryResult.text ?? '';
    const now: number = Date.now();
    const summaryRecord: AgentMemoryRecord = {
      id: AgentMemoryService.newId('sum'),
      sessionId: sessionId,
      type: 'summary',
      content: summaryText,
      source: 'session',
      used: 0,
      createdAt: now,
      updatedAt: now,
    };
    await memoryDao.insert(summaryRecord);
  }

  async markPendingMaterialUsed(sessionId: string): Promise<void> {
    const store: relationalStore.RdbStore = await this.getStore();
    await new AgentMemoryDao(store).markPendingUsed(sessionId);
  }

  private async getStore(): Promise<relationalStore.RdbStore> {
    let store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      store = await DatabaseHelper.init(this.context);
    }
    return store;
  }

  private static buildContextText(
    summary: AgentMemoryRecord | null,
    pendingNotes: AgentMemoryRecord[],
    messages: ChatMessageRecord[],
    limit: number,
  ): string {
    const parts: string[] = [];
    if (summary !== null && summary.content.trim().length > 0) {
      parts.push('Session summary:\n' + summary.content.trim());
    }
    if (pendingNotes.length > 0) {
      const pendingLines: string[] = [];
      for (const pending of pendingNotes) {
        if (pending.content.trim().length > 0) {
          pendingLines.push(pending.content.trim());
        }
      }
      if (pendingLines.length > 0) {
        parts.push('Pending note materials:\n' + pendingLines.join('\n\n'));
      }
    }
    if (messages.length > 0) {
      parts.push('Recent messages:\n' + AgentMemoryService.formatMessages(messages, limit));
    }
    return AgentMemoryService.clip(parts.join('\n\n'), limit);
  }

  private static buildSummarySource(
    existingSummary: AgentMemoryRecord | null,
    messages: ChatMessageRecord[],
    messagesAfterSummary: ChatMessageRecord[],
  ): string {
    const parts: string[] = [];
    if (existingSummary !== null && existingSummary.content.trim().length > 0) {
      parts.push('Existing session summary:\n' + existingSummary.content.trim());
      parts.push('New messages after existing summary:\n'
        + AgentMemoryService.formatMessages(messagesAfterSummary, SUMMARY_CONTEXT_LIMIT));
    } else {
      parts.push('Session messages:\n' + AgentMemoryService.formatMessages(messages, SUMMARY_CONTEXT_LIMIT));
    }
    return AgentMemoryService.clip(parts.join('\n\n'), SUMMARY_CONTEXT_LIMIT);
  }

  private static messagesAfterSummary(
    messages: ChatMessageRecord[],
    summary: AgentMemoryRecord | null,
  ): ChatMessageRecord[] {
    if (summary === null) {
      return messages;
    }
    const result: ChatMessageRecord[] = [];
    for (const message of messages) {
      if (message.createdAt > summary.createdAt) {
        result.push(message);
      }
    }
    return result;
  }

  private static formatMessages(messages: ChatMessageRecord[], limit: number): string {
    const lines: string[] = [];
    let size: number = 0;
    for (const message of messages) {
      const roleLabel: string = AgentMemoryService.roleLabel(message.role);
      const line: string = roleLabel + ': ' + message.content.trim();
      if (line.length > 0) {
        lines.push(line);
        size += line.length;
      }
      if (size >= limit) {
        break;
      }
    }
    return AgentMemoryService.clip(lines.join('\n\n'), limit);
  }

  private static roleLabel(role: ChatRole): string {
    if (role === 'assistant') {
      return 'AI';
    }
    if (role === 'system') {
      return 'System';
    }
    return 'User';
  }

  private static buildLearnerProfileMessages(
    currentProfile: LearnerProfile,
    recentMessages: ChatMessageRecord[],
  ): ChatMessage[] {
    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: '你负责判断 MindTrace 用户的数学学习水平画像。只输出严格 JSON，不要解释。画像分三档：beginner=小白，常要求基础解释、直观例子、步骤很细；novice=初识者，能跟随常规步骤但仍需要关键解释；advanced=精通者，能使用专业术语，关注证明、边界条件、推导效率。请保守更新，不要因为单句话大幅改变画像；无法确定时保持当前水平。globalLevel 表示用户长期整体水平，sessionLevel 表示当前会话/当前主题熟悉度，confidence 是 0 到 1，evidence 用一句中文概括依据且不超过 60 字。输出格式必须是 {"globalLevel":"beginner|novice|advanced","sessionLevel":"beginner|novice|advanced","confidence":0.0,"evidence":"简短依据"}。',
      },
      {
        role: 'user',
        content: '当前画像:\n'
          + JSON.stringify(currentProfile)
          + '\n\n最近对话:\n'
          + AgentMemoryService.formatMessages(recentMessages, 6000),
      },
    ];
    return messages;
  }

  private static formatLearnerProfileContext(
    profile: LearnerProfile,
    globalProfile: LearnerProfile | null,
    sessionProfile: LearnerProfile | null,
  ): string {
    const lines: string[] = [];
    lines.push('Learner profile:');
    lines.push('全局水平: ' + profile.globalLevel + '（' + AgentMemoryService.levelLabel(profile.globalLevel) + '）');
    lines.push('当前会话水平: ' + profile.sessionLevel + '（' + AgentMemoryService.levelLabel(profile.sessionLevel) + '）');
    lines.push('生效水平: ' + profile.effectiveLevel + '（' + AgentMemoryService.levelLabel(profile.effectiveLevel) + '）');
    lines.push('置信度: ' + profile.confidence.toString());
    if (profile.evidence.trim().length > 0) {
      lines.push('依据: ' + AgentMemoryService.clip(profile.evidence.trim(), PROFILE_EVIDENCE_LIMIT));
    }
    if (globalProfile === null && sessionProfile === null) {
      lines.push('状态: 暂无历史画像，使用默认 advanced。');
    }
    lines.push('使用规则: 按生效水平调节解释密度；当前用户明确要求详细、简短、像小白一样讲或直接给结论时，以当前指令优先。');
    return lines.join('\n');
  }

  private static parseLearnerProfile(record: AgentMemoryRecord | null): LearnerProfile | null {
    if (record === null || record.content.trim().length === 0) {
      return null;
    }
    return AgentMemoryService.parseLearnerProfileJson(record.content, record.updatedAt);
  }

  private static validateLearnerProfileJson(json: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    if (AgentMemoryService.parseLearnerLevel(json['globalLevel']) === null) {
      issues.push('globalLevel must be beginner, novice, or advanced');
    }
    if (AgentMemoryService.parseLearnerLevel(json['sessionLevel']) === null) {
      issues.push('sessionLevel must be beginner, novice, or advanced');
    }
    const confidence: Object | undefined = json['confidence'];
    if (typeof confidence !== 'number' && typeof confidence !== 'string') {
      issues.push('confidence must be numeric from 0 to 1');
    } else {
      const value: number = Number(confidence);
      if (Number.isNaN(value) || value < 0 || value > 1) {
        issues.push('confidence must be numeric from 0 to 1');
      }
    }
    if (typeof json['evidence'] !== 'string') {
      issues.push('evidence must be a string');
    }
    return {
      ok: issues.length === 0,
      issues: issues,
    };
  }

  private static parseLearnerProfileJson(raw: string, fallbackUpdatedAt: number): LearnerProfile | null {
    const jsonText: string = AgentMemoryService.extractJsonObject(raw);
    if (jsonText.length === 0) {
      return null;
    }
    try {
      const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
      const globalLevel: LearnerLevel | null = AgentMemoryService.parseLearnerLevel(parsed['globalLevel']);
      const sessionLevel: LearnerLevel | null = AgentMemoryService.parseLearnerLevel(parsed['sessionLevel']);
      if (globalLevel === null || sessionLevel === null) {
        return null;
      }
      const confidence: number = AgentMemoryService.normalizeConfidence(parsed['confidence']);
      const evidenceValue: Object | undefined = parsed['evidence'];
      const evidence: string = typeof evidenceValue === 'string'
        ? AgentMemoryService.clip(evidenceValue.trim(), PROFILE_EVIDENCE_LIMIT)
        : '';
      const updatedAtValue: Object | undefined = parsed['updatedAt'];
      const updatedAt: number = typeof updatedAtValue === 'number' && updatedAtValue > 0
        ? updatedAtValue
        : fallbackUpdatedAt;
      return {
        globalLevel: globalLevel,
        sessionLevel: sessionLevel,
        effectiveLevel: AgentMemoryService.effectiveLevel(globalLevel, sessionLevel),
        confidence: confidence,
        evidence: evidence,
        updatedAt: updatedAt,
      };
    } catch (e) {
      console.warn('[AgentMemoryService] parse learner profile failed: ' + AgentMemoryService.errorMessage(e));
      return null;
    }
  }

  private static mergeLearnerProfile(
    globalProfile: LearnerProfile | null,
    sessionProfile: LearnerProfile | null,
  ): LearnerProfile {
    const globalLevel: LearnerLevel = globalProfile !== null ? globalProfile.globalLevel : 'advanced';
    const sessionLevel: LearnerLevel = sessionProfile !== null ? sessionProfile.sessionLevel : globalLevel;
    const confidence: number = sessionProfile !== null
      ? sessionProfile.confidence
      : (globalProfile !== null ? globalProfile.confidence : 0);
    const evidenceParts: string[] = [];
    if (globalProfile !== null && globalProfile.evidence.trim().length > 0) {
      evidenceParts.push('全局: ' + globalProfile.evidence.trim());
    }
    if (sessionProfile !== null && sessionProfile.evidence.trim().length > 0) {
      evidenceParts.push('会话: ' + sessionProfile.evidence.trim());
    }
    const updatedAt: number = Math.max(
      globalProfile !== null ? globalProfile.updatedAt : 0,
      sessionProfile !== null ? sessionProfile.updatedAt : 0,
    );
    return {
      globalLevel: globalLevel,
      sessionLevel: sessionLevel,
      effectiveLevel: AgentMemoryService.effectiveLevel(globalLevel, sessionLevel),
      confidence: confidence,
      evidence: AgentMemoryService.clip(evidenceParts.join('；'), PROFILE_EVIDENCE_LIMIT),
      updatedAt: updatedAt,
    };
  }

  private static toProfileRecord(sessionId: string, profile: LearnerProfile): AgentMemoryRecord {
    const now: number = profile.updatedAt > 0 ? profile.updatedAt : Date.now();
    return {
      id: AgentMemoryService.newId('profile'),
      sessionId: sessionId,
      type: 'profile',
      content: JSON.stringify(profile),
      source: PROFILE_SOURCE,
      used: 0,
      createdAt: now,
      updatedAt: now,
    };
  }

  private static withSessionLevel(profile: LearnerProfile, sessionLevel: LearnerLevel): LearnerProfile {
    return {
      globalLevel: profile.globalLevel,
      sessionLevel: sessionLevel,
      effectiveLevel: AgentMemoryService.effectiveLevel(profile.globalLevel, sessionLevel),
      confidence: profile.confidence,
      evidence: profile.evidence,
      updatedAt: profile.updatedAt,
    };
  }

  private static countUserMessagesAfter(
    messages: ChatMessageRecord[],
    profileRecord: AgentMemoryRecord | null,
  ): number {
    const since: number = profileRecord !== null ? profileRecord.createdAt : 0;
    let count: number = 0;
    for (const message of messages) {
      if (message.role === 'user' && message.createdAt > since) {
        count += 1;
      }
    }
    return count;
  }

  private static effectiveLevel(globalLevel: LearnerLevel, sessionLevel: LearnerLevel): LearnerLevel {
    if (sessionLevel.length > 0) {
      return sessionLevel;
    }
    return globalLevel;
  }

  private static parseLearnerLevel(value: Object | undefined): LearnerLevel | null {
    if (typeof value !== 'string') {
      return null;
    }
    if (value === 'beginner') { return 'beginner'; }
    if (value === 'advanced') { return 'advanced'; }
    if (value === 'novice') { return 'novice'; }
    return null;
  }

  private static normalizeConfidence(value: Object | undefined): number {
    let num: number = 0;
    if (typeof value === 'number') {
      num = value;
    } else if (typeof value === 'string') {
      const parsed: number = Number(value);
      if (!Number.isNaN(parsed)) {
        num = parsed;
      }
    }
    if (num < 0) { return 0; }
    if (num > 1) { return 1; }
    return num;
  }

  private static extractJsonObject(raw: string): string {
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

  private static levelLabel(level: LearnerLevel): string {
    if (level === 'beginner') { return '小白'; }
    if (level === 'advanced') { return '精通者'; }
    return '初识者';
  }

  private static clip(text: string, limit: number): string {
    if (text.length <= limit) {
      return text;
    }
    return text.substring(0, limit) + '\n...';
  }

  private static newId(prefix: string): string {
    return prefix + '_' + Date.now().toString() + '_' + Math.floor(Math.random() * 1000000).toString();
  }

  private static errorMessage(e: Object): string {
    const message: string | undefined = (e as Error).message;
    if (message !== undefined && message.length > 0) {
      return message;
    }
    return JSON.stringify(e);
  }
}
