/**
 * #187 NoteDetail formula Web budget and normalized cache contract.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const sessionPath = 'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession.ets';
const mathPath = 'entry/src/main/ets/shared/atoms/MathTextRenderer.ets';
const markdownPath = 'entry/src/main/ets/shared/molecules/MarkdownRenderer.ets';
const budgetPath = 'entry/src/main/ets/services/MathRenderBudget.ets';

test('NoteDetail session owns the configured rolling formula Web admission budgets', () => {
  const session = read(sessionPath);
  assert.match(session, /export const DETAIL_RENDER_MAX_WEB_CREATES_IN_FLIGHT:\s*number\s*=\s*5/);
  assert.match(session, /export const DETAIL_RENDER_MAX_WEB_CREATES_PER_ADMISSION:\s*number\s*=\s*3/);
  assert.match(session, /export const DETAIL_RENDER_WEB_CREATE_ADMISSION_MS:\s*number\s*=\s*16/);
  assert.doesNotMatch(session, /DETAIL_RENDER_WEB_CREATE_STAGGER_MS/);
  assert.match(session, /export const DETAIL_RENDER_MAX_WEB_WORK_MS_PER_FRAME:\s*number\s*=\s*16/);
  assert.match(session, /enqueueWebCreate\(/);
  assert.match(session, /enqueueWebWork\(/);
});

test('Hypium covers the ordered three-wide rolling Web pipeline and ready work ordering', () => {
  const hypium = read('entry/src/test/DetailRenderSession.test.ets');
  assert.match(hypium, /pipelines_five_web_creates_three_per_admission/);
  assert.match(hypium, /runs_ready_web_work_before_next_pipelined_create/);
  assert.match(hypium, /keeps_three_create_limit_when_ready_work_interleaves/);
});

test('NoteDetail formula renderers consume the instance budget while chat and previews stay independent', () => {
  const math = read(mathPath);
  const markdown = read(markdownPath);
  const noteSources = [
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailSection.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepList.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailMetaFooter.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ConceptDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/TheoremDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FormulaDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ProofDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ComputationDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FallbackDetailView.ets',
  ].map(read).join('\n');
  const noteMeta = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailMeta.ets');
  const chat = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentAnswerStep.ets');
  const preview = read('entry/src/main/ets/shared/atoms/MathPreviewText.ets');

  assert.match(math, /@Prop renderBudget:\s*MathRenderBudget \| null = null/);
  assert.match(math, /renderBudget\.enqueueWebCreate/);
  assert.match(math, /renderBudget\.enqueueWebWork/);
  assert.match(markdown, /renderBudget:\s*this\.renderBudget/);
  assert.match(noteSources, /renderBudget:\s*this\.renderSession/);
  assert.equal((noteSources.match(/profile:\s*'note'/g) ?? []).length,
    (noteSources.match(/renderBudget:\s*this\.renderSession/g) ?? []).length,
    'every NoteDetail Markdown renderer must use the owning instance budget');
  assert.match(noteSources, /renderPriority:\s*(?:renderPriority|this\.renderPriority|DETAIL_RENDER_PRIORITY_META)/);
  assert.match(noteMeta, /profile:\s*'preview'[\s\S]*renderBudget:\s*this\.renderSession/);
  assert.doesNotMatch(chat, /renderBudget/);
  assert.doesNotMatch(preview, /renderBudget/);
});

test('formula preparation exposes a stable memo contract used by the renderer', () => {
  const budget = read(budgetPath);
  const math = read(mathPath);
  const hypium = read('entry/src/test/DetailRenderSession.test.ets');
  assert.match(budget, /export class MathRenderPreparationMemo/);
  assert.match(budget, /export function buildMathRenderPreparationKey/);
  assert.match(math, /MathRenderPreparationMemo/);
  assert.match(math, /buildMathRenderPreparationKey/);
  assert.match(hypium, /memoizes_unchanged_preparation_and_invalidates_each_contract_dimension/);
});

test('legacy per-formula defer clock is fully contracted', () => {
  const production = [read(mathPath), read(sessionPath), read(markdownPath)].join('\n');
  assert.doesNotMatch(production, /NOTE_MATH_RENDER_DEFER_/);
  assert.doesNotMatch(production, /noteMathRenderDeferClock/);
  assert.doesNotMatch(production, /nextNoteMathRenderDelay|scheduleDeferredWebRender/);
});

test('formula fallback metrics and unclipped display height remain observable', () => {
  const math = read(mathPath);
  assert.match(math, /recordNoteDetailWebCreate/);
  assert.match(math, /recordNoteDetailWebWorkStart/);
  assert.match(math, /recordNoteDetailRenderExit/);
  assert.match(math, /recordNoteDetailDegradation/);
  assert.match(math, /if \(this\.forceDisplay\)[\s\S]*return Math\.max\(this\.minHeight, height\)/);
  assert.match(math, /horizontalScrollBarAccess\(true\)/);
});
