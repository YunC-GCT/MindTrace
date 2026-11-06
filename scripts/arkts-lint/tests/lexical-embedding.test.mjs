// 路径: scripts/arkts-lint/tests/lexical-embedding.test.mjs
// 职责: L2 检索向量化的契约——确定性词面向量、RRF 融合、向量通道接线。
// Why: 向量必须「查询期与索引期同口径」，否则余弦没有意义；分路权重决定多路命中的排序。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const embedding = loadNoteReviewEtsModule('common/src/main/ets/utils/LexicalEmbedding.ets');
const rrf = loadNoteReviewEtsModule('common/src/main/ets/utils/RrfFusion.ets');
const models = loadNoteReviewEtsModule('common/src/main/ets/utils/EmbeddingModels.ets');

const build = embedding.buildLexicalVector;
const cosine = embedding.cosineSimilarity;

test('模型标识：云端向量带来源前缀，空配置视为未启用', () => {
  assert.equal(models.cloudEmbeddingModelId('text-embedding-v4'), 'cloud:text-embedding-v4');
  assert.equal(models.cloudEmbeddingModelId(' cloud:text-embedding-v4 '), 'cloud:text-embedding-v4');
  assert.equal(models.cloudEmbeddingModelId('   '), '');
  assert.equal(models.isCloudEmbeddingModel('cloud:text-embedding-v4'), true);
  assert.equal(models.isCloudEmbeddingModel('lexical-v1'), false);
});

test('BGE 查询指令：中文检索模型加前缀，m3 与其它模型不加', () => {
  assert.equal(models.embeddingQueryPrefix('bge-large-zh-v1.5'), models.BGE_ZH_QUERY_PREFIX);
  assert.equal(models.embeddingQueryPrefix('BAAI/bge-large-zh-v1.5'), models.BGE_ZH_QUERY_PREFIX);
  assert.equal(models.embeddingQueryPrefix('bge-m3'), '');
  assert.equal(models.embeddingQueryPrefix('text-embedding-v4'), '');
  const port = read('common/src/main/ets/ports/EmbeddingPort.ets');
  assert.match(port, /embedQuery\(text: string\): Promise<EmbeddingVector>/);
  const cloud = read('entry/src/main/ets/services/CloudEmbeddingPort.ets');
  assert.match(cloud, /const prefix: string = embeddingQueryPrefix\(this\.modelName\)/);
  assert.match(cloud, /await this\.embed\(\[prefix \+ text\]\)/);
});

