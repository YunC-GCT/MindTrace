/**
 * NoteGenerationContextBuilder.ets - deterministic note-generation context preparation.
 *
 * Path: entry/src/main/ets/services/NoteGenerationContextBuilder.ets
 * Responsibility: Normalize, atomize, deduplicate, isolate topics and apply the
 * model-window budget before any note-generation prompt is constructed.
 */
import { NoteTopicCandidate, SourceBundle, SourceFragment, SourceKind, sourceFingerprint } from 'common';
import {
  AgentMemoryRecord,
  ChatMessageRecord,
  NoteGenerationContextBuildInput,
  NoteGenerationContextCandidate,
  NoteGenerationContextResult,
} from '../models/AgentMemoryModels';

const DEFAULT_CONTEXT_WINDOW_TOKENS: number = 65536;
const OUTPUT_TOKEN_RESERVE: number = 12000;
const SAFETY_TOKEN_RESERVE: number = 2048;
const PROTOCOL_TOKEN_RESERVE: number = 1600;
const APPROXIMATE_DEDUPE_MIN_LENGTH: number = 40;
const JACCARD_DUPLICATE_THRESHOLD: number = 0.88;
const CONTAINMENT_DUPLICATE_THRESHOLD: number = 0.95;

interface TopicDefinition {
  id: string;
  displayName: string;
  terms: string[];
}

interface TopicScore {
  id: string;
  displayName: string;
  sourceIds: string[];
  score: number;
}

interface ContextUnit {
  fragment: SourceFragment;
  priority: number;
  createdAt: number;
  estimatedTokens: number;
}

export class NoteGenerationContextBuilder {
  static build(input: NoteGenerationContextBuildInput): NoteGenerationContextResult {
    const candidates: NoteGenerationContextCandidate[] = NoteGenerationContextBuilder.collectCandidates(input);
    const cleaned: NoteGenerationContextCandidate[] = [];
    for (const candidate of candidates) {
      const text: string = NoteGenerationContextBuilder.cleanCandidateText(candidate.text);
      if (!NoteGenerationContextBuilder.isEffectiveMaterial(text, candidate)) {
        continue;
      }
      cleaned.push({
        id: candidate.id,
        kind: candidate.kind,
        originId: candidate.originId,
        sequence: candidate.sequence,
        role: candidate.role,
        outcome: candidate.outcome,
        text: text,
        createdAt: candidate.createdAt,
        priority: candidate.priority,
      });
    }
    const sourceMerged: NoteGenerationContextCandidate[] = NoteGenerationContextBuilder.mergeCandidateSources(cleaned);
    const atomized: NoteGenerationContextCandidate[] = NoteGenerationContextBuilder.atomizeCandidates(sourceMerged);
    const merged: ContextUnit[] = NoteGenerationContextBuilder.mergeCandidates(atomized);
    const topics: NoteTopicCandidate[] = NoteGenerationContextBuilder.detectTopics(merged);
    const instructionTopics: NoteTopicCandidate[] = NoteGenerationContextBuilder.detectInstructionTopics(input.instruction, topics);
    let selectedUnits: ContextUnit[] = merged;
    let resultTopics: NoteTopicCandidate[] = topics;
    let requiresClarification: boolean = topics.length >= 2 && instructionTopics.length !== 1;
    if (instructionTopics.length === 1) {
      selectedUnits = NoteGenerationContextBuilder.filterUnitsByTopic(merged, instructionTopics[0]);
      resultTopics = [instructionTopics[0]];
      requiresClarification = false;
    }
    const needsSemanticReview: boolean = NoteGenerationContextBuilder.hasUnassignedReviewableUnits(
      selectedUnits,
      resultTopics,
    );
    const budget: number = NoteGenerationContextBuilder.inputBudget(input.contextWindowTokens, input.instruction);
    const budgetDeferred: boolean = requiresClarification || needsSemanticReview;
    const prepared: ContextUnit[] = budgetDeferred
      ? NoteGenerationContextBuilder.sortUnits(selectedUnits)
      : NoteGenerationContextBuilder.trimToBudget(selectedUnits, budget);
    const fragments: SourceFragment[] = [];
    const pendingSourceIds: string[] = [];
    for (let index: number = 0; index < prepared.length; index += 1) {
      const unit: ContextUnit = prepared[index];
      fragments.push({
        id: unit.fragment.id,
        kind: unit.fragment.kind,
        originId: unit.fragment.originId,
        sequence: index,
        fingerprint: sourceFingerprint(unit.fragment.text),
        text: unit.fragment.text,
        provenanceIds: unit.fragment.provenanceIds,
      });
      if (unit.fragment.kind === 'ocr' && !pendingSourceIds.includes(unit.fragment.id)) {
        pendingSourceIds.push(unit.fragment.id);
      }
    }
    const bundle: SourceBundle = { fragments: fragments };
    const contextText: string = NoteGenerationContextBuilder.renderContext(bundle);
    return {
      bundle: bundle,
      contextText: contextText,
      topics: resultTopics,
      requiresClarification: requiresClarification,
      pendingSourceIds: pendingSourceIds,
      contextBudgetTokens: budget,
      estimatedTokens: NoteGenerationContextBuilder.estimateTokens(contextText),
      budgetDeferred: budgetDeferred,
    };
  }

