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

test('issue #227: agents 下不再直接依赖 CoreVisionKit / ImageKit', () => {
  const offenders = codeFilesUnder('agents')
    .filter((file) => /@kit\.(CoreVisionKit|ImageKit)/.test(readFileSync(file, 'utf8')))
    .map(toRepoPath);
  assert.deepEqual(offenders, [], 'agents 只能依赖 common 的 OCR 端口：' + offenders.join(', '));
});

test('common 的 OCR 端口契约零 @kit 依赖，并只经 barrel 导出值 Registry', () => {
  const portPath = 'common/src/main/ets/capability/ocr/OcrRecognizer.ets';
  const port = read(portPath);
  const barrel = read('common/src/main/ets/Index.ets');

  assert.doesNotMatch(port, /@kit/, '端口契约不得 import 任何 @kit');
  assert.match(port, /export interface OcrTextResult \{\s*text: string;\s*confidence: number;\s*\}/);
  assert.match(port, /export interface OcrRecognizer \{/);
  assert.match(port, /recognize\(uri: string\): Promise<OcrTextResult>;/);
  assert.match(port, /isAvailable\(\): boolean;/);
  assert.match(port, /export class OcrRecognizerRegistry \{/);
  assert.match(port, /OCR 能力未初始化（OcrRecognizerRegistry 未安装）/);

  assert.match(barrel, /export \{ OcrRecognizerRegistry \} from '\.\/capability\/ocr\/OcrRecognizer';/);
  assert.match(barrel, /export type \{ OcrRecognizer, OcrTextResult \} from '\.\/capability\/ocr\/OcrRecognizer';/);
});

test('entry 适配层保留两个 Kit，且文件头声明 Process: main only', () => {
  const adapterPath = 'entry/src/main/ets/services/CoreVisionOcrRecognizer.ets';
  const adapter = read(adapterPath);
  const header = adapter.split('\n').slice(0, 20).join('\n');

  assert.match(adapter, /import \{ textRecognition \} from '@kit\.CoreVisionKit';/);
  assert.match(adapter, /import \{ image \} from '@kit\.ImageKit';/);
  assert.match(header, /Process: main only/);
  assert.match(header, /不得进 common barrel/);
  assert.match(adapter, /class CoreVisionOcrRecognizer implements OcrRecognizer/);
});

test('EntryAbility.onCreate 是 OCR 端口的组合根', () => {
  const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(ability, /OcrRecognizerRegistry\.install\(/);
  assert.match(ability, /new CoreVisionOcrRecognizer\(\)/);
});

test('OcrTool 改为经端口取 OCR，且不再出现 textRecognition', () => {
  const tool = read('agents/src/main/ets/mcp/tools/OcrTool.ets');
  assert.match(tool, /OcrRecognizerRegistry\.require\(\)/);
  assert.doesNotMatch(tool, /textRecognition/);
  assert.doesNotMatch(tool, /@kit\.(CoreVisionKit|ImageKit)/);
  assert.match(tool, /constructor\(formulaEndpoint\?: string\)/);
});
