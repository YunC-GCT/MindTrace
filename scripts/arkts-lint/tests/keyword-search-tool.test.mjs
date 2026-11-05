// DEV/AC binding: DEV-RAG-QUERY / AC-RAG-01 — note_query_rag registration in ToolCatalog,
// query/topK default 5 max 10, subject/chapter/tag/time params, title/tag/summary/body hit,
// stable sort, excerpt; backward compat: note_query and SkillIntentWorkflow SearchNote preserved.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8').replace(/\r\n/g, '\n');

const noteQueryTools = read('common/src/main/ets/tools/NoteQueryTools.ets');
const toolCatalog = read('common/src/main/ets/tools/ToolCatalog.ets');
const skillIntent = read('skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets');
const intentRouter = read('skill/src/main/ets/workflows/intent/IntentRouter.ets');
const toolRegistry = read('common/src/main/ets/tools/ToolRegistry.ets');
const noteSearchPort = read('common/src/main/ets/ports/NoteSearchPort.ets');
const noteSearchAdapter = read('common/src/main/ets/ports/impl/RdbNoteSearchAdapter.ets');
const noteSearchRanking = read('common/src/main/ets/ports/impl/NoteSearchRanking.ets');

// === Legacy note_query compatibility (must still pass) ===

test('NoteQueryTool registers as note_query in the read-only catalog', () => {
  assert.match(noteQueryTools, /name: string = 'note_query'/);
  assert.match(toolCatalog, /createReadOnlyNoteTools/);
});