  static trimBundleToBudget(bundle: SourceBundle, tokenBudget: number): SourceBundle {
    if (tokenBudget <= 0) {
      return { fragments: [] };
    }
    const ordered: SourceFragment[] = bundle.fragments.slice(0);
    ordered.sort((left: SourceFragment, right: SourceFragment): number => left.sequence - right.sequence);
    const fragments: SourceFragment[] = [];
    let used: number = 0;
    for (const fragment of ordered) {
      const cost: number = NoteGenerationContextBuilder.estimateTokens(fragment.text);
      if (used + cost <= tokenBudget) {
        fragments.push(fragment);
        used += cost;
        continue;
      }
      const remaining: number = tokenBudget - used;
      if (remaining > 200 && fragments.length === 0) {
        const clippedText: string = NoteGenerationContextBuilder.clipByParagraphs(fragment.text, remaining);
        if (clippedText.trim().length > 0) {
          fragments.push({
            id: fragment.id,
            kind: fragment.kind,
            originId: fragment.originId,
            sequence: fragment.sequence,
            fingerprint: sourceFingerprint(clippedText),
            text: clippedText,
            provenanceIds: fragment.provenanceIds,
          });
        }
      }
    }
    return { fragments: fragments };
  }

  private static collectCandidates(input: NoteGenerationContextBuildInput): NoteGenerationContextCandidate[] {
    const result: NoteGenerationContextCandidate[] = [];
    let sequence: number = 0;
    if (input.inlineMaterial.trim().length > 0) {
      result.push(NoteGenerationContextBuilder.toCandidate(
        'current:' + input.currentRunId,
        'conversation',
        input.currentRunId,
        sequence,
        input.inlineMaterial,
        Date.now(),
        1,
        'user',
        'completed',
      ));
      sequence += 1;
    }
    for (const pending of input.pendingNotes) {
      result.push(NoteGenerationContextBuilder.toCandidate(
        pending.id,
        'ocr',
        pending.source,
        sequence,
        pending.content,
        pending.updatedAt,
        2,
        undefined,
        'completed',
      ));
      sequence += 1;
    }
    for (const message of input.recentMessages) {
      const priority: number = message.role === 'user' ? 3 : message.role === 'assistant' ? 4 : 6;
      result.push(NoteGenerationContextBuilder.toCandidate(
        message.messageKey.length > 0 ? message.messageKey : message.id,
        'conversation',
        message.runId ?? message.messageKey,
        sequence,
        message.content,
        message.createdAt,
        priority,
        message.role,
        message.outcome,
      ));
      sequence += 1;
    }
    if (input.summary !== undefined && input.summary.content.trim().length > 0) {
      const entries: string[] = NoteGenerationContextBuilder.splitSummary(input.summary.content);
      for (let index: number = 0; index < entries.length; index += 1) {
        result.push(NoteGenerationContextBuilder.toCandidate(
          input.summary.id + ':summary:' + index.toString(),
          'summary',
          input.summary.source,
          sequence,
          entries[index],
          input.summary.updatedAt,
          5,
          undefined,
          'completed',
        ));
        sequence += 1;
      }
    }
    if (result.length === 0 && input.currentConversationText.trim().length > 0) {
      result.push(NoteGenerationContextBuilder.toCandidate(
        'conversation:' + input.currentRunId,
        'conversation',
        input.currentRunId,
        sequence,
        input.currentConversationText,
        Date.now(),
        6,
        undefined,
        'completed',
      ));
    }
    return result;
  }

  private static toCandidate(
    id: string,
    kind: 'conversation' | 'ocr' | 'summary',
    originId: string,
    sequence: number,
    text: string,
    createdAt: number,
    priority: number,
    role?: 'system' | 'user' | 'assistant',
    outcome?: string,
  ): NoteGenerationContextCandidate {
    return {
      id: id,
      kind: kind,
      originId: originId,
      sequence: sequence,
      role: role,
      outcome: outcome,
      text: text,
      createdAt: createdAt,
      priority: priority,
    };
  }

