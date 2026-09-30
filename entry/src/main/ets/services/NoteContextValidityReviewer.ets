/**
 * NoteContextValidityReviewer.ets - semantic review for ambiguous note context fragments.
 *
 * Path: entry/src/main/ets/services/NoteContextValidityReviewer.ets
 * Responsibility: Ask the configured model only about fragments that deterministic
 * cleanup could not assign to a topic, while keeping source text and IDs authoritative.
 */
import {
  LlmConfig,
  LlmGuard,
  sourceFingerprint,
} from 'common';
import type {
  LlmGuardJsonResult,
  LlmGuardValidationResult,
  NoteTopicCandidate,
  SourceBundle,
  SourceFragment,
} from 'common';
import { NoteGenerationContextResult } from '../models/AgentMemoryModels';
import { NoteGenerationContextBuilder } from './NoteGenerationContextBuilder';

interface ReviewedFragment {
  sourceId: string;
  valid: boolean;
  topic: string;
  confidence: number;
}

interface TopicGroup {
  id: string;
  displayName: string;
  sourceIds: string[];
  confidence: number;
}

const REVIEW_FRAGMENT_LIMIT: number = 12;
const REVIEW_TEXT_LIMIT: number = 1200;

export class NoteContextValidityReviewer {
  static async review(
    context: NoteGenerationContextResult,
    instruction: string,
  ): Promise<NoteGenerationContextResult> {
    const ambiguous: SourceFragment[] = NoteContextValidityReviewer.ambiguousFragments(context);
    if (ambiguous.length === 0) {
      return context;
    }
    if (!(await NoteContextValidityReviewer.isReviewAvailable())) {
      return NoteContextValidityReviewer.apply(context, []);
    }
    const allowedIds: string[] = ambiguous.map((fragment: SourceFragment): string => fragment.id);
    const sourceLines: string[] = [];
    for (const fragment of ambiguous) {
      sourceLines.push('sourceId=' + fragment.id);
      sourceLines.push(fragment.text.substring(0, REVIEW_TEXT_LIMIT));
      sourceLines.push('---');
    }
    try {
      const raw: LlmGuardJsonResult = await new LlmGuard().callJsonWithRetry([
        {
          role: 'system',
          content: '你只负责复核数学笔记材料。只输出严格 JSON：{"items":[{"sourceId":"原ID","valid":true,"topic":"简短数学主题","confidence":0.0}]}。不得改写材料，不得创造 sourceId。错误提示、寒暄、纯控制指令 valid=false；包含可用于数学笔记的定义、公式、推导、题目或解释 valid=true。topic 必须是单一明确主题。',
        },
        {
          role: 'user',
          content: '用户整理指令：' + instruction + '\n\n待复核片段：\n' + sourceLines.join('\n'),
        },
      ], {
        maxTokens: 1200,
        timeoutMs: 60000,
        responseFormat: { type: 'json_object' },
        label: 'note context validity review',
      }, (json: Record<string, Object>): LlmGuardValidationResult => {
        return NoteContextValidityReviewer.validate(json, allowedIds);
      });
      const reviewed: ReviewedFragment[] = NoteContextValidityReviewer.parse(raw.json, allowedIds);
      return NoteContextValidityReviewer.apply(context, reviewed);
    } catch (error) {
      console.warn('[NoteContextValidityReviewer] semantic review skipped: '
        + NoteContextValidityReviewer.errorMessage(error));
      return NoteContextValidityReviewer.apply(context, []);
    }
  }

  private static ambiguousFragments(context: NoteGenerationContextResult): SourceFragment[] {
    const claimed: string[] = [];
    for (const topic of context.topics) {
      for (const sourceId of topic.sourceIds) {
        if (!claimed.includes(sourceId)) { claimed.push(sourceId); }
      }
    }
    const result: SourceFragment[] = [];
    for (const fragment of context.bundle.fragments) {
      if (result.length >= REVIEW_FRAGMENT_LIMIT) { break; }
      if (!claimed.includes(fragment.id) && fragment.kind !== 'ocr') {
        result.push(fragment);
      }
    }
    return result;
  }

  private static async isReviewAvailable(): Promise<boolean> {
    try {
      return await LlmConfig.getInstance().isConfigured();
    } catch (error) {
      return false;
    }
  }

  private static validate(json: Record<string, Object>, allowedIds: string[]): LlmGuardValidationResult {
    const issues: string[] = [];
    const value: Object | undefined = json['items'];
    if (!Array.isArray(value)) {
      issues.push('items must be an array');
      return { ok: false, issues: issues };
    }
    for (const item of value as Object[]) {
      if (typeof item !== 'object' || item === null) {
        issues.push('item must be object');
        continue;
      }
      const record: Record<string, Object> = item as Record<string, Object>;
      const sourceId: Object | undefined = record['sourceId'];
      const valid: Object | undefined = record['valid'];
      const topic: Object | undefined = record['topic'];
      const confidence: Object | undefined = record['confidence'];
      if (typeof sourceId !== 'string' || !allowedIds.includes(sourceId)) {
        issues.push('sourceId must reference an allowed source');
      }
      if (typeof valid !== 'boolean') { issues.push('valid must be boolean'); }
      if (typeof topic !== 'string') { issues.push('topic must be string'); }
      if (typeof confidence !== 'number' || confidence < 0 || confidence > 1) {
        issues.push('confidence must be between 0 and 1');
      }
    }
    return { ok: issues.length === 0, issues: issues };
  }

