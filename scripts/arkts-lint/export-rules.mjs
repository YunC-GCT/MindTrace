#!/usr/bin/env node
/**
 * scripts/arkts-lint/export-rules.mjs
 *
 * Export the lint rule registry to a compact, agent-readable manifest:
 *   docs/style/arkts-rules.json
 *
 * Usage:
 *   node scripts/arkts-lint/export-rules.mjs           # write manifest
 *   node scripts/arkts-lint/export-rules.mjs --check   # fail if manifest is stale
 *
 * The manifest is generated, never hand-edited.
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadAllRules } from './rules/registry.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const OUT = join(REPO_ROOT, 'docs', 'style', 'arkts-rules.json');

export async function buildManifest() {
  const { rules, errors } = await loadAllRules(__dirname);
  if (errors.length > 0) {
    throw new Error(`rule registry errors:\n${errors.join('\n')}`);
  }
  const entries = rules
    .map((r) => ({
      id: r.id,
      code: r.code,
      severity: r.severity,
      title: r.title,
      fix: r.fixHint,
    }))
    .sort((a, b) => a.id.localeCompare(b.id));
  return {
    generatedFrom: 'scripts/arkts-lint/rules',
    doc: 'docs/style/arkts-1.1.md',
    checklist: 'docs/style/arkts-ai-coding.md',
    count: entries.length,
    rules: entries,
  };
}

function main() {
  const check = process.argv.includes('--check');
  buildManifest().then((manifest) => {
    const text = JSON.stringify(manifest, null, 2) + '\n';
    if (check) {
      if (!existsSync(OUT)) {
        console.error(`FAIL: ${relative(REPO_ROOT, OUT)} is missing; run node scripts/arkts-lint/export-rules.mjs`);
        process.exit(1);
      }
      const current = readFileSync(OUT, 'utf8');
      if (current !== text) {
        console.error(`FAIL: ${relative(REPO_ROOT, OUT)} is stale; run node scripts/arkts-lint/export-rules.mjs`);
        process.exit(1);
      }
      console.log(`OK: arkts-rules.json is current (${manifest.count} rules)`);
      return;
    }
    writeFileSync(OUT, text, 'utf8');
    console.log(`wrote ${relative(REPO_ROOT, OUT)} (${manifest.count} rules)`);
  }).catch((e) => {
    console.error(`FAIL: ${e.message}`);
    process.exit(1);
  });
}

main();
