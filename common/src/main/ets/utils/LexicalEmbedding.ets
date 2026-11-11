/**
 * LexicalEmbedding.ets — 确定性词面向量（纯函数，无 Kit、无 IO）
 *
 * 路径: common/src/main/ets/utils/LexicalEmbedding.ets
 * 职责: 把文本切成中文二元组 + 拉丁/数字整词 + 数学签名 token，按带符号哈希落进固定维度，
 *       得到 L2 归一化的稀疏词面向量。用于检索的向量通道与相似度度量。
 * 依赖: ./MathSignature（中文数字归一 + 算式签名）。
 *
 * 为什么不用系统分词：分词结果必须「索引期与查询期完全一致」才有意义，
 * 而分词引擎在扩展进程不可用（process-boundary R4）；二元组是确定性的，
 * 任何进程、任何版本都得到同一向量，且对「导数定义 / 导数的定义」这类结构差异天然不敏感。
 * 真正的语义鸿沟（导数 ↔ 瞬时变化率）靠后续接入的稠密模型补，本实现只保证零依赖可用。
 */

import { extractMathSignature, normalizeMathText } from './MathSignature';

export const LEXICAL_EMBEDDING_PROVIDER: string = 'local';
export const LEXICAL_EMBEDDING_MODEL: string = 'lexical-v1';
export const LEXICAL_DIMENSION: number = 512;

const CJK_START: number = 0x4e00;
const CJK_END: number = 0x9fff;
const FNV_OFFSET: number = 0x811c9dc5;
const FNV_PRIME: number = 0x01000193;

function isCjk(code: number): boolean {
  return code >= CJK_START && code <= CJK_END;
}

function isWordChar(code: number): boolean {
  return (code >= 0x30 && code <= 0x39)
    || (code >= 0x61 && code <= 0x7a)
    || (code >= 0x41 && code <= 0x5a);
}

/** FNV-1a 32 位；用于稳定哈希，不追求加密强度。 */
function hashToken(token: string): number {
  let hash: number = FNV_OFFSET;
  for (let i = 0; i < token.length; i += 1) {
    hash = hash ^ token.charCodeAt(i);
    hash = Math.imul(hash, FNV_PRIME) >>> 0;
  }
  return hash >>> 0;
}

function addToken(tokens: string[], token: string): void {
  if (token.length > 0) {
    tokens.push(token);
  }
}

/** 中文段：单字 + 二元组。单字吸收「的/和」这类插入造成的二元组错位，权重在向量构建时压低。 */
function pushCjkRun(tokens: string[], run: string): void {
  if (run.length === 0) {
    return;
  }
  for (let i = 0; i < run.length; i += 1) {
    addToken(tokens, run.charAt(i));
  }
  for (let i = 0; i + 1 < run.length; i += 1) {
    addToken(tokens, run.substring(i, i + 2));
  }
}

/** 单字段最泛（几乎所有中文段落共享），只作召回补充；签名最有判别力，加权。 */
function tokenWeight(token: string): number {
  if (token.startsWith('sig:')) {
    return 2;
  }
  if (token.length === 1 && isCjk(token.charCodeAt(0))) {
    return 0.5;
  }
  return 1;
}

/** 分词口径：中文二元组 + 拉丁/数字整词 + 算式签名。查询与文档必须走同一函数。 */
export function embeddingTokens(text: string): string[] {
  const tokens: string[] = [];
  const normalized: string = normalizeMathText(text);
  let cjkRun: string = '';
  let wordRun: string = '';
  for (let i = 0; i < normalized.length; i += 1) {
    const code: number = normalized.charCodeAt(i);
    if (isCjk(code)) {
      if (wordRun.length > 0) {
        addToken(tokens, wordRun);
        wordRun = '';
      }
      cjkRun += normalized.charAt(i);
      continue;
    }
    if (cjkRun.length > 0) {
      pushCjkRun(tokens, cjkRun);
      cjkRun = '';
    }
    if (isWordChar(code)) {
      wordRun += normalized.charAt(i);
    } else if (wordRun.length > 0) {
      addToken(tokens, wordRun);
      wordRun = '';
    }
  }
  if (cjkRun.length > 0) {
    pushCjkRun(tokens, cjkRun);
  }
  if (wordRun.length > 0) {
    addToken(tokens, wordRun);
  }
  const signature: string = extractMathSignature(text);
  if (signature.length > 0) {
    addToken(tokens, 'sig:' + signature);
  }
  return tokens;
}

