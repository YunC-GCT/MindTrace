// scripts/arkts-lint/tests/viewmodel-load-backfill.test.mjs
// T4 follow-up (2026-09-08): VM.load() legacy data migration + apiKey backfill
// 范围:
//   - VM.load() 在还原 customVendors 后,对每个 v:
//     - 若 v.id === undefined 且 cachedVendorId startsWith('custom', set v.id = cachedVendorId(legacy data)
//   - VM.load() 在还原 vendorApiKeys 后,for v of customVendors:
//     - 若 this.vendorApiKeys[v.id] 非空且 !v.apiKey,backfill v.apiKey

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const TARGET_FILE = resolve(root, 'entry/src/main/ets/viewmodels/AiSettingsViewModel.ets');
const src = readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');

test('T4: VM.load() migrates legacy customVendors without id (assign from cachedVendorId)', () => {
  // source-level 匹配 load() 体内含 legacy migration
  assert.match(
    src,
    /load[\s\S]*?v\.id\s*===\s*undefined[\s\S]*?v\.id\s*=\s*this\.vendorId/,
    'VM.load() must migrate legacy customVendors: when v.id is undefined, assign from cachedVendorId'
  );
});

test('T4: VM.load() backfills customVendors[i].apiKey from vendorApiKeys', () => {
  // source-level 匹配 backfill loop
  assert.match(
    src,
    /load[\s\S]*?vendorApiKeys\[\s*v\.id\s*\][\s\S]*?v\.apiKey\s*=\s*stored/,
    'VM.load() must backfill customVendors[i].apiKey from this.vendorApiKeys[v.id]'
  );
});
