/**
 * AppIntentRules.ets — App 内 agent 的意图分类规则（纯函数，无 IO）
 *
 * 路径: agents/src/main/ets/chat/AppIntentRules.ets
 * 职责: 把 App 对话（文字/图片）的意图从「note_generation / chat」两分类扩展为
 *       chat / note_generate / review / note_query / image_explain / image_note / clarify。
 *       规则优先（快、可解释），无法判定时返回 undefined 交给 AppIntentRouter 走 LLM 兜底；
 *       低置信或指代不明时返回 clarify，让 UI 追问而不是猜。
 * 依赖: 无（纯字符串，便于 Node 契约测试）。
 */

export type AppIntentKind =
  | 'chat'
  | 'note_generate'
  | 'review'
  | 'note_query'
  | 'image_explain'
  | 'image_note'
  | 'clarify';

export interface AppIntentDecision {
  kind: AppIntentKind;
  /** rule = 本地规则命中；llm = 模型判定；fallback = LLM 不可用/异常 */
  source: string;
  /** 0..1；规则命中给固定高置信，LLM 返回原始 confidence */
  confidence: number;
  reason: string;
}

export const INTENT_KINDS: AppIntentKind[] = [
  'chat', 'note_generate', 'review', 'note_query', 'image_explain', 'image_note', 'clarify',
];

export const INTENT_LABELS: string[] = [
  'chat（普通问答/讲解）',
  'note_generate（整理成笔记）',
  'review（复习/测验/出题）',
  'note_query（查询我的笔记/历史记录）',
  'image_explain（讲解图片内容）',
  'image_note（把图片整理成笔记）',
  'clarify（意图不明，需要追问）',
];

const DENY_NOTE_PHRASES: string[] = [
  '不要整理', '别整理', '不用整理', '不要存', '别存', '不用记', '不要生成笔记',
  '别生成笔记', '只是问问', '只想问', '不要笔记',
];

const REGENERATE_PHRASES: string[] = [
  '重新生成', '再生成一次', '重做笔记', '重新整理笔记', '再整理一次笔记',
];

const REVIEW_PHRASES: string[] = [
  '复习', '测验', '考考我', '考我', '出题', '抽背', '背一下', '自测', '刷题计划',
];

const NOTE_QUERY_PHRASES: string[] = [
  '我记过', '我之前记', '我以前记', '笔记里', '查笔记', '找笔记', '我的笔记',
  '我保存的', '之前存的', '历史笔记', '笔记记录',
];

const NOTE_GENERATE_PHRASES: string[] = [
  '存笔记', '记笔记', '整理成笔记', '整理为笔记', '创建笔记', '新建笔记', '做笔记', '存为笔记', '存到笔记', '记录到笔记', '笔记入库',
  '存进笔记', '整理一下这', '整理这道', '整理这几', '把这道题', '把这几道', '帮我整理',
  '整理成知识', '保存成笔记', '记下来', '记录一下', '存一下',
];

const IMAGE_NOTE_PHRASES: string[] = [
  '整理', '存', '记下来', '做成笔记', '保存', '入库', '笔记',
];

const IMAGE_EXPLAIN_PHRASES: string[] = [
  '怎么做', '怎么解', '讲解', '什么意思', '为什么', '答案', '求解', '思路', '解释',
];

/** 指代不明/过短、容易猜错的输入（走 clarify 追问）。 */
const AMBIGUOUS_PHRASES: string[] = [
  '帮我看看', '看看这个', '这个怎么弄', '这个呢', '处理一下', '弄一下', '搞一下',
  '整理一下', '帮我弄', '这个帮忙', '看一下这个',
];

const MIN_NOTE_GENERATE_CHARS: number = 6;

