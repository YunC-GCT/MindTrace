#!/usr/bin/env node
/**
 * scripts/rag-lab/fetch-mathnet.mjs — 下载 MathNet-Retrieve（easy 档）
 *
 * 用途: 拉取公开数学检索基准 MathNet-Retrieve 的 easy 档到 .cache（git 忽略）。
 *       数据集: https://huggingface.co/datasets/ShadenA/MathNet-Retrieve（CC-BY-4.0）
 * 用法:
 *   node scripts/rag-lab/fetch-mathnet.mjs
 *   node scripts/rag-lab/fetch-mathnet.mjs --tier medium
 * 说明: 默认走 hf-mirror.com；可用 HF_ENDPOINT 覆盖。
 */
import { existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = 'https://huggingface.co/datasets/ShadenA/MathNet-Retrieve/resolve/main';
const MIRROR = process.env.HF_ENDPOINT ?? 'https://hf-mirror.com';

function parseArgs(argv) {
  const options = { tier: 'easy' };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--tier' && i + 1 < argv.length) {
      options.tier = argv[i + 1];
      i += 1;
    }
  }
  return options;
}

function baseUrl() {
  if (MIRROR.includes('huggingface.co')) {
    return REPO;
  }
  return MIRROR.replace(/\/+$/, '') + '/datasets/ShadenA/MathNet-Retrieve/resolve/main';
}

async function download(url, target) {
  if (existsSync(target) && statSync(target).size > 0) {
    process.stdout.write('[mathnet] skip ' + target + '\n');
    return;
  }
  process.stdout.write('[mathnet] download ' + url + '\n');
  const response = await fetch(url, { signal: AbortSignal.timeout(600000) });
  if (!response.ok) {
    throw new Error('HTTP ' + response.status + ' for ' + url);
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, buffer);
  process.stdout.write('[mathnet] saved ' + target + ' (' + buffer.length + ' bytes)\n');
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const base = baseUrl();
  const root = join(ROOT, '.cache', 'rag-lab', 'mathnet-retrieve', options.tier);
  const files = [
    ['queries.jsonl', join(root, 'queries.jsonl')],
    ['qrels/test.jsonl', join(root, 'qrels', 'test.jsonl')],
    ['corpus.jsonl', join(root, 'corpus.jsonl')],
  ];
  for (const [relative, target] of files) {
    await download(base + '/' + options.tier + '/' + relative, target);
  }
  process.stdout.write('[mathnet] ready: ' + root + '\n');
}

main().catch((error) => {
  process.stderr.write('[mathnet] ' + error.message + '\n');
  process.exit(1);
});
