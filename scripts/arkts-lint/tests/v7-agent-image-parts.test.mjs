// 路径: scripts/arkts-lint/tests/v7-agent-image-parts.test.mjs
// 职责: 小艺请求 part 的形状判定 / 图片提取契约测试（装载真实 .ets，不复制实现）。
// Why: 小艺目前只下发 text part；一旦平台开始透传图片，判定写错就会
//      要么把图片当文字吞掉（不识别、不回执），要么把普通长问题误判成图片。

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const mod = loadNoteReviewEtsModule('entry/src/main/ets/services/AgentImageParts.ets');
const { isImagePart, collectImageParts, joinTextParts } = mod;

test('a plain text part is not an image', () => {
  assert.equal(isImagePart({ mediaType: 'text/plain', text: '存笔记：矩阵的秩' }), false);
});

test('image mediaType is recognised even without bytes', () => {
  assert.equal(isImagePart({ mediaType: 'image/png' }), true);
  assert.equal(isImagePart({ mediaType: 'image/jpeg', url: 'file:///data/a.jpg' }), true);
});

test('raw bytes with no mediaType still count as an image', () => {
  assert.equal(isImagePart({ raw: 'iVBORw0KGgo=' }), true);
});

test('collect keeps base64 raw parts and uri parts separately', () => {
  const images = collectImageParts([
    { mediaType: 'text/plain', text: '整理这几张' },
    { mediaType: 'image/png', raw: 'AAAA' },
    { mediaType: 'image/jpeg', url: 'file:///data/b.jpg' },
  ]);
  assert.equal(images.length, 2);
  // 装载后的对象来自另一个 realm，逐字段比，不用 deepEqual
  assert.equal(images[0].kind, 'base64');
  assert.equal(images[0].value, 'AAAA');
  assert.equal(images[1].kind, 'uri');
  assert.equal(images[1].value, 'file:///data/b.jpg');
});

test('an image part with neither raw nor url is skipped instead of crashing', () => {
  const images = collectImageParts([{ mediaType: 'image/png', text: '' }]);
  assert.equal(images.length, 0, '拿不到字节就跳过，交给「没认出文字」回执');
});

test('data 里直接放 base64（含 data url 前缀）也能取到字节', () => {
  const plain = collectImageParts([{ mediaType: 'image/png', data: 'AAAA' }]);
  assert.equal(plain.length, 1);
  assert.equal(plain[0].kind, 'base64');
  assert.equal(plain[0].value, 'AAAA');

  const dataUrl = collectImageParts([
    { mediaType: 'image/jpeg', data: 'data:image/jpeg;base64,/9j/4AAQ' },
  ]);
  assert.equal(dataUrl.length, 1);
  assert.equal(dataUrl[0].value, '/9j/4AAQ', 'data url 前缀必须剥掉，否则 base64 解不出来');
});

test('Part<url> 形状（端A2A 文档里的图片下发方式）被当成 uri 图', () => {
  const images = collectImageParts([
    { url: 'file://docs/storage/Users/currentUser/a.png', filename: 'a.png', mediaType: 'image/png' },
  ]);
  assert.equal(images.length, 1);
  assert.equal(images[0].kind, 'uri');
  assert.equal(images[0].value, 'file://docs/storage/Users/currentUser/a.png');
});

test('云A2A 的 file 形状（{kind:file, file:{uri,mimeType}}）也当图片，别只认 mediaType', () => {
  const images = collectImageParts([
    { kind: 'file', file: { uri: 'file://docs/a.jpg', mimeType: 'image/jpeg', name: 'a.jpg' } },
  ]);
  assert.equal(images.length, 1);
  assert.equal(images[0].kind, 'uri');
  assert.equal(images[0].value, 'file://docs/a.jpg');
});

test('实测报文形状（只有 mediaType=text/plain 的空 part）不产生图片', () => {
  const parts = [{ mediaType: 'text/plain' }];
  assert.equal(collectImageParts(parts).length, 0);
  assert.equal(joinTextParts(parts), '');
});

test('text beside images is preserved as the hint', () => {
  const parts = [
    { mediaType: 'image/png', raw: 'AAAA' },
    { mediaType: 'text/plain', text: '  存笔记：这两道题  ' },
  ];
  assert.equal(joinTextParts(parts), '存笔记：这两道题');
  assert.equal(collectImageParts(parts).length, 1);
});

test('multiple text parts are joined in order', () => {
  const parts = [
    { mediaType: 'text/plain', text: '第一行' },
    { mediaType: 'text/plain', text: '第二行' },
  ];
  assert.equal(joinTextParts(parts), '第一行\n第二行');
});