  private static parse(json: Record<string, Object>, allowedIds: string[]): ReviewedFragment[] {
    const result: ReviewedFragment[] = [];
    const value: Object | undefined = json['items'];
    if (!Array.isArray(value)) { return result; }
    for (const item of value as Object[]) {
      const record: Record<string, Object> = item as Record<string, Object>;
      const sourceIdValue: Object | undefined = record['sourceId'];
      const validValue: Object | undefined = record['valid'];
      const topicValue: Object | undefined = record['topic'];
      const confidenceValue: Object | undefined = record['confidence'];
      if (typeof sourceIdValue === 'string' && allowedIds.includes(sourceIdValue)
        && typeof validValue === 'boolean' && typeof topicValue === 'string'
        && typeof confidenceValue === 'number') {
        result.push({
          sourceId: sourceIdValue,
          valid: validValue,
          topic: topicValue.trim(),
          confidence: confidenceValue,
        });
      }
    }
    return result;
  }

  private static apply(
    context: NoteGenerationContextResult,
    reviewed: ReviewedFragment[],
  ): NoteGenerationContextResult {
    const rejectedIds: string[] = [];
    const groups: TopicGroup[] = [];
    for (const item of reviewed) {
      if (!item.valid) {
        rejectedIds.push(item.sourceId);
      } else if (item.topic.length > 0 && item.confidence >= 0.55) {
        NoteContextValidityReviewer.addTopicGroup(groups, item);
      }
    }
    const fragments: SourceFragment[] = [];
    for (const fragment of context.bundle.fragments) {
      if (!rejectedIds.includes(fragment.id)) { fragments.push(fragment); }
    }
    const remainingIds: string[] = fragments.map((fragment: SourceFragment): string => fragment.id);
    const topics: NoteTopicCandidate[] = [];
    for (const topic of context.topics) {
      const sourceIds: string[] = topic.sourceIds.filter((id: string): boolean => remainingIds.includes(id));
      if (sourceIds.length > 0) {
        NoteContextValidityReviewer.appendTopic(topics, {
          id: topic.id,
          displayName: topic.displayName,
          sourceIds: sourceIds,
          confidence: topic.confidence,
        });
      }
    }
    for (const group of groups) {
      NoteContextValidityReviewer.appendTopic(topics, {
        id: group.id,
        displayName: group.displayName,
        sourceIds: group.sourceIds,
        confidence: group.confidence,
      });
    }
    const requiresClarification: boolean = context.requiresClarification || topics.length >= 2
      || (context.budgetDeferred && topics.length === 0 && fragments.length > 0);
    const untrimmedBundle: SourceBundle = { fragments: fragments };
    const bundle: SourceBundle = requiresClarification
      ? untrimmedBundle
      : NoteGenerationContextBuilder.trimBundleToBudget(untrimmedBundle, context.contextBudgetTokens);
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + '; kind=' + fragment.kind
        + '; fingerprint=' + sourceFingerprint(fragment.text) + ']');
      lines.push(fragment.text);
      lines.push('');
    }
    const contextText: string = lines.join('\n').trim();
    return {
      bundle: bundle,
      contextText: contextText,
      topics: topics,
      requiresClarification: requiresClarification,
      pendingSourceIds: context.pendingSourceIds.filter((id: string): boolean => !rejectedIds.includes(id)),
      contextBudgetTokens: context.contextBudgetTokens,
      estimatedTokens: context.estimatedTokens,
      budgetDeferred: requiresClarification,
    };
  }

  private static appendTopic(topics: NoteTopicCandidate[], candidate: NoteTopicCandidate): void {
    const candidateName: string = candidate.displayName.toLowerCase();
    for (const topic of topics) {
      const topicName: string = topic.displayName.toLowerCase();
      if (topic.id === candidate.id || topicName === candidateName
        || topicName.indexOf(candidateName) >= 0 || candidateName.indexOf(topicName) >= 0) {
        for (const sourceId of candidate.sourceIds) {
          if (!topic.sourceIds.includes(sourceId)) { topic.sourceIds.push(sourceId); }
        }
        topic.confidence = Math.max(topic.confidence, candidate.confidence);
        return;
      }
    }
    topics.push(candidate);
  }

  private static addTopicGroup(groups: TopicGroup[], item: ReviewedFragment): void {
    const id: string = 'reviewed-' + sourceFingerprint(item.topic.toLowerCase());
    for (const group of groups) {
      if (group.id === id) {
        if (!group.sourceIds.includes(item.sourceId)) { group.sourceIds.push(item.sourceId); }
        group.confidence = Math.max(group.confidence, item.confidence);
        return;
      }
    }
    groups.push({
      id: id,
      displayName: item.topic,
      sourceIds: [item.sourceId],
      confidence: item.confidence,
    });
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) { return error.message; }
    return JSON.stringify(error);
  }
}
