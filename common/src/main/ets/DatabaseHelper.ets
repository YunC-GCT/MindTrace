// MindTrace - 数据库初始化工具
// 责任: Z
// 创建: 2026-07-14 — 精简拍照链 RDB 基础设施
// 更新: 2026-07-15 — 新增 study_plan 表 (学习计划)

import { relationalStore } from "@kit.ArkData";
import { BusinessError } from "@kit.BasicServicesKit";

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: "MindTrace.db",
  securityLevel: relationalStore.SecurityLevel.S1,
};

const DB_SCHEMA_VERSION: number = 10;

const SQL_CREATE_KNOWLEDGE: string = `
CREATE TABLE IF NOT EXISTS knowledge_unit (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT "",
  summary TEXT NOT NULL DEFAULT "",
  tags TEXT NOT NULL DEFAULT "[]",
  subject TEXT NOT NULL DEFAULT "",
  category TEXT NOT NULL DEFAULT "",
  chapter TEXT NOT NULL DEFAULT "",
  difficulty INTEGER NOT NULL DEFAULT 1,
  source TEXT NOT NULL DEFAULT "",
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  review_status TEXT NOT NULL DEFAULT "new",
  next_review_at INTEGER NOT NULL DEFAULT 0,
  interval_days INTEGER NOT NULL DEFAULT 0,
  ease_factor REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0,
  prerequisites TEXT NOT NULL DEFAULT "[]",
  related TEXT NOT NULL DEFAULT "[]",
  embedding TEXT NOT NULL DEFAULT "[]",
  user_id TEXT NOT NULL DEFAULT "",
  version INTEGER NOT NULL DEFAULT 1
)`;

const SQL_CREATE_STUDY_PLAN: string = `
CREATE TABLE IF NOT EXISTS study_plan (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT "",
  is_done INTEGER NOT NULL DEFAULT 0,
  priority INTEGER NOT NULL DEFAULT 2,
  linked_note_id TEXT NOT NULL DEFAULT "",
  created_at INTEGER NOT NULL DEFAULT 0,
  due_date INTEGER NOT NULL DEFAULT 0
)`;

const SQL_CREATE_NOTE_REVISION: string = `
CREATE TABLE IF NOT EXISTS note_revision (
  note_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT "",
  summary TEXT NOT NULL DEFAULT "",
  tags TEXT NOT NULL DEFAULT "[]",
  subject TEXT NOT NULL DEFAULT "",
  category TEXT NOT NULL DEFAULT "",
  chapter TEXT NOT NULL DEFAULT "",
  difficulty INTEGER NOT NULL DEFAULT 1,
  source TEXT NOT NULL DEFAULT "",
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  review_status TEXT NOT NULL DEFAULT "new",
  next_review_at INTEGER NOT NULL DEFAULT 0,
  interval_days INTEGER NOT NULL DEFAULT 0,
  ease_factor REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0,
  prerequisites TEXT NOT NULL DEFAULT "[]",
  related TEXT NOT NULL DEFAULT "[]",
  embedding TEXT NOT NULL DEFAULT "[]",
  user_id TEXT NOT NULL DEFAULT "",
  generation_metadata TEXT NOT NULL DEFAULT "",
  revised_at INTEGER NOT NULL,
  PRIMARY KEY (note_id, version)
)`;

const SQL_CREATE_CHAT_MESSAGE: string = `
CREATE TABLE IF NOT EXISTS chat_message (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT "",
  created_at INTEGER NOT NULL
)`;

