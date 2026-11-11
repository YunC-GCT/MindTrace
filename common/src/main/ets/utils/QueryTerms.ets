/**
 * QueryTerms.ets — RAG 查询归一与关键词拆分（纯函数，无 IO）
 *
 * 路径: common/src/main/ets/utils/QueryTerms.ets
 * 职责: 把用户整句问题归一成可检索的关键词：全角转半角、小写、剥离边界用语与
 *       口语疑问尾巴、按标点切分、去停用词、按长度取前 N 个词。
 * 依赖: ./NoteRetrievalQuery（边界清洗）
 *
 * 数据流: RagQueryPlan / RdbNoteSearchAdapter / RagRetrievalService → planQueryTerms
 *
 * 设计: 确定性规则，不调模型；拆分失败时回退为归一后的整句，保证永远至少一个词。
 */
import { NoteRetrievalQuery } from './NoteRetrievalQuery';

const MAX_TERMS: number = 3;
const QUESTION_TAILS: string[] = [
  '等于几', '等于多少', '等于什么', '是多少', '是几', '怎么算', '怎么做', '怎么求', '怎么解',
];
const STOP_CHARS: string[] = [
  '的', '了', '吗', '呢', '吧', '呀', '啊', '和', '与', '及', '把', '这', '那', '个',
  '是', '有', '请', '帮', '我', '你', '它',
];
// 「的/和/与/及」在中文里常常是结构助词或并列词，直接当分隔符比当停用词更能保留主题。
const INNER_SEPARATORS: string[] = ['的', '和', '与', '及'];

export interface QueryTermPlan {
  /** 原始输入（trim 后）。 */
  raw: string;
  /** 归一 + 清洗后的整句，可作为短语召回的第一选择。 */
  normalized: string;
  /** 1..MAX_TERMS 个关键词，按长度降序。 */
  terms: string[];
}

class QueryTermsHelper {
  static stripQuestionTails(value: string): string {
    let text: string = value;
    let changed: boolean = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < QUESTION_TAILS.length; i += 1) {
        const tail: string = QUESTION_TAILS[i];
        if (text.length > tail.length && text.endsWith(tail)) {
          text = text.substring(0, text.length - tail.length).trim();
          changed = true;
        }
      }
    }
    return text;
  }

  static trimStopChars(value: string): string {
    let start: number = 0;
    let end: number = value.length;
    while (start < end && STOP_CHARS.indexOf(value.charAt(start)) >= 0) {
      start += 1;
    }
    while (end > start && STOP_CHARS.indexOf(value.charAt(end - 1)) >= 0) {
      end -= 1;
    }
    return value.substring(start, end).trim();
  }

  static splitOnSeparators(value: string): string[] {
    const parts: string[] = [];
    let current: string = '';
    for (let i = 0; i < value.length; i += 1) {
      const ch: string = value.charAt(i);
      if (INNER_SEPARATORS.indexOf(ch) >= 0) {
        if (current.length > 0) {
          parts.push(current);
        }
        current = '';
      } else {
        current += ch;
      }
    }
    if (current.length > 0) {
      parts.push(current);
    }
    return parts;
  }

  static addUnique(terms: string[], candidate: string): void {
    if (terms.indexOf(candidate) < 0) {
      terms.push(candidate);
    }
  }
}

/** 全角转半角、英文小写、空白折叠；不删除任何语义字符。 */
export function normalizeQueryText(input: string): string {
  let converted: string = '';
  for (let i = 0; i < input.length; i += 1) {
    const code: number = input.charCodeAt(i);
    if (code >= 0xFF01 && code <= 0xFF5E) {
      converted += String.fromCharCode(code - 0xFEE0);
    } else if (code === 0x3000) {
      converted += ' ';
    } else {
      converted += input.charAt(i);
    }
  }
  return converted.toLowerCase().replace(/\s+/g, ' ').trim();
}

/** 合并基础词与外部关键词（如分词结果），去重并按长度降序截断。 */
export function mergeQueryTerms(base: string[], extra: string[], maxTerms: number = MAX_TERMS): string[] {
  const merged: string[] = [];
  for (let i = 0; i < base.length; i += 1) {
    QueryTermsHelper.addUnique(merged, base[i]);
  }
  for (let i = 0; i < extra.length; i += 1) {
    const term: string = extra[i].trim();
    if (term.length > 0) {
      QueryTermsHelper.addUnique(merged, term);
    }
  }
  merged.sort((left: string, right: string): number => right.length - left.length);
  return merged.slice(0, maxTerms);
}

export function planQueryTerms(query: string): QueryTermPlan {
  const raw: string = query.trim();
  const normalized: string = normalizeQueryText(raw);
  let cleaned: string = NoteRetrievalQuery.normalize(normalized);
  cleaned = QueryTermsHelper.stripQuestionTails(cleaned);
  const clauses: string[] = cleaned.split(/[，,。.！!？?；;：:、\s]+/);
  const candidates: string[] = [];
  for (let i = 0; i < clauses.length; i += 1) {
    const pieces: string[] = QueryTermsHelper.splitOnSeparators(clauses[i]);
    for (let k = 0; k < pieces.length; k += 1) {
      const trimmed: string = QueryTermsHelper.trimStopChars(pieces[k]);
      if (trimmed.length > 0) {
        QueryTermsHelper.addUnique(candidates, trimmed);
      }
    }
  }
  // 有长词时丢掉单字词：单字 LIKE 命中噪声太大，只在全是单字时保留。
  const multiChars: string[] = [];
  for (let i = 0; i < candidates.length; i += 1) {
    if (candidates[i].length > 1) {
      multiChars.push(candidates[i]);
    }
  }
  const terms: string[] = multiChars.length > 0 ? multiChars : candidates;
  if (terms.length === 0 && cleaned.length > 0) {
    terms.push(cleaned);
  }
  terms.sort((left: string, right: string): number => right.length - left.length);
  const plan: QueryTermPlan = {
    raw: raw,
    normalized: cleaned,
    terms: terms.slice(0, MAX_TERMS),
  };
  return plan;
}
