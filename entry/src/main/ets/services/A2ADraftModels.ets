/**
 * A2ADraftModels.ets — A2A 草稿确认的模式与文案
 *
 * 路径: entry/src/main/ets/services/A2ADraftModels.ets
 * 职责: 定义待确认草稿、确认/取消命令解析、草稿预览文案。
 * 依赖: common 的 NoteDraftReadyEvent 类型（仅类型）。
 */

import type { NoteDraftReadyEvent } from 'common';

/** 待确认草稿：按 conversationKey 落盘，跨轮次确认。 */
export interface A2APendingDraft {
  conversationKey: string;
  createdAt: number;
  event: NoteDraftReadyEvent;
  /** 原始资料，用于「详细一点 / 简洁一点 / 重新生成」 */
  sourceText?: string;
  /** 属于多题计划时，确认后要回写 plan.done */
  planTaskId?: string;
  planItemIndex?: number;
}

export type A2ADraftCommand = 'confirm' | 'cancel' | 'none';
export type A2ADraftRefine = 'more' | 'less' | 'regenerate' | 'none';

const CONFIRM_WORDS: string[] = ['确认', '保存', '存吧', '入库', '确定', '可以', '好的', '好'];
const CANCEL_WORDS: string[] = ['取消', '不要了', '算了', '放弃', '不存'];
const CONFIRM_SUFFIXES: string[] = ['', '吧', '。', '！', '!', '啦', '一下', '保存'];
const CANCEL_SUFFIXES: string[] = ['', '吧', '。', '！', '!', '啦', '掉'];

/** 只认短命令：避免把「保存到哪里」这类问题误判成确认。 */
export function parseA2ADraftCommand(text: string): A2ADraftCommand {
  const value: string = text.trim();
  if (value.length === 0 || value.length > 10) {
    return 'none';
  }
  for (let i = 0; i < CONFIRM_WORDS.length; i += 1) {
    const word: string = CONFIRM_WORDS[i];
    for (let j = 0; j < CONFIRM_SUFFIXES.length; j += 1) {
      if (value === word + CONFIRM_SUFFIXES[j]) {
        return 'confirm';
      }
    }
  }
  for (let i = 0; i < CANCEL_WORDS.length; i += 1) {
    const word: string = CANCEL_WORDS[i];
    for (let j = 0; j < CANCEL_SUFFIXES.length; j += 1) {
      if (value === word + CANCEL_SUFFIXES[j]) {
        return 'cancel';
      }
    }
  }
  return 'none';
}

/** 草稿二次操作：详细 / 简洁 / 重新生成；只认短命令，避免误判普通提问。 */
export function parseA2ADraftRefine(text: string): A2ADraftRefine {
  const value: string = text.trim();
  if (value.length === 0 || value.length > 12) {
    return 'none';
  }
  if (value.indexOf('重新生成') >= 0 || value.indexOf('再生成') >= 0 || value === '重来') {
    return 'regenerate';
  }
  if (value.indexOf('详细') >= 0 || value.indexOf('展开') >= 0) {
    return 'more';
  }
  if (value.indexOf('简洁') >= 0 || value.indexOf('简单') >= 0 || value.indexOf('短一点') >= 0) {
    return 'less';
  }
  return 'none';
}

/** 草稿回复：先像聊天一样给出关键内容，最后再问要不要整理成笔记保存。 */
export function formatA2ADraftReply(event: NoteDraftReadyEvent): string {
  const candidate = event.candidate;
  const title: string = candidate.title.trim().length > 0 ? candidate.title.trim() : '未命名笔记';
  const meta: string[] = [];
  if (candidate.subject.trim().length > 0) {
    meta.push(candidate.subject.trim());
  }
  if (candidate.category.trim().length > 0) {
    meta.push(candidate.category.trim());
  }
  const excerpts: string[] = sectionExcerpts(candidate.content, 4, 140);
  let text: string = '「' + title + '」';
  if (meta.length > 0) {
    text += '（' + meta.join(' · ') + '）';
  }
  if (excerpts.length > 0) {
    text += '\n\n';
    for (let i = 0; i < excerpts.length; i += 1) {
      text += (i === 0 ? '· ' : '\n· ') + excerpts[i];
    }
  } else {
    const summary: string = plainPreview(candidate.summary, 120);
    if (summary.length > 0) {
      text += '\n\n' + summary;
    }
  }
  text += '\n\n要我把这些内容整理成笔记保存吗？回复「确认」保存，或「取消」不用。';
  return text;
}

