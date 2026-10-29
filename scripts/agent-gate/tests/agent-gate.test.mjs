import test from 'node:test';
import assert from 'node:assert/strict';
import { hasBom, hasFileHeader, boundaryViolations, parseLintSummary, parseLintJson } from '../index.mjs';

test('hasBom detects UTF-8 BOM only', () => {
  assert.equal(hasBom(Buffer.from([0xef, 0xbb, 0xbf, 0x61])), true);
  assert.equal(hasBom(Buffer.from('abc')), false);
  assert.equal(hasBom(Buffer.from([0x61, 0x62])), false);
});

test('hasFileHeader requires both 路径 and 职责 in the first 30 lines', () => {
  assert.equal(hasFileHeader('/**\n * 路径: a.ets\n * 职责: demo\n */\n'), true);
  assert.equal(hasFileHeader('/**\n * 路径: a.ets\n */\n'), false);
  assert.equal(hasFileHeader('// nothing\n'.repeat(40) + '路径: x\n职责: y\n'), false);
});

test('agents must not import entry', () => {
  const v = boundaryViolations('agents/src/main/ets/core/Dispatcher.ets', "import { X } from 'entry/src/main/ets/Index';\n");
  assert.equal(v.length, 1);
  assert.match(v[0], /must not import entry/);
});

test('pages/overlays must not import CaptureGraph or NoteDao directly', () => {
  const p = 'entry/src/main/ets/pages/HomePage.ets';
  assert.match(boundaryViolations(p, "import { CaptureGraph } from 'agents/src/main/ets/graph/CaptureGraph';")[0], /through a service/);
  assert.match(boundaryViolations(p, "import { NoteDao } from 'entry/src/main/ets/database/NoteDao';")[0], /through a service/);
  assert.equal(boundaryViolations(p, "import { AiService } from '../services/AiService';").length, 0);
});

test('common must not import agents or entry (no upward dependency)', () => {
  const p = 'common/src/main/ets/llm/LlmClient.ets';
  assert.match(boundaryViolations(p, "import { Dispatcher } from 'agents';\n")[0], /common must not import agents/);
  assert.match(boundaryViolations(p, "import { NoteDao } from 'entry/src/main/ets/database/NoteDao';\n")[0], /common must not import entry/);
  assert.equal(boundaryViolations(p, "import { hilog } from '@kit.PerformanceAnalysisKit';\n").length, 0);
});

test('database layer must not reach back into UI', () => {
  const p = 'entry/src/main/ets/database/NoteDao.ets';
  assert.match(boundaryViolations(p, "import { HomePage } from '../pages/HomePage';\n")[0], /database must not import pages/);
  assert.match(boundaryViolations(p, "import { NotesViewModel } from '../viewmodels/NotesViewModel';\n")[0], /database must not import viewmodels/);
  assert.equal(boundaryViolations(p, "import { relationalStore } from '@kit.ArkData';\n").length, 0);
});

test('agents may only use NetworkKit from the platform', () => {
  const p = 'agents/src/main/ets/core/Dispatcher.ets';
  assert.match(boundaryViolations(p, "import { http } from '@kit.NetworkKit';\n").length === 0 ? '' : 'x', /^$/);
  assert.match(boundaryViolations(p, "import { relationalStore } from '@kit.ArkData';\n")[0], /only @kit.NetworkKit/);
  assert.match(boundaryViolations(p, "import { fileIo } from '@ohos.file.fs';\n")[0], /only @kit.NetworkKit/);
});

test('parseLintSummary reads errors and warnings', () => {
  const out = 'Rules: 34\nErrors: 0\nWarnings: 446\n';
  assert.deepEqual(parseLintSummary(out), { errors: 0, warnings: 446 });
  assert.deepEqual(parseLintSummary('no summary'), { errors: null, warnings: null });
});

test('parseLintJson reads the JSON summary and falls back to text', () => {
  const json = JSON.stringify({ filesScanned: 522, totals: { errors: 0, warnings: 446 } });
  assert.deepEqual(parseLintJson(json), { errors: 0, warnings: 446, filesScanned: 522 });
  assert.deepEqual(parseLintJson('Errors: 2\nWarnings: 3'), { errors: 2, warnings: 3 });
  assert.deepEqual(parseLintJson('garbage'), { errors: null, warnings: null });
});
