import test from 'node:test';
import assert from 'node:assert/strict';

import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

function relation(overrides = {}) {
  return {
    id: overrides.id ?? 'edge-a-b',
    from_unit_id: overrides.fromUnitId ?? 'A',
    to_unit_id: overrides.toUnitId ?? 'B',
    relation_type: overrides.relationType ?? 'prerequisite',
    source: overrides.source ?? 'manual',
    status: overrides.status ?? 'accepted',
    confidence: overrides.confidence ?? 0.9,
    weight: overrides.weight ?? 1,
    reason: overrides.reason ?? 'accepted prerequisite',
    created_at: overrides.createdAt ?? 1,
    updated_at: overrides.updatedAt ?? 2,
    version: overrides.version ?? 1,
  };
}

function resultSet(rows, columns) {
  let index = -1;
  return {
    goToFirstRow() {
      index = rows.length > 0 ? 0 : -1;
      return index >= 0;
    },
    goToNextRow() {
      index += 1;
      return index < rows.length;
    },
    getColumnIndex(name) {
      return columns.indexOf(name);
    },
    getString(columnIndex) {
      return String(rows[index][columns[columnIndex]] ?? '');
    },
    getLong(columnIndex) {
      return Number(rows[index][columns[columnIndex]] ?? 0);
    },
    getDouble(columnIndex) {
      return Number(rows[index][columns[columnIndex]] ?? 0);
    },
    close() {},
  };
}

function storeFor({ liveIds, edges }) {
  const relationColumns = [
    'id', 'from_unit_id', 'to_unit_id', 'relation_type', 'source', 'status',
    'confidence', 'weight', 'reason', 'created_at', 'updated_at', 'version',
  ];
  const calls = [];
  return {
    calls,
    querySql(sql, bindArgs, callback) {
      calls.push({ sql, bindArgs: [...bindArgs] });
      if (sql.includes('FROM knowledge_unit')) {
        const ids = [...liveIds]
          .filter((id) => bindArgs.includes(id))
          .sort()
          .map((id) => ({ id }));
        callback(null, resultSet(ids, ['id']));
        return;
      }
      assert.match(sql, /status = 'accepted'/);
      assert.match(sql, /relation_type = 'prerequisite'/);
      assert.match(sql, /to_unit_id IN/);
      assert.doesNotMatch(sql, /from_unit_id IN/);
      const rows = edges
        .filter((edge) => edge.status === 'accepted')
        .filter((edge) => edge.relation_type === 'prerequisite')
        .filter((edge) => bindArgs.includes(edge.to_unit_id))
        .sort((a, b) => `${a.from_unit_id}:${a.to_unit_id}:${a.id}`.localeCompare(`${b.from_unit_id}:${b.to_unit_id}:${b.id}`));
      callback(null, resultSet(rows, relationColumns));
    },
  };
}

function loadDao() {
  return loadNoteReviewEtsModule('entry/src/main/ets/database/KnowledgeRelationDao.ets', {
    mocks: {
      '@kit.ArkData': {
        relationalStore: {
          RdbPredicates: class RdbPredicates {
            constructor(table) { this.table = table; }
            equalTo() { return this; }
            orderByDesc() { return this; }
          },
        },
      },
      common: {},
    },
  });
}

test('KnowledgeRelationDao expands accepted prerequisites in A-to-B direction through cycles', async () => {
  const { KnowledgeRelationDao } = loadDao();
  const store = storeFor({
    liveIds: new Set(['A', 'B', 'C', 'D', 'E', 'F']),
    edges: [
      relation({ id: 'edge-a-b', fromUnitId: 'A', toUnitId: 'B' }),
      relation({ id: 'edge-c-a', fromUnitId: 'C', toUnitId: 'A' }),
      relation({ id: 'edge-b-c', fromUnitId: 'B', toUnitId: 'C' }),
      relation({ id: 'edge-d-b-related', fromUnitId: 'D', toUnitId: 'B', relationType: 'related' }),
      relation({ id: 'edge-e-b-pending', fromUnitId: 'E', toUnitId: 'B', status: 'pending' }),
      relation({ id: 'edge-f-b-derived', fromUnitId: 'F', toUnitId: 'B', relationType: 'derived' }),
    ],
  });

  const expansion = await new KnowledgeRelationDao(store).expandAcceptedPrerequisites(['B'], {
    maxDepth: 99,
    maxNodes: 99,
    maxEdges: 99,
  });

  assert.deepEqual(JSON.parse(JSON.stringify(expansion.nodes.map((node) => `${node.unitId}:${node.depth}`))), ['B:0', 'A:1', 'C:2']);
  assert.deepEqual(JSON.parse(JSON.stringify(expansion.edges.map((edge) => edge.id))), ['edge-a-b', 'edge-c-a']);
  assert.equal(expansion.truncated, false);
  assert.equal(expansion.edges.some((edge) => edge.id === 'edge-b-c'), false);
  assert.equal(expansion.edges.some((edge) => edge.relationType !== 'prerequisite'), false);
});

test('KnowledgeRelationDao marks prerequisite expansion truncated at node and edge caps', async () => {
  const { KnowledgeRelationDao } = loadDao();
  const store = storeFor({
    liveIds: new Set(['A', 'B', 'C']),
    edges: [
      relation({ id: 'edge-a-b', fromUnitId: 'A', toUnitId: 'B' }),
      relation({ id: 'edge-c-a', fromUnitId: 'C', toUnitId: 'A' }),
    ],
  });

  const expansion = await new KnowledgeRelationDao(store).expandAcceptedPrerequisites(['B'], {
    maxDepth: 2,
    maxNodes: 2,
    maxEdges: 1,
  });

  assert.deepEqual(JSON.parse(JSON.stringify(expansion.nodes.map((node) => node.unitId))), ['B', 'A']);
  assert.deepEqual(JSON.parse(JSON.stringify(expansion.edges.map((edge) => edge.id))), ['edge-a-b']);
  assert.equal(expansion.truncated, true);
});
