import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');

const SKIP_DIRS = new Set(['build', 'oh_modules', 'node_modules', '.git']);

function codeFilesUnder(relDir) {
  const out = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const abs = join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name)) {
          walk(abs);
        }
      } else if (/\.(ets|ts|js|mjs)$/.test(entry.name)) {
        out.push(abs);
      }
    }
  };
  walk(resolve(root, relDir));
  return out;
}

const toRepoPath = (abs) => abs.slice(root.length + 1).replace(/\\/g, '/');

test('文搜图端口契约零 @kit 依赖，并只经 barrel 导出值 Registry', () => {
  const portPath = 'common/src/main/ets/capability/imagesearch/ImageSearchIndex.ets';
  const port = read(portPath);
  const barrel = read('common/src/main/ets/Index.ets');

  assert.doesNotMatch(port, /@kit/, '端口契约不得 import 任何 @kit');
  assert.match(port, /export interface ImageSearchHit \{\s*imagePath: string;\s*similarity: number;\s*\}/);
  assert.match(port, /export interface ImageSearchIndex \{/);
  assert.match(port, /insert\(imagePath: string\): Promise<boolean>;/);
  assert.match(port, /search\(query: string, topK\?: number\): Promise<ImageSearchHit\[\]>;/);
  assert.match(port, /export class ImageSearchIndexRegistry \{/);
  assert.match(port, /文搜图能力未初始化（ImageSearchIndexRegistry 未安装）/);

  assert.match(barrel, /export \{ ImageSearchIndexRegistry \} from '\.\/capability\/imagesearch\/ImageSearchIndex';/);
  assert.match(barrel, /export type \{ ImageSearchIndex, ImageSearchHit \} from '\.\/capability\/imagesearch\/ImageSearchIndex';/);
});

test('agents 不直接依赖 textSearchImage / CoreVisionKit', () => {
  const offenders = codeFilesUnder('agents')
    .filter((file) => /textSearchImage|@kit\.CoreVisionKit/.test(readFileSync(file, 'utf8')))
    .map(toRepoPath);
  assert.deepEqual(offenders, [], 'agents 只能依赖 common 的文搜图端口：' + offenders.join(', '));
});

test('entry 适配层用 textSearchImage 且文件头声明 Process: main only', () => {
  const adapterPath = 'entry/src/main/ets/services/CoreVisionImageSearchIndex.ets';
  const adapter = read(adapterPath);
  const header = adapter.split('\n').slice(0, 20).join('\n');

  assert.match(adapter, /import \{ textSearchImage \} from '@kit\.CoreVisionKit';/);
  assert.match(header, /Process: main only/);
  assert.match(header, /不得进 common barrel/);
  assert.match(adapter, /class CoreVisionImageSearchIndex implements ImageSearchIndex/);
  // scope 只允许字母数字（SDK d.ts），写死常量避免运行时才炸
  assert.match(adapter, /const SCOPE: string = 'mindtrace';/);
});

test('组合根注册文搜图端口，capture 落库后建索引', () => {
  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(ability, /ImageSearchIndexRegistry\.install\(new CoreVisionImageSearchIndex\(\)\)/);

  const service = read('entry/src/main/ets/services/AiService.ets');
  assert.match(service, /ImageSearchIndexRegistry\.isInstalled\(\)/);
  assert.match(service, /ImageSearchIndexRegistry\.require\(\)\.insert\(localPath\)/);
});

test('process-boundary 把 CoreVisionKit 限制在 main 进程', () => {
  const checker = read('scripts/process-boundary/check.mjs');
  assert.match(checker, /'@kit\.CoreVisionKit': \[[^\]]*'main'/);
});
