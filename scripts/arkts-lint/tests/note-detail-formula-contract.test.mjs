/**
 * #184 NoteDetail MM-MD-v1 formula contract guard.
 *
 * This structural guard keeps the correctness boundary and the normalized cache retry seam
 * visible to the Node test suite. Behavioural examples remain in the common/entry Hypium tests.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('ContentProtocol remains the single MM-MD-v1 formula normalization boundary', () => {
  const protocol = read('common/src/main/ets/render/ContentProtocol.ets');
  const parser = read('entry/src/main/ets/utils/MarkdownParser.ets');
  assert.match(protocol, /export class ContentProtocol/);
  assert.match(protocol, /normalizeDisplayFormula/);
  assert.match(protocol, /validateLatexEnvironments/);
  assert.match(protocol, /nextUnescapedBacktick/);
  assert.match(protocol, /nextDisplayDelimiterOutsideInlineCode/);
  assert.match(parser, /new ContentProtocol\(\)\.normalizeNoteMarkdown/);
  assert.doesNotMatch(parser, /split\(['"]\$\$['"]\)/);
  assert.match(parser, /let inInlineCode: boolean = false/);
  assert.match(parser, /const outsideFormula: boolean = !inInlineCode/);
});

test('formula failure fixture preserves surrounding text and later formula reachability', () => {
  const protocolTest = read('common/src/test/ContentProtocol.test.ets');
  assert.match(protocolTest, /falls_back_on_unbalanced_left_right_without_dropping_plain_text_contract/);
  assert.match(protocolTest, /后续公式 \$y\^2\$/);
  const html = read('entry/src/main/resources/rawfile/render.html');
  assert.match(html, /throwOnError:\s*false/);
  assert.match(html, /render-error/);
  const renderer = read('entry/src/main/ets/shared/atoms/MathTextRenderer.ets');
  const failureState = read('entry/src/main/ets/utils/MathRenderFailureState.ets');
  const failureTest = read('entry/src/test/MathRenderFailureState.test.ets');
  assert.match(renderer, /fallbackFn: string = this\.forceDisplay \? 'renderFormula' : 'render'/);
  assert.match(renderer, /this\.acceptRenderedHeight\(payload\.height\)/);
  assert.match(renderer, /this\.acceptRenderedHeight\(parsedHeight\)/);
  assert.match(renderer, /this\.failureState\.recordFailure\(\)/);
  assert.match(renderer, /this\.activateBridgeFallback\(\)/);
  assert.match(renderer, /setWebHeight\(height, true\)/);
  assert.match(failureState, /acceptHeight\(height: number\)/);
  assert.match(failureState, /!Number\.isFinite\(height\)/);
  assert.match(failureState, /recordFailure\(\)/);
  assert.match(failureTest, /invalid_height_degrades_only_the_current_formula/);
  assert.match(failureTest, /render_exit_and_bridge_failure_keep_later_formula_reachable/);
  const testList = read('entry/src/test/List.test.ets');
  assert.match(testList, /mathRenderFailureStateTest\(\)/);
});

test('MathTextRenderer retries bridge failures with normalized formula input', () => {
  const budget = read('entry/src/main/ets/services/MathRenderBudget.ets');
  const renderer = read('entry/src/main/ets/shared/atoms/MathTextRenderer.ets');
  const hypium = read('entry/src/test/DetailRenderSession.test.ets');
  assert.match(budget, /export function buildNormalizedMathRenderScript/);
  assert.match(renderer, /buildNormalizedMathRenderScript/);
  assert.match(hypium, /cold_and_retry_scripts_share_the_normalized_prepared_value/);
});

test('render.html keeps KaTeX safety and display overflow protections', () => {
  const html = read('entry/src/main/resources/rawfile/render.html');
  assert.match(html, /htmlAndMathml/);
  assert.match(html, /trust:\s*false/);
  assert.match(html, /maxExpand:\s*1000/);
  assert.equal((html.match(/maxExpand:\s*1000/g) || []).length, 2);
  assert.match(html, /escapeRawHtml/);
  assert.match(html, /overflow-x:\s*auto/);
});
