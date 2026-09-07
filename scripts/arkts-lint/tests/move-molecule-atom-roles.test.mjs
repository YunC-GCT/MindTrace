/**
 * move-molecule-atom-roles.test.mjs — TDD Red phase: spec 016 PR-C (issue #67)
 *
 * Asserts the post-PR-C state:
 *   - MathTextRenderer.ets  shared/atoms/  →  shared/molecules/  (audit C1 final)
 *   - MathPreviewText.ets   shared/atoms/  →  shared/molecules/  (audit C5)
 *   - IconButton.ets extracted from overlays/NoteDetailOverlay/NoteIconButton.ets
 *                           to  shared/atoms/IconButton.ets   (audit C5)
 *   - All consumers' import paths updated
 *   - spec 012 §Layering rules allows molecule→molecule composition
 *
 * Companion Hypium tests cover runtime behavior (no behavior change here —
 * only structural moves).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');

const oldMathTextRenderer = join(root, 'entry/src/main/ets/shared/atoms/MathTextRenderer.ets');
const newMathTextRenderer = join(root, 'entry/src/main/ets/shared/molecules/MathTextRenderer.ets');
const oldMathPreviewText = join(root, 'entry/src/main/ets/shared/atoms/MathPreviewText.ets');
const newMathPreviewText = join(root, 'entry/src/main/ets/shared/molecules/MathPreviewText.ets');
const newIconButton = join(root, 'entry/src/main/ets/shared/atoms/IconButton.ets');
const oldNoteIconButton = join(root, 'entry/src/main/ets/overlays/NoteDetailOverlay/NoteIconButton.ets');
const spec012 = join(root, 'docs/specs/012-frontend-component-model.md');

function file(p) { return existsSync(p) ? readFileSync(p, 'utf8') : ''; }

test('MathTextRenderer.ets relocated to shared/molecules/', () => {
  assert.doesNotMatch(
    existsSync(oldMathTextRenderer) ? 'EXISTS' : 'GONE',
    /EXISTS/,
    'MathTextRenderer.ets still in shared/atoms/'
  );
  assert.ok(existsSync(newMathTextRenderer), 'MathTextRenderer.ets not at shared/molecules/');
  const src = file(newMathTextRenderer);
  assert.match(src, /export\s+struct\s+MathTextRenderer\b/);
  assert.match(src, /@Component\b/);
});

test('MathTextRenderer header comment updated to layer molecule', () => {
  const src = file(newMathTextRenderer);
  assert.match(src, /molecules/, 'Header comment must reflect molecule layer');
});

test('MathPreviewText.ets relocated to shared/molecules/', () => {
  assert.ok(!existsSync(oldMathPreviewText), 'MathPreviewText.ets still in shared/atoms/');
  assert.ok(existsSync(newMathPreviewText), 'MathPreviewText.ets not at shared/molecules/');
  const src = file(newMathPreviewText);
  assert.match(src, /export\s+struct\s+MathPreviewText\b/);
  assert.match(src, /from\s+['"]\.\/MathTextRenderer['"]/, 'must import MathTextRenderer sibling');
});

test('IconButton.ets created at shared/atoms/', () => {
  assert.ok(existsSync(newIconButton), 'IconButton.ets not at shared/atoms/');
  const src = file(newIconButton);
  assert.match(src, /export\s+struct\s+IconButton\b/);
  assert.match(src, /@Component\b/);
});

test('Old NoteIconButton.ets removed from overlays/', () => {
  assert.ok(!existsSync(oldNoteIconButton), 'NoteIconButton.ets still in overlays/');
});

test('MathTextRenderer consumers reference shared/molecules/', () => {
  const consumers = [
    'entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets',
    'entry/src/main/ets/shared/molecules/MarkdownRenderer.ets',
    'entry/src/main/ets/shared/molecules/MathPreviewText.ets',
  ];
  for (const f of consumers) {
    const src = file(join(root, f));
    const isSibling = /from\s+['"]\.\/MathTextRenderer['"]/.test(src);
    const isCrossDir = /from\s+['"](?:\.\.\/)+molecules\/MathTextRenderer['"]/.test(src);
    assert.ok(
      isSibling || isCrossDir,
      `${f}: must import MathTextRenderer from shared/molecules/`
    );
  }
});

test('MathPreviewText consumers reference shared/molecules/', () => {
  const consumers = [
    'entry/src/main/ets/shared/organisms/NoteCard.ets',
    'entry/src/main/ets/pages/Notes/SubjectCard.ets',
  ];
  for (const f of consumers) {
    const src = file(join(root, f));
    assert.match(
      src,
      /from\s+['"](?:\.\.\/)+(?:shared\/)?molecules\/MathPreviewText['"]/,
      `${f}: must import MathPreviewText from shared/molecules/MathPreviewText`
    );
  }
});

test('IconButton consumers reference shared/atoms/IconButton (not NoteIconButton)', () => {
  const consumers = [
    'entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/NoteActionBar.ets',
  ];
  for (const f of consumers) {
    const src = file(join(root, f));
    assert.match(src, /from\s*['"][^'"]*shared\/atoms\/IconButton['"]/, `${f}: must import IconButton`);
    assert.doesNotMatch(src, /\bNoteIconButton\b/, `${f}: still references NoteIconButton`);
  }
});

test('spec 012 §Layering rules allows molecule→molecule composition', () => {
  const src = file(spec012);
  // New rule: molecule may reference sibling molecule (narrowing/view)
  assert.match(
    src,
    /Atom\s*\+\s*\u540c\u5c42\s*Molecule|\u540c\u5c42|同层.*Molecule|MathPreviewText.*MathTextRenderer/is,
    'spec 012 must explicitly allow molecule-to-molecule composition'
  );
});

test('common/Index.ets uses export { ... } from (no destructuring declaration)', () => {
  // ArkTS 1.1 forbids `export const { X, Y } from ...` (arkts-no-destruct-decls, error 10605074).
  // Only plain `export { X, Y } from ...` is valid. This guard prevents the destructuring
  // pattern that broke the PR-C hvigor build.
  const indexSrc = file(join(root, 'common/src/main/ets/Index.ets'));
  assert.doesNotMatch(
    indexSrc,
    /export\s+const\s*\{[^}]*\}\s*from/,
    'common/Index.ets uses destructuring declaration (export const { ... } from ...) — ArkTS 1.1 forbids this; use plain `export { ... } from ...`'
  );
});