/** 词频权重：1 + ln(tf)，长文档不会因为重复词多而压过短文档。 */
function normalizeVector(vector: number[]): number[] {
  let sum: number = 0;
  for (let i = 0; i < vector.length; i += 1) {
    sum += vector[i] * vector[i];
  }
  if (sum <= 0) {
    return vector;
  }
  const norm: number = Math.sqrt(sum);
  for (let i = 0; i < vector.length; i += 1) {
    vector[i] = vector[i] / norm;
  }
  return vector;
}

/** 稀疏词面向量：带符号哈希降低碰撞偏置，L2 归一化后余弦即点积。 */
export function buildLexicalVector(text: string): number[] {
  const vector: number[] = [];
  for (let i = 0; i < LEXICAL_DIMENSION; i += 1) {
    vector.push(0);
  }
  const tokens: string[] = embeddingTokens(text);
  if (tokens.length === 0) {
    return vector;
  }
  const counts: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < tokens.length; i += 1) {
    const token: string = tokens[i];
    counts.set(token, (counts.get(token) ?? 0) + 1);
  }
  const keys: string[] = Array.from(counts.keys());
  for (let i = 0; i < keys.length; i += 1) {
    const token: string = keys[i];
    const count: number = counts.get(token) ?? 0;
    const weight: number = tokenWeight(token) * (1 + Math.log(count));
    const hash: number = hashToken(token);
    const bucket: number = hash % LEXICAL_DIMENSION;
    const sign: number = ((hash >>> 16) & 1) === 0 ? 1 : -1;
    vector[bucket] = vector[bucket] + sign * weight;
  }
  return normalizeVector(vector);
}

/**
 * 语料均值：把它从文档向量里减掉，等于剥掉「几乎所有笔记都有的高频词」分量。
 * 这是 IDF 的廉价近似——不需要存词表，只要一个 512 维向量。
 */
export function meanVector(vectors: number[][]): number[] {
  const centroid: number[] = [];
  if (vectors.length === 0) {
    return centroid;
  }
  const dimension: number = vectors[0].length;
  for (let i = 0; i < dimension; i += 1) {
    centroid.push(0);
  }
  for (let v = 0; v < vectors.length; v += 1) {
    const vector: number[] = vectors[v];
    if (vector.length !== dimension) {
      continue;
    }
    for (let i = 0; i < dimension; i += 1) {
      centroid[i] += vector[i];
    }
  }
  for (let i = 0; i < dimension; i += 1) {
    centroid[i] = centroid[i] / vectors.length;
  }
  return centroid;
}

/** 去均值后重新归一化；维度不一致时原样返回。 */
export function subtractCentroid(vector: number[], centroid: number[]): number[] {
  if (centroid.length === 0 || vector.length !== centroid.length) {
    return vector;
  }
  const centered: number[] = [];
  for (let i = 0; i < vector.length; i += 1) {
    centered.push(vector[i] - centroid[i]);
  }
  return normalizeVector(centered);
}

/** 余弦相似度；维度不一致视为不可比（不同模型向量），返回 0。 */
export function cosineSimilarity(left: number[], right: number[]): number {
  if (left.length === 0 || left.length !== right.length) {
    return 0;
  }
  let dot: number = 0;
  let leftNorm: number = 0;
  let rightNorm: number = 0;
  for (let i = 0; i < left.length; i += 1) {
    dot += left[i] * right[i];
    leftNorm += left[i] * left[i];
    rightNorm += right[i] * right[i];
  }
  if (leftNorm <= 0 || rightNorm <= 0) {
    return 0;
  }
  const score: number = dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm));
  if (score > 1) {
    return 1;
  }
  if (score < -1) {
    return -1;
  }
  return score;
}