  private static splitSummary(text: string): string[] {
    const normalized: string = NoteGenerationContextBuilder.normalizeWhitespace(text);
    const lines: string[] = normalized.split('\n');
    const entries: string[] = [];
    let buffer: string[] = [];
    for (const line of lines) {
      const trimmed: string = line.trim();
      const startsNewEntry: boolean = trimmed.startsWith('- ')
        || trimmed.startsWith('* ')
        || trimmed.startsWith('•')
        || trimmed.startsWith('题目')
        || trimmed.startsWith('公式')
        || trimmed.startsWith('结论');
      if (startsNewEntry && buffer.length > 0) {
        entries.push(buffer.join('\n').trim());
        buffer = [];
      }
      if (trimmed.length > 0) {
        buffer.push(trimmed);
      }
    }
    if (buffer.length > 0) {
      entries.push(buffer.join('\n').trim());
    }
    if (entries.length === 0 && normalized.trim().length > 0) {
      entries.push(normalized.trim());
    }
    return entries;
  }

  private static cleanCandidateText(text: string): string {
    const normalized: string = NoteGenerationContextBuilder.normalizeWhitespace(text);
    const lines: string[] = normalized.split('\n');
    const kept: string[] = [];
    for (const line of lines) {
      let stripped: string = NoteGenerationContextBuilder.stripRolePrefix(line.trim());
      if (NoteGenerationContextBuilder.isErrorMessage(stripped)) {
        stripped = NoteGenerationContextBuilder.recoverMathFromErrorLine(stripped);
      }
      if (NoteGenerationContextBuilder.isMetaNoiseLine(stripped)) {
        continue;
      }
      if (stripped.length > 0) {
        kept.push(stripped);
      }
    }
    return NoteGenerationContextBuilder.stripControlWrapper(kept.join('\n')).trim();
  }

  private static normalizeWhitespace(text: string): string {
    let normalized: string = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    normalized = normalized.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
    return normalized.normalize('NFKC').trim();
  }

  private static stripRolePrefix(line: string): string {
    const prefixes: string[] = ['用户:', '用户：', 'User:', 'AI:', 'AI：', '助手:', '助手：', 'System:', '系统:'];
    for (const prefix of prefixes) {
      if (line.startsWith(prefix)) {
        return line.substring(prefix.length).trim();
      }
    }
    return line;
  }

  private static stripControlWrapper(text: string): string {
    let result: string = text.trim();
    const wrappers: string[] = [
      '请整理成笔记',
      '整理成笔记',
      '生成笔记',
      '做成笔记',
      '帮我整理',
      '整理材料',
      '保存这条笔记',
      '保存笔记',
    ];
    for (const wrapper of wrappers) {
      if (result.startsWith(wrapper)) {
        result = result.substring(wrapper.length).trim();
      }
      if (result.endsWith(wrapper)) {
        result = result.substring(0, result.length - wrapper.length).trim();
      }
    }
    if (result.startsWith(':') || result.startsWith('：')) {
      result = result.substring(1).trim();
    }
    return result;
  }