test('重排：头部候选交给交叉编码器，失败保持余弦顺序', () => {
  const client = read('entry/src/main/ets/services/RerankClient.ets');
  assert.match(client, /return base \+ '\/rerank'/);
  assert.match(client, /const body: RerankBody = \{ query: query, documents: documents \}/);
  assert.match(client, /RerankClient\.cooldownUntil = Date\.now\(\) \+ COOLDOWN_MS/);
  assert.match(client, /MAX_DOC_CHARS: number = 240/);
  const index = read('entry/src/main/ets/services/NoteVectorIndex.ets');
  assert.match(index, /RERANK_CANDIDATES: number = 12/);
  assert.match(index, /const ordered: VectorHit\[\] = await NoteVectorIndex\.rerank\(query, hits\)/);
  assert.match(index, /if \(scores\.length !== count\) \{\s*return hits;/);
  // 重排文档用「标题 + 摘要」：正文模板字既拖慢编码又没有区分度
  assert.match(index, /k\.summary AS summary/);
  assert.match(index, /title \+ '：' \+ summary/);
});

test('查询改写：只在向量头部模糊时调用 LLM，失败不影响检索', () => {
  const svc = read('entry/src/main/ets/services/RagRetrievalService.ets');
  assert.match(svc, /isAmbiguousHead\(vectorHits\)/);
  assert.match(svc, /QueryRewriter\.rewrite\(trimmed\)/);
  assert.match(svc, /CHANNEL_WEIGHT_REWRITE: number = 3/);
  assert.match(svc, /AMBIGUOUS_HEAD_GAP: number = 0\.03/);
  const rewriter = read('entry/src/main/ets/services/QueryRewriter.ets');
  assert.match(rewriter, /REWRITE_TIMEOUT_MS: number = 1800/);
  assert.match(rewriter, /COOLDOWN_MS: number = 60000/);
  assert.match(rewriter, /只输出关键词/);
});

test('向量：同文本余弦为 1，维度固定', () => {
  const vector = build('导数定义与几何意义');
  assert.equal(vector.length, embedding.LEXICAL_DIMENSION);
  assert.ok(Math.abs(cosine(vector, build('导数定义与几何意义')) - 1) < 1e-9);
});

test('向量：相近文本高于无关文本', () => {
  const base = build('导数定义与几何意义');
  const related = build('导数的定义和几何意义');
  const unrelated = build('矩阵的秩与初等变换');
  const relatedScore = cosine(base, related);
  const unrelatedScore = cosine(base, unrelated);
  assert.ok(relatedScore > 0.6, '结构助词差异不应拉低相似度: ' + relatedScore);
  assert.ok(unrelatedScore < 0.2, '无关主题不应有高分: ' + unrelatedScore);
  assert.ok(relatedScore - unrelatedScore > 0.5);
});

test('向量：中文数字与阿拉伯数字归一后同一道题', () => {
  const cn = build('计算八十加八十并写出运算步骤');
  const arabic = build('计算 80 加 80 并写出运算步骤');
  assert.ok(cosine(cn, arabic) > 0.99);
});

test('向量：算式签名让不同措辞的同一道题共享特征', () => {
  const tokens = Array.from(embedding.embeddingTokens('两个 21 的和是多少'));
  assert.ok(tokens.includes('sig:add(21,21)'), '文字表述应产出与算式一致的签名');
  const expressionTokens = Array.from(embedding.embeddingTokens('计算 21 加 21 并写出运算步骤'));
  assert.ok(expressionTokens.includes('sig:add(21,21)'));
  // 不同数字的模板句词面天然接近——数字差异由确定性签名规则判，不靠余弦。
  const differentTokens = Array.from(embedding.embeddingTokens('两个 99 的和是多少'));
  assert.ok(differentTokens.includes('sig:add(99,99)'));
  assert.ok(!differentTokens.includes('sig:add(21,21)'));
});

test('向量：空文本得到零向量且不产生 NaN', () => {
  const empty = build('');
  assert.equal(empty.length, embedding.LEXICAL_DIMENSION);
  assert.ok(empty.every((value) => value === 0));
  assert.equal(cosine(empty, build('导数')), 0);
});

test('去均值：剥离语料公共分量后重新归一化', () => {
  const centroid = embedding.meanVector([[1, 0], [0, 1]]);
  assert.deepEqual(Array.from(centroid), [0.5, 0.5]);
  const centered = embedding.subtractCentroid([1, 0], centroid);
  assert.ok(Math.abs(centered[0] - Math.SQRT1_2) < 1e-9);
  assert.ok(Math.abs(centered[1] + Math.SQRT1_2) < 1e-9);
  // 维度不一致时原样返回，不抛异常
  assert.deepEqual(Array.from(embedding.subtractCentroid([1, 2], [])), [1, 2]);
});

test('RRF：多路命中优先于单路，权重表达可信度', () => {
  const fused = rrf.fuseRrf([
    { weight: 3, ids: ['a', 'b'] },
    { weight: 2, ids: ['b', 'c'] },
  ], 3);
  // a=3/61, b=3/62+2/61, c=2/62 → b 最高，a 次之
  assert.deepEqual(Array.from(fused), ['b', 'a', 'c']);
});

test('RRF：同路重复 id 只计一次，limit 截断', () => {
  const fused = rrf.fuseRrf([
    { weight: 1, ids: ['a', 'a', 'b'] },
    { weight: 1, ids: ['a'] },
  ], 1);
  assert.deepEqual(Array.from(fused), ['a']);
});

test('RRF：空输入与非法 limit 返回空数组', () => {
  assert.deepEqual(Array.from(rrf.fuseRrf([], 3)), []);
  assert.deepEqual(Array.from(rrf.fuseRrf([{ weight: 1, ids: ['a'] }], 0)), []);
});

test('端口：EmbeddingPort 不含 Kit，稀疏实现标记模型版本', () => {
  const port = read('common/src/main/ets/ports/EmbeddingPort.ets');
  assert.match(port, /export interface EmbeddingPort/);
  assert.match(port, /embed\(texts: string\[\]\): Promise<EmbeddingVector\[\]>/);
  assert.doesNotMatch(port, /@kit\./, '端口必须能在任意进程求值');
  const lexical = read('entry/src/main/ets/services/LexicalEmbeddingPort.ets');
  assert.match(lexical, /implements EmbeddingPort/);
  assert.match(lexical, /LEXICAL_EMBEDDING_MODEL/);
  assert.doesNotMatch(lexical, /@kit\./);
});

test('向量索引：只读当前模型的向量，按 unit 取最高分', () => {
  const index = read('entry/src/main/ets/services/NoteVectorIndex.ets');
  assert.match(index, /WHERE e\.model = \?/);
  assert.match(index, /INNER JOIN rag_chunk c ON c\.id = e\.chunk_id/);
  assert.match(index, /if \(existing === undefined \|\| score > existing\.score\)/);
  assert.match(index, /VECTOR_MIN_COSINE/);
  assert.match(index, /COUNT\(\*\) AS n, COALESCE\(MAX\(updated_at\), 0\) AS t/);
});

test('向量写入：确定性行 id + 提交后补建 + 覆盖诊断', () => {
  const service = read('entry/src/main/ets/services/NoteEmbeddingService.ets');
  assert.match(service, /INSERT OR REPLACE INTO rag_embedding/);
  assert.match(service, /const rowId: string = chunk\.id \+ ':' \+ vector\.model/);
  assert.match(service, /texts\.push\(chunks\[i\]\.title \+ '\\n' \+ chunks\[i\]\.content\)/);
  assert.match(service, /static async backfillMissing/);
  assert.match(service, /LEFT JOIN rag_embedding e ON e\.chunk_id = c\.id AND e\.model = \?/);
  assert.match(service, /EmbeddingRuntime\.active\(\)/);
  const effect = read('entry/src/main/ets/services/KnowledgeUnitEmbeddingEffect.ets');
  assert.match(effect, /implements KnowledgeUnitPostCommitEffect/);
  assert.match(effect, /NoteEmbeddingService\.embedUnit/);
  const factory = read('entry/src/main/ets/services/KnowledgeUnitWriteServiceFactory.ets');
  assert.match(factory, /new KnowledgeUnitEmbeddingEffect\(store\)/);
});

test('云端 embedding：OpenAI 兼容 /embeddings，复用当前厂商端点与 Key', () => {
  const port = read('entry/src/main/ets/services/CloudEmbeddingPort.ets');
  assert.match(port, /implements EmbeddingPort/);
  assert.match(port, /return base \+ '\/embeddings'/);
  assert.match(port, /header\['Authorization'\] = 'Bearer ' \+ apiKey/);
  assert.match(port, /const body: EmbeddingRequestBody = \{ model: this\.modelName, input: texts \}/);
  assert.match(port, /throw new Error\('embedding http '/);
  assert.match(port, /BATCH_SIZE: number = 16/);
  const runtime = read('entry/src/main/ets/services/EmbeddingRuntime.ets');
  assert.match(runtime, /static isDense\(\): boolean/);
  assert.match(runtime, /new CloudEmbeddingPort\(modelName\)/);
  assert.match(runtime, /return EmbeddingRuntime\.lexical/);
  const config = read('common/src/main/ets/llm/LlmConfig.ets');
  assert.match(config, /const KEY_EMBEDDING_MODEL = 'embedding_model'/);
  assert.match(config, /public getEmbeddingModel\(\): string/);
  assert.match(config, /public async setEmbeddingModel\(v: string\): Promise<void>/);
  // 聊天厂商（如 DeepSeek）没有 /embeddings，端点与密钥必须能单独配置
  assert.match(config, /const KEY_EMBEDDING_ENDPOINT = 'embedding_endpoint'/);
  assert.match(config, /const KEY_EMBEDDING_API_KEY = 'embedding_api_key'/);
  assert.match(config, /public getEmbeddingEndpoint\(\): string/);
  assert.match(config, /public getEmbeddingApiKey\(\): string/);
  // 不回落到聊天厂商：多数聊天厂商没有 /embeddings
  assert.doesNotMatch(config, /cachedEmbeddingEndpoint\.length > 0 \? this\.cachedEmbeddingEndpoint : this\.getEndpoint\(\)/);
  assert.match(port, /config\.getEmbeddingEndpoint\(\)/);
  assert.match(port, /const apiKey: string = config\.getEmbeddingApiKey\(\)/);
  assert.match(port, /if \(apiKey\.length > 0\) \{/, '密钥可选：本地服务不带鉴权');
  assert.match(runtime, /config\.getEmbeddingEndpoint\(\)\.length > 0/);
  assert.doesNotMatch(runtime, /getEmbeddingApiKey\(\)\.length > 0/, '本地服务不需要密钥');
});

test('检索主链路：五路召回 + RRF 融合，向量失败不影响其余通道', () => {
  const service = read('entry/src/main/ets/services/RagRetrievalService.ets');
  assert.match(service, /import \{ extractMathSignature, fuseRrf, mergeQueryTerms, planQueryTerms \} from 'common'/);
  assert.match(service, /const fusedIds: string\[\] = fuseRrf\(channels, topK\)/);
  assert.match(service, /CHANNEL_WEIGHT_WHOLE/);
  assert.match(service, /CHANNEL_WEIGHT_SIGNATURE/);
  assert.match(service, /CHANNEL_WEIGHT_TERMS/);
  assert.match(service, /CHANNEL_WEIGHT_SHORT/);
  assert.match(service, /CHANNEL_WEIGHT_VECTOR/);
  assert.match(service, /await NoteVectorIndex\.search\(store, query, fetchK\)/);
  assert.match(service, /rag vector search failed/);
  assert.match(service, /FUSION_OVERFETCH/);
  // 词面向量分不开相关与无关（真机实测），检索侧只在配置了云端稠密模型时才开向量通道。
  assert.match(service, /if \(EmbeddingRuntime\.isDense\(\)\) \{/);
});
