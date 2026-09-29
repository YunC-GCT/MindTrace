import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const projectionPath = resolve(
  root,
  'entry/src/main/ets/pages/Review/GalaxyGraphProjection.ets',
);

async function loadProjection() {
  const source = readFileSync(projectionPath, 'utf8');
  const compiled = stripTypeScriptTypes(source, { mode: 'strip' });
  return import(`data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);
}

function planet(id, title, type = '概念') {
  return {
    id,
    note: { title, type },
    type,
    subject: '数学分析',
    chapter: '极限',
    color: '#FF5BE3B0',
    mastery: 0.75,
  };
}

test('projection includes built-in notes and filters invalid or wrong-note nodes', async () => {
  const { projectGalaxyGraph } = await loadProjection();
  const snapshot = projectGalaxyGraph([
    {
      subject: '数学分析',
      planets: [
        planet('unit-1', '极限定义'),
        planet('', '空 ID'),
        planet('galaxy_preview_demo', '预览数据'),
        planet('wrong-1', '错题', '错题'),
      ],
      links: [],
    },
  ]);

  assert.deepEqual(snapshot.nodes.map((node) => node.id), ['unit-1', 'galaxy_preview_demo']);
  assert.equal(snapshot.nodes[0].label, '极限定义');
  assert.deepEqual(snapshot.edges, []);
});

test('projection preserves accepted cross-subject links and removes invalid duplicates', async () => {
  const { projectGalaxyGraph } = await loadProjection();
  const analysis = planet('analysis-1', '极限定义');
  const algebra = {
    ...planet('algebra-1', '向量组'),
    subject: '线性代数',
    chapter: '向量空间',
  };
  const probability = {
    ...planet('probability-1', '随机变量'),
    subject: '概率论',
    chapter: '随机变量',
  };

  const snapshot = projectGalaxyGraph([
    {
      subject: analysis.subject,
      planets: [analysis],
      links: [
        { fromId: 'analysis-1', toId: 'algebra-1', type: 'prerequisite' },
        { fromId: 'analysis-1', toId: 'algebra-1', type: 'prerequisite' },
        { fromId: 'analysis-1', toId: 'probability-1', type: 'derived' },
        { fromId: 'analysis-1', toId: 'missing', type: 'related' },
      ],
    },
    {
      subject: algebra.subject,
      planets: [algebra],
      links: [
        { fromId: 'algebra-1', toId: 'probability-1', type: 'related' },
      ],
    },
    {
      subject: probability.subject,
      planets: [probability],
      links: [
        { fromId: 'probability-1', toId: 'algebra-1', type: 'related' },
      ],
    },
  ]);

  assert.deepEqual(snapshot.edges, [
    {
      id: 'prerequisite:analysis-1->algebra-1',
      fromId: 'analysis-1',
      toId: 'algebra-1',
      type: 'prerequisite',
    },
    {
      id: 'related:algebra-1<->probability-1',
      fromId: 'algebra-1',
      toId: 'probability-1',
      type: 'related',
    },
  ]);
});

test('view model supplies projection with accepted relations only', () => {
  const source = readFileSync(
    resolve(root, 'entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets'),
    'utf8',
  );
  assert.match(source, /queryAcceptedEdges\(\)/);
  assert.match(source, /relation\.status !== ["']accepted["']/);
});