const SQL_CREATE_AGENT_MEMORY: string = `
CREATE TABLE IF NOT EXISTS agent_memory (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  type TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT "",
  source TEXT NOT NULL DEFAULT "",
  used INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

const SQL_CREATE_NOTE_GENERATION_RUN: string = `
CREATE TABLE IF NOT EXISTS note_generation_run (
  id TEXT PRIMARY KEY,
  route TEXT NOT NULL,
  status TEXT NOT NULL,
  instruction TEXT NOT NULL DEFAULT '',
  source_count INTEGER NOT NULL DEFAULT 0,
  token_budget INTEGER NOT NULL DEFAULT 0,
  best_checkpoint_id TEXT NOT NULL DEFAULT '',
  stop_reason TEXT NOT NULL DEFAULT '',
  issue_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;
const SQL_CREATE_NOTE_GENERATION_SOURCE: string = `
CREATE TABLE IF NOT EXISTS note_generation_source (
  id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  origin_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  fingerprint TEXT NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY (run_id, id)
)`;
const SQL_CREATE_NOTE_GENERATION_CHECKPOINT: string = `
CREATE TABLE IF NOT EXISTS note_generation_checkpoint (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  iteration INTEGER NOT NULL,
  stage TEXT NOT NULL,
  parent_id TEXT NOT NULL DEFAULT '',
  candidate_hash TEXT NOT NULL,
  document_json TEXT NOT NULL,
  accepted INTEGER NOT NULL DEFAULT 0,
   issue_codes TEXT NOT NULL DEFAULT '[]',
    outline_json TEXT NOT NULL DEFAULT '',
    evidence_json TEXT NOT NULL DEFAULT '',
    verification_json TEXT NOT NULL DEFAULT '',
    issue_fingerprint TEXT NOT NULL DEFAULT '',
    coverage_json TEXT NOT NULL DEFAULT '',
    token_cost INTEGER NOT NULL DEFAULT 0,
    change_scope REAL NOT NULL DEFAULT 0,
    decision TEXT NOT NULL DEFAULT 'rejected',
    created_at INTEGER NOT NULL
 )`;
const SQL_CREATE_NOTE_GENERATION_COMMIT: string = `
CREATE TABLE IF NOT EXISTS note_generation_commit (
  commit_key TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  checkpoint_id TEXT NOT NULL,
  note_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  source_ids TEXT NOT NULL DEFAULT '[]',
  candidate_json TEXT NOT NULL DEFAULT '',
  committed_at INTEGER NOT NULL,
  generation_metadata TEXT NOT NULL DEFAULT ''
 )`;
const SQL_CREATE_NOTE_GENERATION_LOG: string = `
CREATE TABLE IF NOT EXISTS note_generation_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL,
  event TEXT NOT NULL,
  checkpoint_id TEXT NOT NULL DEFAULT '',
    issue_count INTEGER NOT NULL DEFAULT 0,
    source_count INTEGER NOT NULL DEFAULT 0,
    round INTEGER NOT NULL DEFAULT 0,
    stop_reason TEXT NOT NULL DEFAULT '',
    rollback INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
 )`;

const SQL_CREATE_KG_EDGE: string = `
CREATE TABLE IF NOT EXISTS kg_edge (
  id TEXT PRIMARY KEY,
  from_unit_id TEXT NOT NULL,
  to_unit_id TEXT NOT NULL,
  relation_type TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  status TEXT NOT NULL DEFAULT 'accepted',
  confidence REAL NOT NULL DEFAULT 1.0,
  weight REAL NOT NULL DEFAULT 1.0,
  reason TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  version INTEGER NOT NULL DEFAULT 1
)`;

const SQL_CREATE_RAG_CHUNK: string = `
CREATE TABLE IF NOT EXISTS rag_chunk (
  id TEXT PRIMARY KEY,
  unit_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL DEFAULT '',
  token_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

const SQL_CREATE_RAG_EMBEDDING: string = `
CREATE TABLE IF NOT EXISTS rag_embedding (
  id TEXT PRIMARY KEY,
  chunk_id TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT '',
  model TEXT NOT NULL DEFAULT '',
  dimension INTEGER NOT NULL DEFAULT 0,
  metric TEXT NOT NULL DEFAULT 'cosine',
  vector_json TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

const SQL_INDEX_KNOWLEDGE_CREATED: string =
  "CREATE INDEX IF NOT EXISTS idx_knowledge_unit_created_at ON knowledge_unit(created_at)";
const SQL_INDEX_KNOWLEDGE_REVIEW: string =
  "CREATE INDEX IF NOT EXISTS idx_knowledge_unit_review_status ON knowledge_unit(review_status)";
const SQL_INDEX_NOTE_REVISION_NOTE: string =
  "CREATE INDEX IF NOT EXISTS idx_note_revision_note ON note_revision(note_id, version)";
const SQL_INDEX_STUDY_PLAN_DONE: string =
  "CREATE INDEX IF NOT EXISTS idx_study_plan_is_done ON study_plan(is_done)";
const SQL_INDEX_CHAT_MESSAGE_SESSION_CREATED: string =
  "CREATE INDEX IF NOT EXISTS idx_chat_message_session_created ON chat_message(session_id, created_at)";
const SQL_INDEX_AGENT_MEMORY_PENDING: string =
  "CREATE INDEX IF NOT EXISTS idx_agent_memory_pending ON agent_memory(session_id, type, used, created_at)";
const SQL_INDEX_AGENT_MEMORY_SUMMARY: string =
  "CREATE INDEX IF NOT EXISTS idx_agent_memory_summary ON agent_memory(session_id, type, created_at)";
const SQL_INDEX_NOTE_GENERATION_RUN_STATUS: string =
  "CREATE INDEX IF NOT EXISTS idx_note_generation_run_status ON note_generation_run(status, updated_at)";
const SQL_INDEX_NOTE_GENERATION_LOG_RUN: string =
  "CREATE INDEX IF NOT EXISTS idx_note_generation_log_run ON note_generation_log(run_id, created_at)";
const SQL_INDEX_KG_EDGE_FROM: string =
  "CREATE INDEX IF NOT EXISTS idx_kg_edge_from ON kg_edge(from_unit_id)";
const SQL_INDEX_KG_EDGE_TO: string =
  "CREATE INDEX IF NOT EXISTS idx_kg_edge_to ON kg_edge(to_unit_id)";
const SQL_INDEX_KG_EDGE_STATUS: string =
  "CREATE INDEX IF NOT EXISTS idx_kg_edge_status ON kg_edge(status)";
const SQL_INDEX_KG_EDGE_RELATION: string =
  "CREATE UNIQUE INDEX IF NOT EXISTS uq_kg_edge_relation ON kg_edge(from_unit_id, to_unit_id, relation_type)";
const SQL_INDEX_RAG_CHUNK_UNIT: string =
  "CREATE INDEX IF NOT EXISTS idx_rag_chunk_unit ON rag_chunk(unit_id, chunk_index)";
const SQL_INDEX_RAG_EMBEDDING_CHUNK: string =
  "CREATE INDEX IF NOT EXISTS idx_rag_embedding_chunk ON rag_embedding(chunk_id)";

const SQL_MIGRATE_KNOWLEDGE_SUBJECT: string =
  "ALTER TABLE knowledge_unit ADD COLUMN subject TEXT NOT NULL DEFAULT \"\"";
const SQL_MIGRATE_KNOWLEDGE_CATEGORY: string =
  "ALTER TABLE knowledge_unit ADD COLUMN category TEXT NOT NULL DEFAULT \"\"";
const SQL_MIGRATE_KNOWLEDGE_CHAPTER: string =
  "ALTER TABLE knowledge_unit ADD COLUMN chapter TEXT NOT NULL DEFAULT \"\"";
const SQL_MIGRATE_GENERATION_SOURCE_IDS: string =
  "ALTER TABLE note_generation_run ADD COLUMN source_ids TEXT NOT NULL DEFAULT '[]'";
const SQL_MIGRATE_GENERATION_SOURCE_SUMMARY: string =
  "ALTER TABLE note_generation_run ADD COLUMN source_summary TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_GENERATION_PENDING_SOURCE_IDS: string =
  "ALTER TABLE note_generation_run ADD COLUMN pending_source_ids TEXT NOT NULL DEFAULT '[]'";
const SQL_MIGRATE_GENERATION_COMMIT_METADATA: string =
  "ALTER TABLE note_generation_commit ADD COLUMN generation_metadata TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHECKPOINT_OUTLINE: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN outline_json TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHECKPOINT_EVIDENCE: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN evidence_json TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHECKPOINT_VERIFICATION: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN verification_json TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHECKPOINT_ISSUE_FINGERPRINT: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN issue_fingerprint TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHECKPOINT_COVERAGE: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN coverage_json TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHECKPOINT_TOKEN_COST: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN token_cost INTEGER NOT NULL DEFAULT 0";
const SQL_MIGRATE_CHECKPOINT_CHANGE_SCOPE: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN change_scope REAL NOT NULL DEFAULT 0";
const SQL_MIGRATE_CHECKPOINT_DECISION: string =
  "ALTER TABLE note_generation_checkpoint ADD COLUMN decision TEXT NOT NULL DEFAULT 'rejected'";
const SQL_MIGRATE_GENERATION_LOG_ROUND: string =
  "ALTER TABLE note_generation_log ADD COLUMN round INTEGER NOT NULL DEFAULT 0";
const SQL_MIGRATE_GENERATION_LOG_STOP_REASON: string =
  "ALTER TABLE note_generation_log ADD COLUMN stop_reason TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_GENERATION_LOG_ROLLBACK: string =
  "ALTER TABLE note_generation_log ADD COLUMN rollback INTEGER NOT NULL DEFAULT 0";
const SQL_BACKFILL_NOTE_REVISION: string = `
INSERT OR IGNORE INTO note_revision (
  note_id, version, title, content, summary, tags, subject, category, chapter,
  difficulty, source, created_at, updated_at, review_status, next_review_at,
  interval_days, ease_factor, repetitions, prerequisites, related, embedding,
  user_id, generation_metadata, revised_at
)
SELECT
  id, version, title, content, summary, tags, subject, category, chapter,
  difficulty, source, created_at, updated_at, review_status, next_review_at,
  interval_days, ease_factor, repetitions, prerequisites, related, embedding,
  user_id, "", updated_at
FROM knowledge_unit`;

export class DatabaseHelper {
  private static store: relationalStore.RdbStore | null = null;

  static async init(context: Context): Promise<relationalStore.RdbStore> {
    if (DatabaseHelper.store !== null) {
      return DatabaseHelper.store;
    }
    return new Promise<relationalStore.RdbStore>((resolve, reject) => {
      relationalStore.getRdbStore(context, STORE_CONFIG, (err: BusinessError, store: relationalStore.RdbStore) => {
        if (err) {
          reject(new Error("RDB init failed: " + err.message));
          return;
        }
        DatabaseHelper.ensureSchema(store).then(() => {
          DatabaseHelper.store = store;
          resolve(store);
        }).catch((schemaErr: Error) => {
          reject(schemaErr);
        });
      });
    });
  }

  static getStore(): relationalStore.RdbStore | null {
    return DatabaseHelper.store;
  }

  private static async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
    const statements: string[] = [
      SQL_CREATE_KNOWLEDGE,
      SQL_CREATE_NOTE_REVISION,
      SQL_CREATE_STUDY_PLAN,
      SQL_CREATE_CHAT_MESSAGE,
      SQL_CREATE_AGENT_MEMORY,
      SQL_CREATE_NOTE_GENERATION_RUN,
      SQL_CREATE_NOTE_GENERATION_SOURCE,
      SQL_CREATE_NOTE_GENERATION_CHECKPOINT,
      SQL_CREATE_NOTE_GENERATION_COMMIT,
      SQL_CREATE_NOTE_GENERATION_LOG,
      SQL_CREATE_KG_EDGE,
      SQL_CREATE_RAG_CHUNK,
      SQL_CREATE_RAG_EMBEDDING,
      SQL_INDEX_KNOWLEDGE_CREATED,
      SQL_INDEX_KNOWLEDGE_REVIEW,
      SQL_INDEX_NOTE_REVISION_NOTE,
      SQL_INDEX_STUDY_PLAN_DONE,
      SQL_INDEX_CHAT_MESSAGE_SESSION_CREATED,
      SQL_INDEX_AGENT_MEMORY_PENDING,
      SQL_INDEX_AGENT_MEMORY_SUMMARY,
      SQL_INDEX_NOTE_GENERATION_RUN_STATUS,
      SQL_INDEX_NOTE_GENERATION_LOG_RUN,
      SQL_INDEX_KG_EDGE_FROM,
      SQL_INDEX_KG_EDGE_TO,
      SQL_INDEX_KG_EDGE_STATUS,
      SQL_INDEX_KG_EDGE_RELATION,
      SQL_INDEX_RAG_CHUNK_UNIT,
      SQL_INDEX_RAG_EMBEDDING_CHUNK,
    ];

    for (const sql of statements) {
      await DatabaseHelper.executeSql(store, sql);
    }

    const hasSubject: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "subject");
    if (!hasSubject) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_KNOWLEDGE_SUBJECT);
    }
    const hasCategory: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "category");
    if (!hasCategory) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_KNOWLEDGE_CATEGORY);
    }
    const hasChapter: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "chapter");
    if (!hasChapter) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_KNOWLEDGE_CHAPTER);
    }
    const hasSourceIds: boolean = await DatabaseHelper.hasColumn(store, "note_generation_run", "source_ids");
    if (!hasSourceIds) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_SOURCE_IDS);
    }
    const hasSourceSummary: boolean = await DatabaseHelper.hasColumn(store, "note_generation_run", "source_summary");
    if (!hasSourceSummary) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_SOURCE_SUMMARY);
    }
    const hasPendingSourceIds: boolean = await DatabaseHelper.hasColumn(store, "note_generation_run", "pending_source_ids");
    if (!hasPendingSourceIds) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_PENDING_SOURCE_IDS);
    }
    const hasCommitMetadata: boolean = await DatabaseHelper.hasColumn(store, "note_generation_commit", "generation_metadata");
    if (!hasCommitMetadata) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_COMMIT_METADATA);
    }
    const hasOutlineJson: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "outline_json");
    if (!hasOutlineJson) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_OUTLINE);
    }
    const hasEvidenceJson: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "evidence_json");
    if (!hasEvidenceJson) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_EVIDENCE);
    }
    const hasVerificationJson: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "verification_json");
    if (!hasVerificationJson) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_VERIFICATION);
    }
    const hasIssueFingerprint: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "issue_fingerprint");
    if (!hasIssueFingerprint) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_ISSUE_FINGERPRINT);
    }
    const hasCoverage: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "coverage_json");
    if (!hasCoverage) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_COVERAGE);
    }
    const hasTokenCost: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "token_cost");
    if (!hasTokenCost) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_TOKEN_COST);
    }
    const hasChangeScope: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "change_scope");
    if (!hasChangeScope) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_CHANGE_SCOPE);
    }
    const hasDecision: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "decision");
    if (!hasDecision) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_DECISION);
    }
    const hasLogRound: boolean = await DatabaseHelper.hasColumn(store, "note_generation_log", "round");
    if (!hasLogRound) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_LOG_ROUND);
    }
    const hasLogStopReason: boolean = await DatabaseHelper.hasColumn(store, "note_generation_log", "stop_reason");
    if (!hasLogStopReason) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_LOG_STOP_REASON);
    }
    const hasLogRollback: boolean = await DatabaseHelper.hasColumn(store, "note_generation_log", "rollback");
    if (!hasLogRollback) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_LOG_ROLLBACK);
    }

    await DatabaseHelper.executeSql(store, SQL_BACKFILL_NOTE_REVISION);

    if (store.version < DB_SCHEMA_VERSION) {
      store.version = DB_SCHEMA_VERSION;
    }
  }

  private static async executeSql(store: relationalStore.RdbStore, sql: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      store.executeSql(sql, [], (err: BusinessError) => {
        if (err) {
          reject(new Error("DatabaseHelper.executeSql failed: " + err.message));
          return;
        }
        resolve();
      });
    });
  }

  private static async hasColumn(
    store: relationalStore.RdbStore,
    tableName: string,
    columnName: string,
  ): Promise<boolean> {
    return new Promise<boolean>((resolve, reject) => {
      store.querySql("PRAGMA table_info(" + tableName + ")", [], (err: BusinessError, rs: relationalStore.ResultSet) => {
        if (err) {
          reject(new Error("DatabaseHelper.hasColumn failed: " + err.message));
          return;
        }
        let found: boolean = false;
        if (rs.goToFirstRow()) {
          do {
            const name: string = rs.getString(rs.getColumnIndex("name"));
            if (name === columnName) {
              found = true;
              break;
            }
          } while (rs.goToNextRow());
        }
        rs.close();
        resolve(found);
      });
    });
  }

  private static async executeAddColumn(store: relationalStore.RdbStore, sql: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      store.executeSql(sql, [], (err: BusinessError) => {
        if (err) {
          if (DatabaseHelper.isDuplicateColumnError(err.message)) {
            resolve();
            return;
          }
          reject(new Error("DatabaseHelper.executeAddColumn failed: " + err.message));
          return;
        }
        resolve();
      });
    });
  }

  private static isDuplicateColumnError(message: string): boolean {
    const normalized: string = message.toLowerCase();
    return normalized.includes("duplicate column")
      || normalized.includes("already exists")
      || normalized.includes("duplicate")
      || normalized.includes("exists")
      || normalized.includes("重复")
      || normalized.includes("已存在")
      || normalized.includes("已经存在");
  }
}