  private static isEffectiveMaterial(text: string, candidate: NoteGenerationContextCandidate): boolean {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return false;
    }
    if (candidate.outcome !== undefined && candidate.outcome !== 'completed') {
      return false;
    }
    if (candidate.role === 'system') {
      return false;
    }
    if (NoteGenerationContextBuilder.isErrorMessage(trimmed)
      && !NoteGenerationContextBuilder.hasMathSignal(trimmed)) {
      return false;
    }
    if (NoteGenerationContextBuilder.isPureControl(trimmed)) {
      return false;
    }
    if (trimmed.length < 8 && !NoteGenerationContextBuilder.hasMathSignal(trimmed)) {
      return false;
    }
    if (NoteGenerationContextBuilder.hasMathSignal(trimmed)
      || candidate.kind === 'ocr'
      || candidate.kind === 'summary') {
      return true;
    }
    // A user explanation may contain valid notation outside the local keyword
    // list. Preserve it for the bounded semantic reviewer instead of silently
    // dropping possible mathematical evidence.
    return candidate.role === 'user' && trimmed.length >= 8;
  }

  private static isMetaNoiseLine(line: string): boolean {
    const lower: string = line.toLowerCase();
    if (lower.startsWith('以下是') || lower.startsWith('好的') || lower.startsWith('我来')) {
      return !NoteGenerationContextBuilder.hasMathSignal(line);
    }
    if (line.indexOf('根据上文') >= 0 && !NoteGenerationContextBuilder.hasMathSignal(line)) {
      return true;
    }
    return false;
  }

  private static isErrorMessage(text: string): boolean {
    const lower: string = text.toLowerCase();
    const markers: string[] = [
      'no_api_key',
      'api key',
      'network error',
      'timeout',
      'timed out',
      'stream_interrupted',
      '本轮处理失败',
      '网络连接失败',
      'ai 回复异常',
      '草稿生成失败',
      '服务响应超时',
      '处理失败:',
    ];
    for (const marker of markers) {
      if (lower.indexOf(marker) >= 0 || text.indexOf(marker) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static recoverMathFromErrorLine(text: string): string {
    if (!NoteGenerationContextBuilder.hasMathSignal(text)) {
      return '';
    }
    const chineseSeparator: number = text.indexOf('：');
    const asciiSeparator: number = text.indexOf(':');
    let separator: number = chineseSeparator;
    if (separator < 0 || (asciiSeparator >= 0 && asciiSeparator < separator)) {
      separator = asciiSeparator;
    }
    if (separator >= 0 && separator < text.length - 1) {
      const material: string = text.substring(separator + 1).trim();
      if (NoteGenerationContextBuilder.hasMathSignal(material)) {
        return material;
      }
    }
    return text;
  }

  private static isPureControl(text: string): boolean {
    const normalized: string = text.replace(/\s/g, '');
    const controls: string[] = [
      '好的',
      '好',
      '谢谢',
      '确认',
      '取消',
      '保存',
      '重新生成',
      '重试',
      '继续',
      '生成笔记',
      '整理成笔记',
      '帮我整理',
    ];
    for (const control of controls) {
      if (normalized === control) {
        return true;
      }
    }
    return false;
  }

  private static hasMathSignal(text: string): boolean {
    const lower: string = text.toLowerCase();
    const terms: string[] = [
      '矩阵', '向量', '行列式', '特征值', '特征向量', '线性方程组', '线性代数', '秩',
      '导数', '求导', '微分', '偏导', '积分', '极限', '函数', '链式法则', '洛必达',
      '公式', '方程', '定理', '证明', '概率', '数列', '几何', '三角', 'derivative', 'matrix',
      'integral', 'limit',
    ];
    for (const term of terms) {
      if (lower.indexOf(term.toLowerCase()) >= 0) {
        return true;
      }
    }
    return /[=∫∑√∞≈≤≥]|\\frac|\\int|\\sum|\blim\b|[a-zA-Z]\s*\^\s*\d|dy\/dx|d\/dx/.test(text);
  }

  private static mergeCandidateSources(
    candidates: NoteGenerationContextCandidate[],
  ): NoteGenerationContextCandidate[] {
    const result: NoteGenerationContextCandidate[] = [];
    for (const candidate of candidates) {
      let existingIndex: number = -1;
      for (let index: number = 0; index < result.length; index += 1) {
        if (result[index].id === candidate.id) {
          existingIndex = index;
          break;
        }
      }
      if (existingIndex < 0) {
        candidate.provenanceIds = candidate.provenanceIds ?? [candidate.id];
        result.push(candidate);
        continue;
      }
      const existing: NoteGenerationContextCandidate = result[existingIndex];
      const winner: NoteGenerationContextCandidate = NoteGenerationContextBuilder.preferCandidate(existing, candidate);
      const provenanceIds: string[] = [];
      NoteGenerationContextBuilder.appendUnique(provenanceIds, existing.provenanceIds ?? [existing.id]);
      NoteGenerationContextBuilder.appendUnique(provenanceIds, candidate.provenanceIds ?? [candidate.id]);
      winner.provenanceIds = provenanceIds;
      result[existingIndex] = winner;
    }
    return result;
  }

  private static preferCandidate(
    left: NoteGenerationContextCandidate,
    right: NoteGenerationContextCandidate,
  ): NoteGenerationContextCandidate {
    if (left.priority !== right.priority) {
      return left.priority < right.priority ? left : right;
    }
    if (left.createdAt !== right.createdAt) {
      return left.createdAt > right.createdAt ? left : right;
    }
    return left.text.length >= right.text.length ? left : right;
  }

  private static atomizeCandidates(
    candidates: NoteGenerationContextCandidate[],
  ): NoteGenerationContextCandidate[] {
    const result: NoteGenerationContextCandidate[] = [];
    let sequence: number = 0;
    for (const candidate of candidates) {
      const blocks: string[] = NoteGenerationContextBuilder.splitAtomicBlocks(candidate.text);
      if (blocks.length <= 1) {
        candidate.sequence = sequence;
        candidate.provenanceIds = candidate.provenanceIds ?? [candidate.id];
        result.push(candidate);
        sequence += 1;
        continue;
      }
      for (let index: number = 0; index < blocks.length; index += 1) {
        const block: string = NoteGenerationContextBuilder.cleanCandidateText(blocks[index]);
        const heading: boolean = NoteGenerationContextBuilder.isHeading(block);
        if (!heading && !NoteGenerationContextBuilder.isEffectiveMaterial(block, candidate)) {
          continue;
        }
        result.push({
          id: candidate.id + ':part:' + index.toString(),
          kind: candidate.kind,
          originId: candidate.originId,
          provenanceIds: candidate.provenanceIds ?? [candidate.id],
          sequence: sequence,
          role: candidate.role,
          outcome: candidate.outcome,
          text: block,
          createdAt: candidate.createdAt,
          priority: candidate.priority,
        });
        sequence += 1;
      }
    }
    return result;
  }

  private static splitAtomicBlocks(text: string): string[] {
    const formulaParts: string[] = text.split(/(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])/g);
    const blocks: string[] = [];
    for (const formulaPart of formulaParts) {
      const part: string = formulaPart.trim();
      if (part.length === 0) {
        continue;
      }
      if (NoteGenerationContextBuilder.isFormulaBlock(part)) {
        blocks.push(part);
        continue;
      }
      const lines: string[] = part.split('\n');
      let buffer: string[] = [];
      for (const line of lines) {
        const trimmed: string = line.trim();
        if (trimmed.length === 0 || NoteGenerationContextBuilder.isHeading(trimmed)
          || NoteGenerationContextBuilder.isStandaloneFormulaLine(trimmed)) {
          if (buffer.length > 0) {
            blocks.push(buffer.join('\n').trim());
            buffer = [];
          }
          if (trimmed.length > 0) {
            blocks.push(trimmed);
          }
          continue;
        }
        buffer.push(trimmed);
      }
      if (buffer.length > 0) {
        blocks.push(buffer.join('\n').trim());
      }
    }
    return blocks;
  }

  private static isFormulaBlock(text: string): boolean {
    return (text.startsWith('$$') && text.endsWith('$$'))
      || (text.startsWith('\\[') && text.endsWith('\\]'));
  }

  private static isHeading(text: string): boolean {
    return /^#{1,6}\s+\S/.test(text) || /^[一-龥A-Za-z0-9][^\n]{0,30}[:：]$/.test(text);
  }

  private static isStandaloneFormulaLine(text: string): boolean {
    if (text.length > 240) {
      return false;
    }
    const hasFormulaMarker: boolean = text.indexOf('=') >= 0 || text.indexOf('\\frac') >= 0
      || text.indexOf('\\int') >= 0 || text.indexOf('∫') >= 0 || text.indexOf('^') >= 0;
    return hasFormulaMarker && !/[,，。；;]/.test(text);
  }

  private static mergeCandidates(candidates: NoteGenerationContextCandidate[]): ContextUnit[] {
    const units: ContextUnit[] = [];
    for (const candidate of candidates) {
      const normalizedText: string = NoteGenerationContextBuilder.normalizeForCompare(candidate.text);
      const fingerprint: string = sourceFingerprint(normalizedText);
      const fragment: SourceFragment = {
        id: candidate.id,
        kind: candidate.kind as SourceKind,
        originId: candidate.originId,
        sequence: candidate.sequence,
        fingerprint: fingerprint,
        text: candidate.text,
        provenanceIds: candidate.provenanceIds ?? [candidate.id],
      };
      const unit: ContextUnit = {
        fragment: fragment,
        priority: candidate.priority,
        createdAt: candidate.createdAt,
        estimatedTokens: NoteGenerationContextBuilder.estimateTokens(candidate.text),
      };
      const exactIndex: number = NoteGenerationContextBuilder.findExactDuplicate(units, unit);
      if (exactIndex >= 0) {
        units[exactIndex] = NoteGenerationContextBuilder.mergeUnit(units[exactIndex], unit);
        continue;
      }
      const approximateIndex: number = NoteGenerationContextBuilder.findApproximateDuplicate(units, unit);
      if (approximateIndex >= 0) {
        units[approximateIndex] = NoteGenerationContextBuilder.mergeUnit(units[approximateIndex], unit);
        continue;
      }
      units.push(unit);
    }
    return units;
  }

  private static findExactDuplicate(units: ContextUnit[], unit: ContextUnit): number {
    for (let index: number = 0; index < units.length; index += 1) {
      const existing: ContextUnit = units[index];
      if (existing.fragment.id === unit.fragment.id || existing.fragment.fingerprint === unit.fragment.fingerprint) {
        return index;
      }
    }
    return -1;
  }

  private static findApproximateDuplicate(units: ContextUnit[], unit: ContextUnit): number {
    const normalized: string = NoteGenerationContextBuilder.normalizeForCompare(unit.fragment.text);
    if (normalized.length < APPROXIMATE_DEDUPE_MIN_LENGTH) {
      return -1;
    }
    const signature: string = NoteGenerationContextBuilder.formulaSignature(unit.fragment.text);
    for (let index: number = 0; index < units.length; index += 1) {
      const existing: ContextUnit = units[index];
      const existingNormalized: string = NoteGenerationContextBuilder.normalizeForCompare(existing.fragment.text);
      if (existingNormalized.length < APPROXIMATE_DEDUPE_MIN_LENGTH) {
        continue;
      }
      const existingSignature: string = NoteGenerationContextBuilder.formulaSignature(existing.fragment.text);
      if (signature !== existingSignature) {
        continue;
      }
      const score: number = NoteGenerationContextBuilder.jaccard3Gram(normalized, existingNormalized);
      const containment: number = NoteGenerationContextBuilder.containment(normalized, existingNormalized);
      if (score >= JACCARD_DUPLICATE_THRESHOLD || containment >= CONTAINMENT_DUPLICATE_THRESHOLD) {
        return index;
      }
    }
    return -1;
  }

  private static mergeUnit(left: ContextUnit, right: ContextUnit): ContextUnit {
    const winner: ContextUnit = NoteGenerationContextBuilder.preferUnit(left, right);
    const loser: ContextUnit = winner.fragment.id === left.fragment.id ? right : left;
    const provenance: string[] = [];
    NoteGenerationContextBuilder.appendUnique(provenance, winner.fragment.provenanceIds ?? [winner.fragment.id]);
    NoteGenerationContextBuilder.appendUnique(provenance, loser.fragment.provenanceIds ?? [loser.fragment.id]);
    return {
      fragment: {
        id: winner.fragment.id,
        kind: winner.fragment.kind,
        originId: winner.fragment.originId,
        sequence: Math.min(left.fragment.sequence, right.fragment.sequence),
        fingerprint: sourceFingerprint(winner.fragment.text),
        text: winner.fragment.text,
        provenanceIds: provenance,
      },
      priority: Math.min(left.priority, right.priority),
      createdAt: Math.max(left.createdAt, right.createdAt),
      estimatedTokens: NoteGenerationContextBuilder.estimateTokens(winner.fragment.text),
    };
  }

  private static preferUnit(left: ContextUnit, right: ContextUnit): ContextUnit {
    if (left.priority !== right.priority) {
      return left.priority < right.priority ? left : right;
    }
    if (left.createdAt !== right.createdAt) {
      return left.createdAt > right.createdAt ? left : right;
    }
    return left.fragment.text.length >= right.fragment.text.length ? left : right;
  }

  private static appendUnique(target: string[], values: string[]): void {
    for (const value of values) {
      if (!target.includes(value)) {
        target.push(value);
      }
    }
  }

  private static normalizeForCompare(text: string): string {
    return NoteGenerationContextBuilder.normalizeWhitespace(text)
      .replace(/[，。；：、,.!！?？\s]/g, '')
      .toLowerCase();
  }

  private static formulaSignature(text: string): string {
    const lines: string[] = text.split('\n');
    const formulas: string[] = [];
    for (const line of lines) {
      const trimmed: string = line.trim();
      if (trimmed.indexOf('=') >= 0 || trimmed.indexOf('\\frac') >= 0 || trimmed.indexOf('∫') >= 0
        || trimmed.indexOf('\\int') >= 0 || trimmed.indexOf('lim') >= 0 || trimmed.indexOf('^') >= 0) {
        formulas.push(NoteGenerationContextBuilder.normalizeForCompare(trimmed));
      }
    }
    return formulas.join('|');
  }

  private static jaccard3Gram(left: string, right: string): number {
    const leftGrams: string[] = NoteGenerationContextBuilder.char3Grams(left);
    const rightGrams: string[] = NoteGenerationContextBuilder.char3Grams(right);
    if (leftGrams.length === 0 || rightGrams.length === 0) {
      return 0;
    }
    let intersection: number = 0;
    for (const gram of leftGrams) {
      if (rightGrams.includes(gram)) {
        intersection += 1;
      }
    }
    const union: number = leftGrams.length + rightGrams.length - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  private static containment(left: string, right: string): number {
    const shorter: string = left.length <= right.length ? left : right;
    const longer: string = left.length <= right.length ? right : left;
    if (shorter.length === 0) {
      return 0;
    }
    if (longer.indexOf(shorter) >= 0) {
      return 1;
    }
    const shorterGrams: string[] = NoteGenerationContextBuilder.char3Grams(shorter);
    const longerGrams: string[] = NoteGenerationContextBuilder.char3Grams(longer);
    if (shorterGrams.length === 0) {
      return 0;
    }
    let covered: number = 0;
    for (const gram of shorterGrams) {
      if (longerGrams.includes(gram)) {
        covered += 1;
      }
    }
    return covered / shorterGrams.length;
  }

  private static char3Grams(text: string): string[] {
    const grams: string[] = [];
    if (text.length < 3) {
      if (text.length > 0) {
        grams.push(text);
      }
      return grams;
    }
    for (let index: number = 0; index <= text.length - 3; index += 1) {
      const gram: string = text.substring(index, index + 3);
      if (!grams.includes(gram)) {
        grams.push(gram);
      }
    }
    return grams;
  }

  private static detectTopics(units: ContextUnit[]): NoteTopicCandidate[] {
    const definitions: TopicDefinition[] = NoteGenerationContextBuilder.topicDefinitions();
    const scores: TopicScore[] = [];
    for (const definition of definitions) {
      const score: TopicScore = {
        id: definition.id,
        displayName: definition.displayName,
        sourceIds: [],
        score: 0,
      };
      for (const unit of units) {
        const matches: number = NoteGenerationContextBuilder.countTopicTerms(unit.fragment.text, definition.terms);
        if (matches > 0) {
          score.score += matches;
          if (!score.sourceIds.includes(unit.fragment.id)) {
            score.sourceIds.push(unit.fragment.id);
          }
        }
      }
      if (score.score > 0) {
        scores.push(score);
      }
    }
    const topics: NoteTopicCandidate[] = [];
    for (const score of scores) {
      const confidence: number = Math.min(0.95, 0.45 + score.score * 0.12 + score.sourceIds.length * 0.05);
      if (confidence >= 0.55) {
        topics.push({
          id: score.id,
          displayName: score.displayName,
          sourceIds: score.sourceIds,
          confidence: confidence,
        });
      }
    }
    if (topics.length === 0) {
      const formulaSources: string[] = [];
      for (const unit of units) {
        if (NoteGenerationContextBuilder.hasMathSignal(unit.fragment.text)) {
          formulaSources.push(unit.fragment.id);
        }
      }
      if (formulaSources.length > 0) {
        topics.push({
          id: 'general-math',
          displayName: '数学材料',
          sourceIds: formulaSources,
          confidence: 0.55,
        });
      }
    }
    return topics;
  }

  private static detectInstructionTopics(instruction: string, topics: NoteTopicCandidate[]): NoteTopicCandidate[] {
    const matched: NoteTopicCandidate[] = [];
    const definitions: TopicDefinition[] = NoteGenerationContextBuilder.topicDefinitions();
    for (const topic of topics) {
      const definition: TopicDefinition | undefined = definitions.find((item: TopicDefinition): boolean => item.id === topic.id);
      if (definition === undefined) {
        continue;
      }
      if (NoteGenerationContextBuilder.countTopicTerms(instruction, definition.terms) > 0) {
        matched.push(topic);
      }
    }
    return matched;
  }

  private static filterUnitsByTopic(units: ContextUnit[], topic: NoteTopicCandidate): ContextUnit[] {
    const result: ContextUnit[] = [];
    for (const unit of units) {
      if (topic.sourceIds.includes(unit.fragment.id)) {
        result.push(unit);
      }
    }
    return result.length > 0 ? result : units;
  }

  private static hasUnassignedReviewableUnits(
    units: ContextUnit[],
    topics: NoteTopicCandidate[],
  ): boolean {
    const claimedIds: string[] = [];
    for (const topic of topics) {
      NoteGenerationContextBuilder.appendUnique(claimedIds, topic.sourceIds);
    }
    for (const unit of units) {
      if (unit.fragment.kind !== 'ocr' && !claimedIds.includes(unit.fragment.id)) {
        return true;
      }
    }
    return false;
  }

  private static topicDefinitions(): TopicDefinition[] {
    return [
      {
        id: 'linear-algebra',
        displayName: '线性代数',
        terms: ['线性代数', '矩阵', '向量', '行列式', '特征值', '特征向量', '线性方程组', '秩', '基', '维数'],
      },
      {
        id: 'calculus-derivative',
        displayName: '微积分/求导',
        terms: ['求导', '导数', '微分', '偏导', '链式法则', '洛必达', 'derivative', 'dy/dx', 'd/dx'],
      },
      {
        id: 'calculus-integral',
        displayName: '微积分/积分',
        terms: ['积分', '不定积分', '定积分', '换元积分', '分部积分', 'integral', '\\int', '∫'],
      },
      {
        id: 'limit-continuity',
        displayName: '极限与连续',
        terms: ['极限', '连续', 'lim', '无穷小', '无穷大'],
      },
      {
        id: 'probability',
        displayName: '概率论',
        terms: ['概率', '随机变量', '分布', '期望', '方差', '贝叶斯'],
      },
    ];
  }

  private static countTopicTerms(text: string, terms: string[]): number {
    const lower: string = text.toLowerCase();
    let count: number = 0;
    for (const term of terms) {
      if (lower.indexOf(term.toLowerCase()) >= 0) {
        count += 1;
      }
    }
    return count;
  }

  private static inputBudget(contextWindowTokens: number, instruction: string): number {
    const windowTokens: number = contextWindowTokens > 0 ? contextWindowTokens : DEFAULT_CONTEXT_WINDOW_TOKENS;
    const seventyPercent: number = Math.floor(windowTokens * 0.7);
    const bounded: number = windowTokens - OUTPUT_TOKEN_RESERVE - SAFETY_TOKEN_RESERVE;
    const rawBudget: number = Math.min(seventyPercent, bounded);
    const instructionCost: number = NoteGenerationContextBuilder.estimateTokens(instruction) + PROTOCOL_TOKEN_RESERVE;
    const sourceBudget: number = rawBudget - instructionCost;
    return Math.max(0, sourceBudget);
  }

  private static trimToBudget(units: ContextUnit[], budget: number): ContextUnit[] {
    if (budget <= 0) {
      return [];
    }
    const sorted: ContextUnit[] = NoteGenerationContextBuilder.sortUnits(units);
    const result: ContextUnit[] = [];
    let used: number = 0;
    for (const unit of sorted) {
      const cost: number = NoteGenerationContextBuilder.estimateTokens(unit.fragment.text);
      if (used + cost <= budget) {
        result.push(unit);
        used += cost;
        continue;
      }
      const remaining: number = budget - used;
      if (remaining > 200 && result.length === 0) {
        const clippedText: string = NoteGenerationContextBuilder.clipByParagraphs(unit.fragment.text, remaining);
        if (clippedText.trim().length > 0) {
          result.push({
            fragment: {
              id: unit.fragment.id,
              kind: unit.fragment.kind,
              originId: unit.fragment.originId,
              sequence: unit.fragment.sequence,
              fingerprint: sourceFingerprint(clippedText),
              text: clippedText,
              provenanceIds: unit.fragment.provenanceIds,
            },
            priority: unit.priority,
            createdAt: unit.createdAt,
            estimatedTokens: NoteGenerationContextBuilder.estimateTokens(clippedText),
          });
        }
      }
    }
    return result;
  }

  private static sortUnits(units: ContextUnit[]): ContextUnit[] {
    const sorted: ContextUnit[] = units.slice(0);
    sorted.sort((left: ContextUnit, right: ContextUnit): number => {
      if (left.priority !== right.priority) {
        return left.priority - right.priority;
      }
      return right.createdAt - left.createdAt;
    });
    return sorted;
  }

  private static clipByParagraphs(text: string, tokenBudget: number): string {
    const paragraphs: string[] = text.split(/\n{2,}/g);
    const kept: string[] = [];
    let used: number = 0;
    for (const paragraph of paragraphs) {
      const cost: number = NoteGenerationContextBuilder.estimateTokens(paragraph);
      if (used + cost > tokenBudget) {
        continue;
      }
      kept.push(paragraph);
      used += cost;
    }
    if (kept.length > 0) {
      return kept.join('\n\n');
    }
    const maxChars: number = Math.max(1, tokenBudget);
    return text.substring(0, Math.min(text.length, maxChars));
  }

  private static renderContext(bundle: SourceBundle): string {
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + '; kind=' + fragment.kind + '; fingerprint=' + fragment.fingerprint + ']');
      lines.push(fragment.text);
      lines.push('');
    }
    return lines.join('\n').trim();
  }

  private static estimateTokens(text: string): number {
    let tokens: number = 0;
    let asciiRun: number = 0;
    for (let index: number = 0; index < text.length; index += 1) {
      const code: number = text.charCodeAt(index);
      const asciiAlphaNumeric: boolean = (code >= 48 && code <= 57)
        || (code >= 65 && code <= 90)
        || (code >= 97 && code <= 122);
      if (asciiAlphaNumeric) {
        asciiRun += 1;
        continue;
      }
      if (asciiRun > 0) {
        tokens += Math.ceil(asciiRun / 4);
        asciiRun = 0;
      }
      if (code <= 32) {
        continue;
      }
      tokens += 1;
    }
    if (asciiRun > 0) {
      tokens += Math.ceil(asciiRun / 4);
    }
    return tokens;
  }
}
