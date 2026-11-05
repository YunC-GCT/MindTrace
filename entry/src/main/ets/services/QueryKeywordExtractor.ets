/**
 * QueryKeywordExtractor.ets — 检索查询的实时分词关键词（entry 侧 Kit 适配）
 *
 * 路径: entry/src/main/ets/services/QueryKeywordExtractor.ets
 * 职责: 调用系统中文分词，抽取名词/动词/数量词等内容词，作为 FTS 查询扩展；
 *       任何失败返回空数组，调用方回退到纯规则拆分。
 * 依赖: @kit.NaturalLanguageKit（懒加载）、common Logger。
 *
 * 约束: 受限 Kit 必须延迟求值——静态 import 会让 A2A 扩展进程也加载它（process-boundary R4）；
 *       扩展进程调用失败时静默降级。
 */
import type { textProcessing } from '@kit.NaturalLanguageKit';
import { Logger } from 'common';

const log: Logger = new Logger('QueryKeywords');
const MAX_KEYWORDS: number = 6;
const CONTENT_TAGS: string[] = [
  'n', 'nr', 'ns', 'nt', 'nz', 'nrf', 'v', 'vn', 'vd', 'a', 'ad', 'an', 'm', 'q', 'eng', 'i', 'j', 'l',
];
const STOP_WORDS: string[] = [
  '什么', '怎么', '如何', '多少', '哪个', '哪些', '是否', '可以', '我们', '你们', '他们',
  '这个', '那个', '一下', '请问', '帮我', '给我', '笔记', '主要内容',
];
let kitNamespace: ESObject | null = null;
let initPromise: Promise<boolean> | null = null;

async function requireNlpKit(): Promise<ESObject> {
  if (kitNamespace === null) {
    kitNamespace = await import('@kit.NaturalLanguageKit') as ESObject;
  }
  return kitNamespace;
}

export class QueryKeywordExtractor {
  static async extract(text: string): Promise<string[]> {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return [];
    }
    try {
      const ready: boolean = await QueryKeywordExtractor.ensureInit();
      if (!ready) {
        return [];
      }
      const ns: ESObject = await requireNlpKit();
      const words: Array<textProcessing.WordSegment> =
        await ns.textProcessing.getWordSegment(trimmed) as Array<textProcessing.WordSegment>;
      const keywords: string[] = [];
      for (let i = 0; i < words.length; i += 1) {
        const value: string = words[i].word.trim();
        if (value.length < 2 || STOP_WORDS.indexOf(value) >= 0) {
          continue;
        }
        if (CONTENT_TAGS.indexOf(words[i].wordTag) < 0) {
          continue;
        }
        if (keywords.indexOf(value) < 0) {
          keywords.push(value);
        }
        if (keywords.length >= MAX_KEYWORDS) {
          break;
        }
      }
      return keywords;
    } catch (e) {
      log.warn('keyword extract failed: ' + (e as Error).message);
      return [];
    }
  }

  private static async ensureInit(): Promise<boolean> {
    if (initPromise === null) {
      initPromise = QueryKeywordExtractor.initEngine();
    }
    return await initPromise;
  }

  private static async initEngine(): Promise<boolean> {
    try {
      const ns: ESObject = await requireNlpKit();
      const ok: boolean = await ns.textProcessing.init() as boolean;
      return ok;
    } catch (e) {
      log.warn('keyword engine init failed: ' + (e as Error).message);
      return false;
    }
  }
}
