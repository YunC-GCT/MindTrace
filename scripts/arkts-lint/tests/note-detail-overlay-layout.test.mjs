import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const overlay = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets');
const detailMeta = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailMeta.ets');
const actionBar = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteActionBar.ets');
const deleteButton = read('entry/src/main/ets/shared/atoms/DeleteButton.ets');
const appIcon = read('entry/src/main/ets/shared/atoms/AppIcon.ets');
const reviewPlanRow = read('entry/src/main/ets/pages/Review/ReviewPlanRow.ets');
const reviewPlanView = read('entry/src/main/ets/pages/Review/ReviewPlanView.ets');
const reviewPage = read('entry/src/main/ets/pages/Review/ReviewPage.ets');
const markdownRenderer = read('entry/src/main/ets/shared/molecules/MarkdownRenderer.ets');
const detailStepList = read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepList.ets');

test('note detail header paints through the status area while its content keeps the safe inset', () => {
  assert.doesNotMatch(overlay, /height\(this\.sbh \+ S_2\)/);
  assert.match(overlay, /NoteDetailMeta\(\{[\s\S]*?topInset: this\.sbh/);
  assert.match(detailMeta, /@Prop topInset: number = 0/);
  assert.match(detailMeta, /padding\(\{ left: S_5, right: S_5, top: this\.topInset \+ S_4, bottom: S_5 \}\)/);
  assert.match(overlay, /if \(this\.isEditing\) \{\s*Row\(\)\.width\('100%'\)\.height\(this\.sbh\)/);
  assert.match(overlay, /else if \(!this\.canRenderReadOnlyDetail\(\)\) \{\s*Row\(\)\.width\('100%'\)\.height\(this\.sbh\)/);
  assert.doesNotMatch(overlay, /NoteCloseButton/);
  assert.doesNotMatch(overlay, /Text\(this\.modeTitle\(\)\)/);
});

test('read-only footer places delete immediately before edit', () => {
  assert.match(overlay, /NoteActionBar\(\{[\s\S]*?onDelete: \(\): void => this\.confirmDelete\(\)/);
  assert.match(
    actionBar,
    /DeleteButton\([\s\S]*?Blank\(\)\.width\(S_2\)[\s\S]*?name: 'edit'/,
  );
});

test('shared delete button uses the HarmonyOS system symbol and emits only a tap intent', () => {
  assert.match(deleteButton, /SymbolGlyph\(\$r\('sys\.symbol\.trash'\)\)/);
  assert.match(deleteButton, /onTap: \(\) => void/);
  assert.doesNotMatch(deleteButton, /NoteViewModel|promptAction|confirmDelete|noteId/);
});

test('delete action uses the same compact container as adjacent note actions', () => {
  assert.match(deleteButton, /R_MD/);
  assert.match(deleteButton, /GLASS_10/);
  assert.match(deleteButton, /\.borderRadius\(R_MD \+ 2\)/);
  assert.match(deleteButton, /\.backgroundColor\(GLASS_10\)/);
  assert.doesNotMatch(deleteButton, /glassSurfaceColor\(DANGER\)|borderToneColor\(DANGER\)/);
});

test('note deletion stays behind an explicit cancel-or-delete confirmation', () => {
  assert.match(overlay, /private confirmDelete = \(\): void => \{/);
  assert.match(overlay, /promptAction\.showDialog\(\{[\s\S]*?buttons: \[[\s\S]*?text: '取消'[\s\S]*?text: '删除'/);
  assert.match(overlay, /onDelete: \(\): void => this\.confirmDelete\(\)/);
});

test('review plan deletion also stays behind cancel-or-delete confirmation', () => {
  assert.match(reviewPage, /private confirmDeletePlan = \(item: StudyPlanItem\): void => \{/);
  assert.match(reviewPage, /promptAction\.showDialog\(\{[\s\S]*?text: "取消"[\s\S]*?text: "删除"/);
  assert.match(reviewPage, /onRemovePlan: this\.confirmDeletePlan/);
});

test('note detail and review plan reuse the shared delete atom', () => {
  assert.match(actionBar, /import \{ DeleteButton \} from '\.\.\/\.\.\/shared\/atoms\/DeleteButton'/);
  assert.match(reviewPlanRow, /import \{ DeleteButton \} from "\.\.\/\.\.\/shared\/atoms\/DeleteButton"/);
  assert.doesNotMatch(reviewPlanRow, /deleteIcon|deleteColor/);
  assert.doesNotMatch(reviewPlanView, /deleteIcon|deleteColor/);
  assert.doesNotMatch(appIcon, /this\.name === "trash"/);
});

test('markdown content renders every parsed block without a continue-reading gate', () => {
  assert.match(markdownRenderer, /ForEach\(this\.parsedBlocks/);
  assert.doesNotMatch(markdownRenderer, /继续阅读|ContinueReading|visibleBlockCount|hasDeferredBlocks/);
  assert.match(detailStepList, /ForEach\(this\.items/);
  assert.doesNotMatch(detailStepList, /继续阅读|visibleItemCount|visibleItems|showNextItemBatch/);
});