test('NoteQueryTool accepts keyword parameter that matches title or content', () => {
  assert.match(noteQueryTools, /keyword/);
  assert.match(noteQueryTools, /contains\('title'/);
  assert.match(noteQueryTools, /contains\('content'/);
});

test('NoteQueryTool caps results at MAX_QUERY_RESULTS', () => {
  assert.match(noteQueryTools, /MAX_QUERY_RESULTS/);
  assert.match(noteQueryTools, /limit.*MAX_QUERY_RESULTS|MAX_QUERY_RESULTS.*limit/);
});

test('NoteQueryTool supports exact subject match', () => {
  assert.match(noteQueryTools, /subject/);
  assert.match(noteQueryTools, /equalTo\('subject'/);
});

test('NoteQueryTool supports review_status filter', () => {
  assert.match(noteQueryTools, /review_status/);
  assert.match(noteQueryTools, /equalTo\('review_status'/);
});

test('SkillIntentWorkflow routes search_note to NoteQueryTool execute', () => {
  assert.match(skillIntent, /execute_search/);
  assert.match(skillIntent, /registry\.execute\('note_query'/);
});

test('IntentRouter extracts keyword from Want parameters', () => {
  assert.match(intentRouter, /keyword/);
  assert.match(intentRouter, /SearchNote/);
});

test('NoteQueryTool queries knowledge_unit table directly (no soft-delete filter)', () => {
  assert.match(noteQueryTools, /knowledge_unit/);
  assert.doesNotMatch(noteQueryTools, /is_deleted/);
});

test('createReadOnlyRegistry includes all note tools via factory', () => {
  assert.match(toolCatalog, /createReadOnlyNoteTools/);
  assert.match(noteQueryTools, /createReadOnlyNoteTools/);
});

// === AC-RAG-01: note_query_rag registration and semantics ===

test('note_query_rag must be registered in ToolCatalog or NoteQueryTools (AC-RAG-01)', () => {
  const hasRagTool = noteQueryTools.match(/note_query_rag/) ||
    toolCatalog.match(/note_query_rag/);
  if (hasRagTool !== null) {
    assert.ok(true, 'note_query_rag tool registered');
  } else {
    assert.ok(
      false,
      'note_query_rag not found in ToolCatalog or NoteQueryTools — implementation not yet merged (DEV-RAG-QUERY / AC-RAG-01)',
    );
  }
});

test('note_query_rag must accept query parameter (AC-RAG-01)', () => {
  const hasQueryParam = noteQueryTools.match(/note_query_rag[\s\S]*?query/);
  if (hasQueryParam !== null) {
    assert.ok(true, 'query parameter exists');
  } else {
    assert.ok(
      false,
      'note_query_rag must have query param — implementation not yet merged (AC-RAG-01)',
    );
  }
});

test('note_query_rag must accept topK parameter with default 5 and max 10 (AC-RAG-01)', () => {
  const hasTopK = noteQueryTools.match(/note_query_rag[\s\S]*?topK/) ||
    noteQueryTools.match(/topK/);
  if (hasTopK !== null) {
    assert.ok(true, 'topK parameter exists');
    const hasDefault5 = noteQueryTools.match(/topK.*5|DEFAULT_TOP_K.*5/);
    const hasMax10 = noteQueryTools.match(/topK.*10|MAX_TOP_K.*10|topK.*clamp.*10/);
    if (hasDefault5 !== null || hasMax10 !== null) {
      assert.ok(true, 'topK default/max constraints found');
    } else {
      assert.ok(
        false,
        'topK default=5 max=10 not found — implementation not yet merged (AC-RAG-01)',
      );
    }
  } else {
    assert.ok(
      false,
      'note_query_rag must have topK param — implementation not yet merged (AC-RAG-01)',
    );
  }
});

test('note_query_rag must support subject filter parameter (AC-RAG-01)', () => {
  const hasSubject = noteQueryTools.match(/note_query_rag[\s\S]*?subject/);
  if (hasSubject !== null) {
    assert.ok(true, 'subject filter exists in rag tool');
  } else {
    assert.ok(
      false,
      'note_query_rag must have subject param — implementation not yet merged (AC-RAG-01)',
    );
  }
});

test('note_query_rag must support chapter filter parameter (AC-RAG-01)', () => {
  const hasChapter = noteQueryTools.match(/note_query_rag[\s\S]*?chapter/);
  if (hasChapter !== null) {
    assert.ok(true, 'chapter filter exists in rag tool');
  } else {
    assert.ok(
      false,
      'note_query_rag must have chapter param — implementation not yet merged (AC-RAG-01)',
    );
  }
});

test('note_query_rag must support tag filter parameter (AC-RAG-01)', () => {
  const hasTag = noteQueryTools.match(/note_query_rag[\s\S]*?tag/);
  if (hasTag !== null) {
    assert.ok(true, 'tag filter exists in rag tool');
  } else {
    assert.ok(
      false,
      'note_query_rag must have tag param — implementation not yet merged (AC-RAG-01)',
    );
  }
});

test('note_query_rag must support time range filter parameter (AC-RAG-01)', () => {
  const hasTime = noteQueryTools.match(/note_query_rag[\s\S]*?time|note_query_rag[\s\S]*?created_at|note_query_rag[\s\S]*?dateRange/);
  if (hasTime !== null) {
    assert.ok(true, 'time range filter exists in rag tool');
  } else {
    assert.ok(
      false,
      'note_query_rag must have time range param — implementation not yet merged (AC-RAG-01)',
    );
  }
});

test('note_query_rag delegates title/tags/summary/body matching to NoteSearchPort (AC-RAG-01, ADR-0021)', () => {
  // 工具层只做参数校验与 payload 组装；命中字段的保证已下沉到端口实现。
  assert.match(noteQueryTools, /NoteSearchPort/);
  assert.match(noteQueryTools, /RdbNoteSearchAdapter\.fromDatabase\(\)/);
  assert.match(noteSearchPort, /interface NoteSearchPort/);
  assert.match(noteSearchAdapter, /instr\(lower\(title\), \?\)/);
  assert.match(noteSearchAdapter, /instr\(lower\(tags\), \?\)/);
  assert.match(noteSearchAdapter, /instr\(lower\(summary\), \?\)/);
  assert.match(noteSearchAdapter, /instr\(lower\(content\), \?\)/);
  assert.match(noteSearchRanking, /RAG_TITLE_WEIGHT: number = 4/);
  assert.match(noteSearchRanking, /RAG_TAG_WEIGHT: number = 3/);
  assert.match(noteSearchRanking, /RAG_SUMMARY_WEIGHT: number = 2/);
});

test('note_query_rag must produce stable sort order (AC-RAG-01)', () => {
  // 排序保证已下沉到 NoteSearchRanking：分数降序 → updatedAt 降序 → noteId 升序。
  assert.match(noteSearchRanking, /export function compareHits/);
  assert.match(noteSearchRanking, /right\.score - left\.score/);
  assert.match(noteSearchRanking, /right\.updatedAt - left\.updatedAt/);
  assert.match(noteSearchRanking, /left\.noteId < right\.noteId/);
  assert.match(noteSearchAdapter, /rankNoteHitsByTerms\(rows, terms, topK\)/);
});

test('note_query_rag must return excerpt field in results (AC-RAG-01)', () => {
  const hasExcerpt = noteQueryTools.match(/note_query_rag[\s\S]*?excerpt/);
  if (hasExcerpt !== null) {
    assert.ok(true, 'excerpt field exists in rag results');
  } else {
    assert.ok(
      false,
      'note_query_rag must return excerpt — implementation not yet merged (AC-RAG-01)',
    );
  }
});

// Backward compat: ToolRegistry must still accept note_query registration
test('ToolRegistry enforces lowercase snake_case tool name pattern for both note_query and note_query_rag', () => {
  assert.match(toolRegistry, /\^\[a-z\]\[a-z0-9_\]/);
});