export function classifyAppIntentLocal(text: string, hasImage: boolean): AppIntentDecision | undefined {
  const normalized: string = text.trim();
  if (hasImage && (normalized.length === 0 || normalized === '[图片]')) {
    return decision('clarify', 'image-no-text', 0.4, 'image-without-intent-text');
  }
  if (normalized.length === 0) {
    return decision('chat', 'empty', 0.3, 'empty-text');
  }
  if (matches(normalized, DENY_NOTE_PHRASES)) {
    return decision('chat', 'deny-note', 0.9, 'explicit-deny-note');
  }
  if (matches(normalized, REGENERATE_PHRASES)) {
    return decision('note_generate', 'regenerate', 0.9, 'explicit-regenerate');
  }
  if (matches(normalized, REVIEW_PHRASES)) {
    return decision('review', 'review-keyword', 0.85, 'review-phrase');
  }
  if (matches(normalized, NOTE_QUERY_PHRASES)) {
    return decision('note_query', 'note-query-keyword', 0.85, 'note-query-phrase');
  }
  if (hasImage) {
    if (matches(normalized, IMAGE_NOTE_PHRASES)) {
      return decision('image_note', 'image-note-keyword', 0.8, 'image-note-phrase');
    }
    if (matches(normalized, IMAGE_EXPLAIN_PHRASES)) {
      return decision('image_explain', 'image-explain-keyword', 0.8, 'image-explain-phrase');
    }
    if (matches(normalized, AMBIGUOUS_PHRASES)) {
      return decision('clarify', 'image-ambiguous', 0.4, 'image-ambiguous-phrase');
    }
    // 图片 + 有正文但无明显动词：默认讲解（比默认生成笔记安全）
    return decision('image_explain', 'image-default', 0.55, 'image-default-explain');
  }
  if (normalized.length >= MIN_NOTE_GENERATE_CHARS && matches(normalized, NOTE_GENERATE_PHRASES)) {
    return decision('note_generate', 'note-generate-keyword', 0.85, 'note-generate-phrase');
  }
  if (matches(normalized, AMBIGUOUS_PHRASES)) {
    return decision('clarify', 'text-ambiguous', 0.4, 'ambiguous-phrase');
  }
  return undefined;
}

/** LLM 兜底的 system prompt（两阶段路由：规则命中就不调模型）。 */
export function buildAppIntentPrompt(): string {
  return '你是 MindTrace 的意图分类器。用户会发文字或图片+文字，把意图分成下列之一，返回严格 JSON：'
    + '{"intent":"<kind>","confidence":0..1,"reason":"<10字内原因>"}。\n'
    + '可选 kind：\n'
    + '- chat：普通问答、讲解、计算、闲聊\n'
    + '- note_generate：把内容整理成可保存的学习笔记\n'
    + '- review：复习/测验/出题/抽背\n'
    + '- note_query：查询用户自己的笔记/历史记录\n'
    + '- image_explain：讲解图片里的题目（不保存）\n'
    + '- image_note：把图片整理成笔记保存\n'
    + '- clarify：意图不明或指代不清，需要追问\n'
    + '判断原则：用户说「存/记/整理成笔记/保存」才是 note_generate/image_note；'
    + '只是问「怎么做/为什么/讲解」是 chat/image_explain；'
    + '提到「我记过的/笔记里」是 note_query；无法确定时返回 clarify，不要猜。';
}

/** 校验 LLM JSON：intent 合法、confidence 在 0..1。 */
export function validateAppIntentJson(json: Record<string, Object>): string[] {
  const issues: string[] = [];
  const intent: Object | undefined = json['intent'];
  if (typeof intent !== 'string' || !isKnownAppIntent(intent)) {
    issues.push('intent must be one of: ' + INTENT_KINDS.join('/'));
  }
  const confidence: Object | undefined = json['confidence'];
  if (typeof confidence !== 'number' && typeof confidence !== 'string') {
    issues.push('confidence must be a number from 0 to 1');
  } else {
    const value: number = Number(confidence);
    if (Number.isNaN(value) || value < 0 || value > 1) {
      issues.push('confidence must be a number from 0 to 1');
    }
  }
  return issues;
}

/** 解析 LLM JSON → 决策（低置信转 clarify）。 */
export function parseAppIntentJson(parsed: Record<string, Object>): AppIntentDecision {
  const intent: string = typeof parsed['intent'] === 'string' ? (parsed['intent'] as string) : 'chat';
  const rawConfidence: number = Number(parsed['confidence'] ?? 0.5);
  const confidence: number = Number.isNaN(rawConfidence) ? 0.5 : rawConfidence;
  const reason: string = typeof parsed['reason'] === 'string' ? (parsed['reason'] as string) : 'llm';
  const kind: AppIntentKind = isKnownAppIntent(intent) ? (intent as AppIntentKind) : 'chat';
  if (confidence < 0.6) {
    return decision('clarify', 'llm', confidence, 'low-confidence:' + reason);
  }
  return decision(kind, 'llm', confidence, reason);
}

export function isKnownAppIntent(intent: string): boolean {
  for (let i = 0; i < INTENT_KINDS.length; i += 1) {
    if (INTENT_KINDS[i] === intent) {
      return true;
    }
  }
  return false;
}

function matches(text: string, phrases: string[]): boolean {
  for (let i = 0; i < phrases.length; i += 1) {
    if (text.indexOf(phrases[i]) >= 0) {
      return true;
    }
  }
  return false;
}

function decision(kind: AppIntentKind, source: string, confidence: number, reason: string): AppIntentDecision {
  return { kind: kind, source: source, confidence: confidence, reason: reason };
}
