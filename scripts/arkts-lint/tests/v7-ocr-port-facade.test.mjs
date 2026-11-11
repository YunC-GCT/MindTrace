// 路径: scripts/arkts-lint/tests/v7-ocr-port-facade.test.mjs
// 职责: 静态守卫 OCR 能力端口的分层边界——
//       1) OcrService 只是门面, 不得再出现 CoreVisionKit / ImageKit / textRecognition / image / createImageSource
//       2) OcrService 只能经 OcrRecognizerRegistry.require() 取实现
//       3) :agent 进程的组合根自己 install OCR 实现（主进程由 EntryAbility 安装）
//       4) 能力端口暴露 recognize(uri) 与 recognizeBase64(base64); 适配器两者都实现
// Why: 门面里重复写一遍 Kit 调用会把「能力端口是唯一入口」破坏掉；
//      任何一处绕过端口, :agent 组合根安装的实现就不再是唯一真相。
//      这些断言读源码而不是 import .ets（ArkTS 源文件不能直接被 node 执行）。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const REPO_ROOT = new URL('../../../', import.meta.url);
const readRepoFile = (path) => readFileSync(new URL(path, REPO_ROOT), 'utf8');

const OCR_SERVICE = 'entry/src/main/ets/services/OcrService.ets';
const AGENT_EXT_ABILITY = 'entry/src/main/ets/agentextability/AgentExtAbility.ets';
const OCR_PORT = 'common/src/main/ets/capability/ocr/OcrRecognizer.ets';
const CORE_VISION = 'entry/src/main/ets/services/CoreVisionOcrRecognizer.ets';

test('OcrService 不得直接调用 OCR / 图像 Kit（分层规则：门面只依赖能力端口）', () => {
  const source = readRepoFile(OCR_SERVICE);
  assert.equal(source.indexOf('@kit.CoreVisionKit'), -1,
    '违反分层规则: OcrService 不得 import @kit.CoreVisionKit；OCR Kit 只能在 CoreVisionOcrRecognizer（由组合根安装的实现）里加载');
  assert.equal(source.indexOf('@kit.ImageKit'), -1,
    '违反分层规则: OcrService 不得 import @kit.ImageKit；解码/建 PixelMap 属于适配器职责');
  assert.equal(source.indexOf('textRecognition.'), -1,
    '违反分层规则: OcrService 不得调用 textRecognition.*；识别只能经 OcrRecognizerRegistry.require()');
  assert.equal(source.indexOf('image.'), -1,
    '违反分层规则: OcrService 不得调用 image.*；ImageSource / PixelMap 生命周期属于适配器');
  assert.equal(source.indexOf('createImageSource'), -1,
    '违反分层规则: OcrService 不得调用 createImageSource；base64/uri 解码由适配器的 recognizeBase64/recognize 负责');
  assert.equal(source.indexOf('recognizeText('), -1,
    '违反分层规则: OcrService 不得调用 recognizeText()；识别只能经 OcrRecognizerRegistry.require()');
});

test('OcrService 必须经 OcrRecognizerRegistry.require() 取实现', () => {
  const source = readRepoFile(OCR_SERVICE);
  assert.ok(source.includes('OcrRecognizerRegistry.require()'),
    '违反分层规则: OcrService 必须经 OcrRecognizerRegistry.require() 取 OCR 实现，不得自己 new 适配器或直接调 Kit');
});

test(':agent 组合根必须在 onCreate 安装 OCR 实现', () => {
  const source = readRepoFile(AGENT_EXT_ABILITY);
  assert.ok(source.includes('OcrRecognizerRegistry.install('),
    '违反分层规则: :agent 进程必须由 AgentExtAbility.onCreate 组合根安装 OCR 实现，否则 OcrService 在扩展进程里拿不到能力');
});

test('OCR 能力端口必须暴露 recognizeBase64(base64)', () => {
  const source = readRepoFile(OCR_PORT);
  assert.ok(source.includes('recognizeBase64'),
    '违反端口契约: OcrRecognizer 必须提供 recognizeBase64(base64)，否则门面只能自己解码 base64（重复 Kit 调用）');
});

test('CoreVisionOcrRecognizer 必须实现端口（含 recognizeBase64）', () => {
  const source = readRepoFile(CORE_VISION);
  assert.ok(source.includes('implements OcrRecognizer'),
    '违反端口契约: CoreVisionOcrRecognizer 必须 implements OcrRecognizer，作为端口的唯一 Kit 实现');
  assert.ok(source.includes('recognizeBase64'),
    '违反端口契约: CoreVisionOcrRecognizer 必须实现 recognizeBase64(base64)，与 recognize(uri) 共用同一条 Kit 调用链');
});
