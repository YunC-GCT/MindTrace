import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = resolve(import.meta.dirname, '../../..');
async function loadSeeder() {
  const source = readFileSync(resolve(root, 'entry/src/main/ets/services/GalaxyPreviewSeeder.ets'), 'utf8');
  const js = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
  return (await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'))).GalaxyPreviewSeeder;
}

// Persistent storage boundary. No UI, networking, or HarmonyOS runtime required.
class MemorySeedStore {
  failNextEdge = false;
  units = new Map();
  revisions = new Set();
  edges = new Map();
  completed = false;
  async isComplete() { return this.completed; }
  async markComplete() { this.completed = true; }
  async findUnit(id) { return this.units.get(id) ?? null; }
  async hasRevision(id) { return this.revisions.has(id); }
  async createUnit(unit) {
    if (this.units.has(unit.id)) throw new Error('duplicate');
    this.units.set(unit.id, structuredClone(unit));
    this.revisions.add(unit.id);
  }
  async hasRelation(edge) { return this.edges.has(edge.id); }
  async createRelation(edge) {
    if (this.failNextEdge) { this.failNextEdge = false; throw new Error('disk failure'); }
    this.edges.set(edge.id, structuredClone(edge));
  }
}

test('sample seeding makes the full note retrievable through persistent storage', async () => {
  const Seeder = await loadSeeder();
  const store = new MemorySeedStore();
  const seeder = new Seeder(store);
  await seeder.ensureSeeded([{ id: 'galaxy_preview_limit_definition', content: '公式 $$x^2$$' }], []);
  assert.equal((await store.findUnit('galaxy_preview_limit_definition')).content, '公式 $$x^2$$');
  assert.equal(await store.isComplete(), true);
});

test('concurrent and repeated imports preserve edited and deleted notes, including after restart', async () => {
  const Seeder = await loadSeeder();
  const store = new MemorySeedStore();
  store.units.set('edited', { id: 'edited', content: 'user edit' });
  store.revisions.add('deleted');
  const samples = ['edited', 'deleted', 'new'].map(id => ({ id, content: 'sample' }));
  const seeder = new Seeder(store);
  await Promise.all([seeder.ensureSeeded(samples, []), seeder.ensureSeeded(samples, [])]);
  store.units.delete('new');
  await new Seeder(store).ensureSeeded(samples, []);
  assert.equal((await store.findUnit('edited')).content, 'user edit');
  assert.equal(await store.findUnit('deleted'), null);
  assert.equal(await store.findUnit('new'), null);
});

test('valid edges persist, rejected edges stay rejected, and interrupted seeding can resume', async () => {
  const Seeder = await loadSeeder();
  const store = new MemorySeedStore();
  const samples = ['a', 'b'].map(id => ({ id, content: 'sample' }));
  const edges = [
    { id: 'valid', fromUnitId: 'a', toUnitId: 'b', status: 'accepted' },
    { id: 'missing', fromUnitId: 'a', toUnitId: 'missing', status: 'accepted' },
    { id: 'rejected', fromUnitId: 'b', toUnitId: 'a', status: 'accepted' },
  ];
  store.edges.set('rejected', { ...edges[2], status: 'rejected' });
  store.failNextEdge = true;
  const seeder = new Seeder(store);
  await assert.rejects(seeder.ensureSeeded(samples, edges), /disk failure/);
  assert.equal(await store.isComplete(), false);
  await seeder.ensureSeeded(samples, edges);
  assert.equal(store.edges.get('valid').status, 'accepted');
  assert.equal(store.edges.has('missing'), false);
  assert.equal(store.edges.get('rejected').status, 'rejected');
  assert.equal(await store.isComplete(), true);
});

test('all 11 built-in samples retain readable content, subjects and long formulas', async () => {
  const source = readFileSync(resolve(root, 'entry/src/main/ets/services/GalaxyPreviewData.ets'), 'utf8')
    .replace(/import\s+\{[^}]+\}\s+from\s+'common';/, '');
  const stubs = 'const DifficultyLevel = { MEDIUM: 2 }; const ReviewStatus = { LEARNING: "learning", REVIEW: "review", GRADUATED: "graduated", LAPSED: "lapsed" };\n';
  const js = ts.transpileModule(stubs + source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
  const { GalaxyPreviewData } = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
  const data = new GalaxyPreviewData();
  const Seeder = await loadSeeder();
  const store = new MemorySeedStore();
  const samples = data.units();
  await new Seeder(store).ensureSeeded(samples, data.relations(samples));
  assert.equal(store.units.size, 11);
  assert.equal(new Set(samples.map(unit => unit.id)).size, 11);
  assert.equal(samples.filter(unit => unit.subject === '数学分析').length, 7);
  assert.equal(samples.filter(unit => unit.subject === '线性代数').length, 4);
  assert.match((await store.findUnit('galaxy_preview_taylor_formula')).content, /\\sum_\{k=0\}/);
  assert.match((await store.findUnit('galaxy_preview_matrix_inverse')).content, /\\operatorname\{rank\}/);
  assert.ok(samples.every(unit => unit.content.trim().length > 0));
  assert.ok(store.edges.size > 0);
  assert.ok([...store.edges.values()].every(edge => store.units.has(edge.fromUnitId) && store.units.has(edge.toUnitId)));
});

test('both page loaders wait for durable samples and read details via RDB', () => {
  const read = path => readFileSync(resolve(root, path), 'utf8');
  const notes = read('entry/src/main/ets/viewmodels/NotesViewModel.ets');
  const galaxy = read('entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets');
  const adapter = read('entry/src/main/ets/services/GalaxyPreviewSeedService.ets');
  assert.match(notes, /await GalaxyPreviewSeedService.ensureSeeded\(context\)[\s\S]*await UiDataCacheService.loadNotesSnapshot/);
  assert.match(galaxy, /await GalaxyPreviewSeedService.ensureSeeded\(context\)[\s\S]*await this.loadPersistedGraph/);
  assert.doesNotMatch(galaxy, /findLoadedPreviewUnit|withPreviewUnits|withPreviewRelations/);
  assert.match(galaxy, /await new NoteDao\(store\).queryById\(id\)/);
  assert.match(adapter, /KnowledgeUnitWriteServiceFactory.create/);
  assert.match(adapter, /await this.writer.create\(unit\)/);
});
