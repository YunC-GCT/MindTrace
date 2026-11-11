#!/usr/bin/env node
/**
 * scripts/rag-lab/eval.mjs — 离线检索评测台
 *
 * 用途: 不装真机，在 PC 上评测检索策略。使用公开数学检索基准
 *       MathNet-Retrieve（CC-BY-4.0，中文子集）。
 * 用法:
 *   node scripts/rag-lab/fetch-mathnet.mjs          # 先下载数据到 .cache
 *   node scripts/rag-lab/eval.mjs                   # MathNet 中文子集 + 抽样候选池
 *   node scripts/rag-lab/eval.mjs --sample-docs 2000 --json
 * 依赖: 本地 embedding 服务（tools/embedding_service/start.bat）用于稠密变体；
 *       服务不可用时自动只跑词面变体。
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadNoteReviewEtsModule } from '../arkts-lint/tests/note-review-ets-loader.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const DEFAULT_ENDPOINT = 'http://127.0.0.1:8001/v1';
const DEFAULT_MODEL = 'BAAI/bge-m3';
const DEFAULT_RERANK_MODEL = 'BAAI/bge-reranker-base';
const BATCH_SIZE = 16;
const TOP_K = 10;
const RRF_K = 60;
const RERANK_TRIGGER_GAP = 0.05;
const MATHNET_VARIANTS = ['lexical', 'dense-body', 'hybrid-body', 'hybrid-body-re'];
const EMBED_CACHE = new Map();
let EMBED_CACHE_PATH = '';

function initEmbedCache(model) {
  const dir = join(ROOT, '.cache', 'rag-lab', 'embeddings');
  EMBED_CACHE_PATH = join(dir, model.replace(/[^a-zA-Z0-9._-]/g, '_') + '.json');
  try {
    const raw = JSON.parse(readFileSync(EMBED_CACHE_PATH, 'utf8'));
    for (const key of Object.keys(raw)) {
      EMBED_CACHE.set(key, raw[key]);
    }
    process.stdout.write('[rag-lab] embedding cache loaded: ' + EMBED_CACHE.size + ' vectors\n');
  } catch (error) {
    // 首次运行没有缓存，正常。
  }
}

function persistEmbedCache() {
  try {
    const dir = join(ROOT, '.cache', 'rag-lab', 'embeddings');
    mkdirSync(dir, { recursive: true });
    const plain = {};
    for (const [key, value] of EMBED_CACHE.entries()) {
      plain[key] = value;
    }
    writeFileSync(EMBED_CACHE_PATH, JSON.stringify(plain));
  } catch (error) {
    process.stderr.write('[rag-lab] embedding cache write failed: ' + error.message + '\n');
  }
}

function parseArgs(argv) {
  const options = {
    endpoint: DEFAULT_ENDPOINT,
    model: DEFAULT_MODEL,
    rerankModel: DEFAULT_RERANK_MODEL,
    dataset: 'mathnet',
    tier: 'easy',
    sampleDocs: 2000,
    maxQueries: 0,
    variants: [],
    json: false,
    detail: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--endpoint' && i + 1 < argv.length) {
      options.endpoint = argv[i + 1];
      i += 1;
    } else if (arg === '--model' && i + 1 < argv.length) {
      options.model = argv[i + 1];
      i += 1;
    } else if (arg === '--rerank-model' && i + 1 < argv.length) {
      options.rerankModel = argv[i + 1];
      i += 1;
    } else if (arg === '--dataset' && i + 1 < argv.length) {
      options.dataset = argv[i + 1];
      i += 1;
    } else if (arg === '--tier' && i + 1 < argv.length) {
      options.tier = argv[i + 1];
      i += 1;
    } else if (arg === '--sample-docs' && i + 1 < argv.length) {
      options.sampleDocs = Number(argv[i + 1]);
      i += 1;
    } else if (arg === '--max-queries' && i + 1 < argv.length) {
      options.maxQueries = Number(argv[i + 1]);
      i += 1;
    } else if (arg === '--variants' && i + 1 < argv.length) {
      options.variants = argv[i + 1].split(',').map((v) => v.trim()).filter((v) => v.length > 0);
      i += 1;
    } else if (arg === '--json') {
      options.json = true;
    } else if (arg === '--detail') {
      options.detail = true;
    }
  }
  return options;
}

function loadEts(relativePath) {
  return loadNoteReviewEtsModule(relativePath);
}

function readJsonl(path) {
  const text = readFileSync(path, 'utf8');
  const rows = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.length > 0) {
      rows.push(JSON.parse(trimmed));
    }
  }
  return rows;
}

function hasCjk(text) {
  return /[一-鿿]/.test(text);
}

function hashString(text) {
  let hash = 2166136261;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function sampleCorpus(rows, goldIds, limit) {
  if (limit <= 0) {
    return rows;
  }
  const gold = new Set(goldIds);
  const selected = [];
  for (const row of rows) {
    if (gold.has(row._id)) {
      selected.push(row);
    }
  }
  const pool = rows.filter((row) => !gold.has(row._id));
  pool.sort((left, right) => hashString(left._id) - hashString(right._id));
  for (const row of pool) {
    if (selected.length >= limit) {
      break;
    }
    selected.push(row);
  }
  return selected;
}

function loadMathNetData(options) {
  const dir = join(ROOT, '.cache', 'rag-lab', 'mathnet-retrieve', options.tier);
  const queriesPath = join(dir, 'queries.jsonl');
  const qrelsPath = join(dir, 'qrels', 'test.jsonl');
  const corpusPath = join(dir, 'corpus.jsonl');
  if (!existsSync(queriesPath) || !existsSync(qrelsPath) || !existsSync(corpusPath)) {
    throw new Error('缺少 MathNet 数据，请先运行 node scripts/rag-lab/fetch-mathnet.mjs');
  }
  const rawQueries = readJsonl(queriesPath).filter((item) => hasCjk(item.text));
  const qrels = readJsonl(qrelsPath);
  const goldByQuery = new Map();
  for (const row of qrels) {
    goldByQuery.set(row['query-id'], row['corpus-id']);
  }
  const cases = [];
  const goldIds = [];
  for (const item of rawQueries) {
    const gold = goldByQuery.get(item._id);
    if (gold === undefined) {
      continue;
    }
    cases.push({ query: item.text, expectTitle: gold, kind: 'mathnet-' + options.tier });
    goldIds.push(gold);
  }
  const limitedCases = options.maxQueries > 0 ? cases.slice(0, options.maxQueries) : cases;
  const limitedGold = options.maxQueries > 0 ? goldIds.slice(0, options.maxQueries) : goldIds;
  const corpus = readJsonl(corpusPath);
  const selected = sampleCorpus(corpus, limitedGold, options.sampleDocs);
  const notes = selected.map((row) => ({
    id: row._id,
    matchKey: row._id,
    title: '',
    summary: '',
    content: row.text,
  }));
  return {
    notes: notes,
    cases: limitedCases,
    label: 'MathNet-Retrieve/' + options.tier + ' 中文子集（抽 ' + notes.length + ' 条候选）',
  };
}

function loadDataset(options) {
  if (options.dataset !== 'mathnet') {
    throw new Error('只支持 MathNet-Retrieve；自建 100 条夹具已于 2026-11-10 移除');
  }
  return loadMathNetData(options);
}

function stripHeadings(text) {
  return text.split(/\r?\n/).filter((line) => !/^\s*#{1,6}\s/.test(line)).join('\n').trim();
}

function tokenize(text) {
  const lower = text.toLowerCase();
  const tokens = [];
  const ascii = lower.match(/[a-z0-9]+/g) ?? [];
  for (const word of ascii) {
    tokens.push(word);
  }
  const cjkRuns = lower.match(/[一-鿿]+/g) ?? [];
  for (const run of cjkRuns) {
    for (let i = 0; i < run.length; i += 1) {
      tokens.push(run[i]);
      if (i + 1 < run.length) {
        tokens.push(run.substring(i, i + 2));
      }
    }
  }
  return tokens;
}

function countMap(tokens) {
  const counts = new Map();
  for (const token of tokens) {
    counts.set(token, (counts.get(token) ?? 0) + 1);
  }
  return counts;
}

function buildBm25(texts) {
  const docs = texts.map((text) => tokenize(text));
  const tfs = docs.map(countMap);
  const df = new Map();
  for (const map of tfs) {
    for (const token of map.keys()) {
      df.set(token, (df.get(token) ?? 0) + 1);
    }
  }
  const total = docs.reduce((sum, tokens) => sum + tokens.length, 0);
  return { docs, tfs, df, avgdl: docs.length === 0 ? 0 : total / docs.length };
}

function bm25Rank(index, query, limit) {
  const queryTokens = tokenize(query);
  const k1 = 1.5;
  const b = 0.75;
  const scored = [];
  for (let d = 0; d < index.docs.length; d += 1) {
    const tf = index.tfs[d];
    const dl = index.docs[d].length;
    let score = 0;
    for (const token of queryTokens) {
      const freq = tf.get(token) ?? 0;
      if (freq === 0) {
        continue;
      }
      const docFreq = index.df.get(token) ?? 0;
      const idf = Math.log(1 + (index.docs.length - docFreq + 0.5) / (docFreq + 0.5));
      score += idf * (freq * (k1 + 1)) / (freq + k1 * (1 - b + b * dl / (index.avgdl || 1)));
    }
    if (score > 0) {
      scored.push({ index: d, score });
    }
  }
  scored.sort((left, right) => right.score - left.score);
  return scored.slice(0, limit);
}

async function embedTexts(endpoint, model, texts) {
  const vectors = new Array(texts.length);
  const missing = [];
  for (let i = 0; i < texts.length; i += 1) {
    const key = createHash('sha1').update(texts[i]).digest('hex');
    const cached = EMBED_CACHE.get(key);
    if (cached !== undefined) {
      vectors[i] = cached;
    } else {
      missing.push({ index: i, key: key, text: texts[i] });
    }
  }
  if (missing.length > 0) {
    process.stdout.write('[rag-lab] embed cache miss ' + missing.length + '/' + texts.length + '\n');
  }
  for (let offset = 0; offset < missing.length; offset += BATCH_SIZE) {
    const batch = missing.slice(offset, offset + BATCH_SIZE);
    const response = await fetch(endpoint.replace(/\/+$/, '') + '/embeddings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, input: batch.map((item) => item.text) }),
    });
    if (!response.ok) {
      throw new Error('embeddings http ' + response.status + ': ' + (await response.text()).slice(0, 200));
    }
    const payload = await response.json();
    const rows = payload.data ?? [];
    for (let i = 0; i < rows.length && i < batch.length; i += 1) {
      vectors[batch[i].index] = rows[i].embedding;
      EMBED_CACHE.set(batch[i].key, rows[i].embedding);
    }
  }
  persistEmbedCache();
  return vectors;
}

function cosine(left, right) {
  let dot = 0;
  let leftNorm = 0;
  let rightNorm = 0;
  for (let i = 0; i < left.length; i += 1) {
    dot += left[i] * right[i];
    leftNorm += left[i] * left[i];
    rightNorm += right[i] * right[i];
  }
  if (leftNorm === 0 || rightNorm === 0) {
    return 0;
  }
  return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm));
}

function denseRank(vectors, queryVector, limit) {
  const scored = [];
  for (let i = 0; i < vectors.length; i += 1) {
    scored.push({ index: i, score: cosine(vectors[i], queryVector) });
  }
  scored.sort((left, right) => right.score - left.score);
  return scored.slice(0, limit);
}

async function rerank(endpoint, model, query, documents) {
  const response = await fetch(endpoint.replace(/\/+$/, '') + '/rerank', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, query, documents }),
  });
  if (!response.ok) {
    throw new Error('rerank http ' + response.status + ': ' + (await response.text()).slice(0, 200));
  }
  const payload = await response.json();
  return payload.results ?? [];
}

let fusionApi = null;

function fuseRrf(channels, limit) {
  if (fusionApi === null) {
    fusionApi = loadEts('common/src/main/ets/utils/RrfFusion.ets');
  }
  const fused = fusionApi.fuseRrfScored(channels, limit, RRF_K);
  return fused.map((item) => item.id);
}

function rankOf(ids, notes, expectedKey) {
  for (let i = 0; i < ids.length; i += 1) {
    const note = notes[Number(ids[i])];
    if (note !== undefined && note.matchKey === expectedKey) {
      return i;
    }
  }
  return -1;
}

function evaluate(rankedIds, notes, cases) {
  const stats = { hit1: 0, hit5: 0, miss: 0, total: 0, mrr: 0, ndcg10: 0, byKind: {}, details: [] };
  for (const item of cases) {
    if (item.expectTitle === '') {
      continue;
    }
    const rank = rankOf(rankedIds.get(item.query) ?? [], notes, item.expectTitle);
    const kind = item.kind ?? 'spot';
    const group = stats.byKind[kind] ?? { hit1: 0, hit5: 0, miss: 0, total: 0 };
    stats.total += 1;
    group.total += 1;
    if (rank === 0) {
      stats.hit1 += 1;
      group.hit1 += 1;
    }
    if (rank >= 0 && rank < 5) {
      stats.hit5 += 1;
      group.hit5 += 1;
    } else {
      stats.miss += 1;
      group.miss += 1;
    }
    if (rank >= 0) {
      stats.mrr += 1 / (rank + 1);
      if (rank < 10) {
        stats.ndcg10 += 1 / Math.log2(rank + 2);
      }
    }
    stats.byKind[kind] = group;
    stats.details.push({ query: item.query, expectTitle: item.expectTitle, kind, rank });
  }
  if (stats.total > 0) {
    stats.mrr = stats.mrr / stats.total;
    stats.ndcg10 = stats.ndcg10 / stats.total;
  }
  return stats;
}

function formatStats(name, stats, elapsedMs) {
  const parts = Object.keys(stats.byKind).map((kind) => {
    const group = stats.byKind[kind];
    return kind + ' h1=' + group.hit1 + '/' + group.total + ' h5=' + group.hit5;
  });
  return name.padEnd(16) + ' hit1=' + stats.hit1 + '/' + stats.total
    + ' hit5=' + stats.hit5 + '/' + stats.total + ' miss=' + stats.miss
    + ' mrr=' + stats.mrr.toFixed(3) + ' ndcg10=' + stats.ndcg10.toFixed(3)
    + ' | ' + parts.join(' | ') + ' | ' + elapsedMs + 'ms';
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  initEmbedCache(options.model);
  const data = loadDataset(options);
  const notes = data.notes;
  const allCases = data.cases;
  const variants = options.variants.length > 0
    ? options.variants
    : MATHNET_VARIANTS;
  const denseTexts = {
    'dense-body': notes.map((note) => (note.title.length > 0 ? note.title + '\n' : '') + stripHeadings(note.content)),
    'dense-title2': notes.map((note) => note.title.length > 0
      ? note.title + '\n' + note.title + '\n' + stripHeadings(note.content)
      : stripHeadings(note.content)),
    'dense-summary': notes.map((note) => (note.title.length > 0 ? note.title + '\n' : '') + note.summary),
  };

  let denseAvailable = true;
  let health = '';
  try {
    const response = await fetch(options.endpoint.replace(/\/+$/, '') + '/health');
    health = (await response.json()).model ?? '';
  } catch (error) {
    denseAvailable = false;
    health = 'unavailable: ' + error.message;
  }

  const lexicalIndex = buildBm25(notes.map((note) =>
    (note.title.length > 0 ? note.title + '\n' + note.title + '\n' : '') + stripHeadings(note.content)));
  const lexicalRanked = new Map();
  for (const item of allCases) {
    lexicalRanked.set(item.query, bm25Rank(lexicalIndex, item.query, TOP_K).map((row) => String(row.index)));
  }

  const denseVectors = {};
  const queryVectors = new Map();
  const needsDense = variants.some((name) => name.startsWith('dense-') || name.startsWith('hybrid-'));
  if (denseAvailable && needsDense) {
    const neededDense = new Set();
    for (const name of variants) {
      if (name.startsWith('dense-')) {
        neededDense.add(name);
      }
      const hybrid = name.match(/^hybrid-(body|title2)/);
      if (hybrid !== null) {
        neededDense.add('dense-' + hybrid[1]);
      }
    }
    for (const variant of neededDense) {
      process.stdout.write('[rag-lab] embedding ' + variant + ' documents...\n');
      denseVectors[variant] = await embedTexts(options.endpoint, options.model, denseTexts[variant]);
    }
    const queries = [...new Set(allCases.map((item) => item.query))];
    process.stdout.write('[rag-lab] embedding ' + queries.length + ' queries...\n');
    const vectors = await embedTexts(options.endpoint, options.model, queries);
    for (let i = 0; i < queries.length; i += 1) {
      queryVectors.set(queries[i], vectors[i]);
    }
  }

  const runVariant = async (name) => {
    const startedAt = Date.now();
    const rankedIds = new Map();
    if (name === 'lexical') {
      for (const item of allCases) {
        rankedIds.set(item.query, lexicalRanked.get(item.query) ?? []);
      }
    } else if (name.startsWith('dense-')) {
      if (!denseAvailable) {
        return null;
      }
      const vectors = denseVectors[name];
      if (vectors === undefined) {
        return null;
      }
      for (const item of allCases) {
        rankedIds.set(item.query,
          denseRank(vectors, queryVectors.get(item.query), TOP_K).map((row) => String(row.index)));
      }
    } else if (name.startsWith('hybrid-')) {
      if (!denseAvailable) {
        return null;
      }
      const match = name.match(/^hybrid-(body|title2)(-re)?$/);
      if (match === null) {
        return null;
      }
      const vectors = denseVectors['dense-' + match[1]];
      const withRerank = match[2] !== undefined;
      for (const item of allCases) {
        const dense = denseRank(vectors, queryVectors.get(item.query), TOP_K);
        let denseOrder = dense.map((row) => String(row.index));
        if (withRerank && dense.length >= 2 && dense[0].score - dense[1].score < RERANK_TRIGGER_GAP) {
          const candidates = denseOrder.slice(0, Math.min(12, denseOrder.length));
          const documents = candidates.map((id) => {
            const note = notes[Number(id)];
            return (note.title.length > 0 ? note.title + '\n' : '') + (note.summary.length > 0 ? note.summary : stripHeadings(note.content));
          });
          try {
            const reranked = await rerank(options.endpoint, options.rerankModel, item.query, documents);
            denseOrder = reranked.map((row) => candidates[row.index]);
          } catch (error) {
            // 重排失败保持余弦顺序，与服务端降级策略一致。
          }
        }
        const fused = fuseRrf([
          { weight: 1, ids: lexicalRanked.get(item.query) ?? [] },
          { weight: 1, ids: denseOrder },
        ], TOP_K);
        rankedIds.set(item.query, fused);
      }
    } else {
      return null;
    }
    const stats = evaluate(rankedIds, notes, allCases);
    return { name, stats, elapsedMs: Date.now() - startedAt };
  };

  const results = [];
  for (const name of variants) {
    const result = await runVariant(name);
    if (result !== null) {
      results.push(result);
    }
  }

  if (options.json) {
    process.stdout.write(JSON.stringify({
      endpoint: options.endpoint,
      model: options.model,
      health,
      dataset: data.label,
      notes: notes.length,
      cases: allCases.length,
      results,
    }, null, 2) + '\n');
    return;
  }

  process.stdout.write('[rag-lab] dataset=' + data.label + ' endpoint=' + options.endpoint
    + ' health=' + health + ' notes=' + notes.length + ' cases=' + allCases.length + '\n');
  if (!denseAvailable) {
    process.stdout.write('WARN: 稠密服务不可用，只跑词面变体。\n');
  }
  for (const result of results) {
    process.stdout.write(formatStats(result.name, result.stats, result.elapsedMs) + '\n');
  }
  if (options.detail) {
    for (const result of results) {
      process.stdout.write('\n== ' + result.name + ' ==\n');
      for (const row of result.stats.details.slice(0, 20)) {
        process.stdout.write('  rank=' + row.rank + ' [' + row.kind + '] ' + row.query.slice(0, 40) + ' -> ' + row.expectTitle + '\n');
      }
    }
  }
}

main().catch((error) => {
  process.stderr.write('[rag-lab] ' + error.message + '\n');
  process.exit(1);
});
