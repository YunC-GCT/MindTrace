/**
 * #183 NoteDetail automatic expansion and visible-first release contract.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const rendererPaths = [
  'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ConceptDetailView.ets',
  'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/TheoremDetailView.ets',
  'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FormulaDetailView.ets',
  'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ProofDetailView.ets',
  'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ComputationDetailView.ets',
  'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FallbackDetailView.ets',
];

test('NoteDetail exposes named visible-first priorities through the instance session', () => {
  const session = read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession.ets');
  for (const priority of [
    'DETAIL_RENDER_PRIORITY_VISIBLE_TEXT',
    'DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA',
    'DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT',
    'DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT',
    'DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA',
    'DETAIL_RENDER_PRIORITY_META',
  ]) {
    assert.match(session, new RegExp('export const ' + priority));
  }
});

test('all renderer families auto-release through the session without staged state', () => {
  const gatePath = 'entry/src/main/ets/overlays/NoteDetailOverlay/DetailReleaseGate.ets';
  assert.ok(existsSync(resolve(root, gatePath)), gatePath + ' must exist');
  const gate = read(gatePath);
  assert.match(gate, /renderSession\.enqueue/);
  assert.match(gate, /releasePriority/);
  assert.match(gate, /ContentProtocol/);
  assert.match(gate, /hasFormulaSyntax\(this\.releaseContent\)/);
  assert.doesNotMatch(gate, /setTimeout|ContinueReading|继续阅读/);

  for (const path of rendererPaths) {
    const source = read(path);
    assert.match(source, /DetailReleaseGate/, path + ' must use the instance release gate');
    assert.match(source, /releaseKey:\s*this\.renderSession\.scopeKey\(/,
      path + ' must scope release keys to the active detail session');
    assert.match(source, /DETAIL_RENDER_PRIORITY_VISIBLE_TEXT/, path + ' must identify visible text work');
    assert.match(source, /DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA/, path + ' must identify visible formula work');
    assert.match(source, /DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT/, path + ' must identify near-viewport work');
    assert.match(source, /DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT/, path + ' must identify offscreen work');
    assert.match(source, /DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA/, path + ' must identify offscreen formula work');
    assert.doesNotMatch(source, /visibleStage|schedule(?:Concept|Theorem|Formula|Proof|Computation|Fallback)Stage/);
    assert.doesNotMatch(source, /setTimeout/);
  }
});

test('NoteDetail Markdown and steps are fully expanded while chat keeps its profile', () => {
  const noteSources = rendererPaths
    .concat([
      'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailSection.ets',
      'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepList.ets',
      'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailMetaFooter.ets',
    ])
    .map(read)
    .join('\n');
  const steps = read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepList.ets');
  const chat = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentAnswerStep.ets');

  assert.doesNotMatch(noteSources, /MarkdownRenderer\(\{[^}]*progressive:\s*true/);
  assert.match(noteSources, /MarkdownRenderer\(\{[^}]*progressive:\s*false[^}]*profile:\s*'note'/);
  assert.match(steps, /ForEach\(this\.items/);
  assert.doesNotMatch(steps, /ContinueReading|继续阅读|visibleItemCount|showNextItemBatch/);
  const meta = read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailMetaFooter.ets');
  assert.doesNotMatch(meta, /originalExpanded|\.onClick\(/);
  assert.match(meta, /OriginalMaterial[\s\S]*MarkdownRenderer\(\{[^}]*progressive:\s*false[^}]*profile:\s*'note'/);
  assert.match(chat, /progressive:\s*false/);
  assert.match(chat, /profile:\s*'chat'/);
});

test('NoteDetail Markdown releases complete content units through the budget seam', () => {
  const markdown = read('entry/src/main/ets/shared/molecules/MarkdownRenderer.ets');
  const math = read('entry/src/main/ets/shared/atoms/MathTextRenderer.ets');
  const budget = read('entry/src/main/ets/services/MathRenderBudget.ets');
  const session = read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession.ets');
  const hypium = read('entry/src/test/DetailRenderSession.test.ets');

  assert.match(budget, /enqueueContent\(key:\s*string,\s*priority:\s*number,\s*run:\s*\(\)\s*=>\s*void\):\s*void/);
  assert.match(session, /enqueueContent\(key:\s*string,\s*priority:\s*number,\s*run:\s*\(\)\s*=>\s*void\):\s*void/);
  assert.match(markdown, /renderBudget\.enqueueContent/);
  assert.match(math, /onContentReady:\s*\(\)\s*=>\s*void\s*=\s*\(\):\s*void\s*=>/);
  assert.match(hypium, /releases_markdown_content_units_one_at_a_time/);
});

test('a formula list completes before the following Markdown heading is released', () => {
  const markdown = read('entry/src/main/ets/shared/molecules/MarkdownRenderer.ets');
  const barrier = read('entry/src/main/ets/services/MarkdownContentReleaseBarrier.ets');
  const hypium = read('entry/src/test/DetailRenderSession.test.ets');

  assert.match(markdown, /MarkdownContentReleaseBarrier/);
  assert.match(markdown, /waitFor\(unitKey\)/);
  assert.match(markdown, /deferNextBlock\(\)/);
  assert.match(markdown, /complete\(unitKey\)/);
  assert.match(barrier, /export class MarkdownContentReleaseBarrier/);
  assert.match(hypium, /waits_for_formula_list_before_releasing_next_heading/);
});

test('renderer family block order remains stable after automatic expansion', () => {
  const expectations = [
    [rendererPaths[0], ['DefinitionBlock', 'PropertiesBlock', 'ExamplesBlock', 'RelatedBlock', 'SupplementBlock']],
    [rendererPaths[1], ['StatementBlock', 'ConclusionBlock', 'ConditionBlock', 'InsightBlock', 'ApplicationBlock', 'SupplementBlock']],
    [rendererPaths[2], ['ExpressionBlock', 'ParameterBlock', 'RangeBlock', 'DerivationBlock', 'NotesBlock', 'SupplementBlock']],
    [rendererPaths[3], ['PropositionBlock', 'InsightBlock', 'ProcessBlock', 'ConclusionBlock', 'GivenBlock', 'SupplementBlock']],
    [rendererPaths[4], ['ProblemBlock', 'StepsBlock', 'AnswerBlock', 'MethodBlock', 'NotesBlock', 'SupplementBlock']],
  ];
  for (const [path, blocks] of expectations) {
    const source = read(path);
    const start = source.indexOf('  build() {');
    const end = source.indexOf('\n  @Builder', start);
    const buildBody = source.substring(start, end);
    let previousIndex = -1;
    for (const block of blocks) {
      const index = buildBody.indexOf('this.' + block + '(');
      assert.ok(index > previousIndex, path + ' must preserve ' + block + ' order');
      previousIndex = index;
    }
  }

  const fallback = read(rendererPaths[5]);
  const fallbackBuildStart = fallback.indexOf('  build() {');
  const fallbackBuildEnd = fallback.indexOf('\n  @Builder', fallbackBuildStart);
  const fallbackBuild = fallback.substring(fallbackBuildStart, fallbackBuildEnd);
  assert.ok(fallbackBuild.indexOf('ForEach(this.model.sections') >= 0);
  assert.ok(fallbackBuild.indexOf('this.SourceSection(') > fallbackBuild.indexOf('ForEach(this.model.sections'));
  assert.ok(fallbackBuild.indexOf('DetailMetaFooter(') > fallbackBuild.indexOf('this.SourceSection('));
});