/** 把回复切成适合 artifactUpdate 的短块；每块尽量只放一句，客户端对多句块只渲染第一句。 */
export function splitReplyText(text: string, maxChunk: number = 40, maxChunks: number = 12): string[] {
  const chunks: string[] = [];
  let buffer: string = '';
  for (let i = 0; i < text.length; i += 1) {
    const ch: string = text.charAt(i);
    buffer += ch;
    const boundary: boolean = ch === '\n' || ch === '。' || ch === '！' || ch === '？' || ch === '；';
    if ((boundary && buffer.length >= 12) || buffer.length >= maxChunk) {
      chunks.push(buffer);
      buffer = '';
      if (chunks.length === maxChunks - 1) {
        const rest: string = text.substring(i + 1);
        if (rest.length > 0) {
          buffer = rest;
        }
        break;
      }
    }
  }
  if (buffer.length > 0) {
    chunks.push(buffer);
  }
  if (chunks.length === 0) {
    chunks.push(text);
  }
  return chunks;
}

/** 小艺不渲染 LaTeX：预览只保留纯文本。 */
export function plainPreview(text: string, limit: number): string {
  const flattened: string = text
    .replace(/\$\$?/g, '')
    .replace(/\\[a-zA-Z]+/g, '')
    .replace(/\\+/g, '')
    .replace(/[{}]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (flattened.length <= limit) {
    return flattened;
  }
  return flattened.substring(0, limit) + '…';
}

/** 从 Markdown 正文里抽「## 标题」作为章节列表，最多 6 个。 */
export function sectionLabels(content: string): string[] {
  const labels: string[] = [];
  const lines: string[] = content.split(/\r?\n/);
  for (let i = 0; i < lines.length && labels.length < 6; i += 1) {
    const match: RegExpMatchArray | null = lines[i].trim().match(/^#{2,3}\s+(.+)$/);
    if (match !== null) {
      const label: string = match[1].trim();
      if (label.length > 0 && label !== '原文') {
        labels.push(label);
      }
    }
  }
  return labels;
}

/** 前 N 个章节的「标签：正文摘要」，用于小艺里的内容介绍。 */
export function sectionExcerpts(content: string, maxSections: number, limit: number): string[] {
  const excerpts: string[] = [];
  const lines: string[] = content.split(/\r?\n/);
  let label: string = '';
  let body: string[] = [];
  const flush = (): void => {
    if (label.length === 0 || excerpts.length >= maxSections) {
      return;
    }
    if (label === '原文') {
      return;
    }
    const text: string = plainPreview(body.join(' '), limit);
    if (text.length > 0) {
      excerpts.push(isGenericLabel(label) ? text : friendlyLabel(label) + '：' + text);
    }
  };
  for (let i = 0; i < lines.length; i += 1) {
    const match: RegExpMatchArray | null = lines[i].trim().match(/^#{2,3}\s+(.+)$/);
    if (match !== null) {
      flush();
      if (excerpts.length >= maxSections) {
        return excerpts;
      }
      label = match[1].trim();
      body = [];
      continue;
    }
    if (label.length > 0) {
      body.push(lines[i]);
    }
  }
  flush();
  return excerpts;
}

/** light 路由的通用章节名换成「要点」，预览更自然。 */
function friendlyLabel(label: string): string {
  if (label === '核心内容') {
    return '要点';
  }
  const match: RegExpMatchArray | null = label.match(/^补充内容(\d+)$/);
  if (match !== null) {
    return '要点' + match[1];
  }
  return label;
}

function isGenericLabel(label: string): boolean {
  return label === '核心内容' || /^补充内容\d+$/.test(label);
}
