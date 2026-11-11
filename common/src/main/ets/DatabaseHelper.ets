/**
 * DatabaseHelper.ets — 数据库初始化与 schema 迁移
 *
 * 路径: common/src/main/ets/DatabaseHelper.ets
 * 职责: 打开 MindTrace.db、建表/迁移到 schema v23、初始化 RDB 单例。
 * 依赖: @kit.ArkData (relationalStore)。
 */
// MindTrace - 数据库初始化工具
// 责任: Z
// 创建: 2026-07-14 — 精简拍照链 RDB 基础设施
// 更新: 2026-07-15 — 新增 study_plan 表 (学习计划)

import { relationalStore } from "@kit.ArkData";
import { BusinessError } from "@kit.BasicServicesKit";
import { extractMathSignature } from "./utils/MathSignature";

interface SignatureBackfillRow {
  id: string;
  title: string;
}

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: "MindTrace.db",
  securityLevel: relationalStore.SecurityLevel.S1,
};

const DB_SCHEMA_VERSION: number = 23;

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
  source_image_id TEXT NOT NULL DEFAULT "",
  source_region TEXT NOT NULL DEFAULT "",
  ocr_confidence REAL NOT NULL DEFAULT 0,
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
  signature TEXT NOT NULL DEFAULT "",
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
  message_key TEXT NOT NULL,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT "",
  run_id TEXT NOT NULL DEFAULT "",
  sequence INTEGER NOT NULL DEFAULT 0,
  origin TEXT NOT NULL DEFAULT "legacy",
  outcome TEXT NOT NULL DEFAULT "completed",
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
  context_budget_tokens INTEGER NOT NULL DEFAULT 0,
  best_checkpoint_id TEXT NOT NULL DEFAULT '',
  stop_reason TEXT NOT NULL DEFAULT '',
  issue_count INTEGER NOT NULL DEFAULT 0,
  origin_session_id TEXT NOT NULL DEFAULT '',
  parent_conversation_run_id TEXT NOT NULL DEFAULT '',
  clarification_json TEXT NOT NULL DEFAULT '',
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
  provenance_ids TEXT NOT NULL DEFAULT '[]',
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

// v19：RAG 检索 FTS 表（trigram 分词，中文子串可命中；≥3 字查询走 MATCH，2 字走 LIKE fallback）
const SQL_CREATE_NOTE_FTS: string = `
  CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
    title, content, unit_id UNINDEXED, subject UNINDEXED, chapter UNINDEXED, tokenize='trigram'
  )`;

const SQL_BACKFILL_NOTE_FTS: string =
  "INSERT INTO note_fts (title, content, unit_id, subject, chapter) " +
  "SELECT title, content, id, subject, chapter FROM knowledge_unit";

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

// ADR-0022：复习用独立表，study_plan 保持待办语义（v14 → v15）。
// 测试态按本地开发数据处理：CREATE IF NOT EXISTS 即可，回滚 = DROP TABLE。
const SQL_CREATE_REVIEW_ITEM: string = `
CREATE TABLE IF NOT EXISTS review_item (
  id TEXT PRIMARY KEY,
  unit_id TEXT NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'new',
  next_review_at INTEGER NOT NULL DEFAULT 0,
  interval_days INTEGER NOT NULL DEFAULT 0,
  ease_factor REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  last_reviewed_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

const SQL_CREATE_REVIEW_LOG: string = `
CREATE TABLE IF NOT EXISTS review_log (
  id TEXT PRIMARY KEY,
  review_item_id TEXT NOT NULL,
  unit_id TEXT NOT NULL,
  reviewed_at INTEGER NOT NULL,
  grade TEXT NOT NULL,
  correct INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  interval_before INTEGER NOT NULL DEFAULT 0,
  interval_after INTEGER NOT NULL DEFAULT 0
)`;

// v23：复习写侧幂等键。与 review_item / review_log 的业务写入同事务。
const SQL_CREATE_REVIEW_OP: string = `
CREATE TABLE IF NOT EXISTS review_op (
  operation_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  log_id TEXT NOT NULL DEFAULT '',
  committed_at INTEGER NOT NULL
)`;

const SQL_INDEX_REVIEW_ITEM_DUE: string =
  "CREATE INDEX IF NOT EXISTS idx_review_item_due ON review_item(next_review_at)";
const SQL_INDEX_REVIEW_ITEM_UNIT: string =
  "CREATE INDEX IF NOT EXISTS idx_review_item_unit ON review_item(unit_id)";
const SQL_INDEX_REVIEW_LOG_ITEM: string =
  "CREATE INDEX IF NOT EXISTS idx_review_log_item ON review_log(review_item_id)";

// RunStore 持久化（v15 → v16）：run 记录 + 事件流。
// 事件序号由 DAO 在事务内 MAX(sequence)+1 生成，(run_id, sequence) 唯一递增。
const SQL_CREATE_RUN_STORE: string = `
CREATE TABLE IF NOT EXISTS run_store (
  run_id TEXT PRIMARY KEY,
  parent_run_id TEXT,
  status TEXT NOT NULL,
  checkpoint_id TEXT,
  committed_note_id TEXT,
  committed_version INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

const SQL_CREATE_RUN_EVENT: string = `
CREATE TABLE IF NOT EXISTS run_event (
  event_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  kind TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL
)`;

const SQL_INDEX_RUN_STORE_STATUS: string =
  "CREATE INDEX IF NOT EXISTS idx_run_store_status ON run_store(status)";
const SQL_INDEX_RUN_STORE_CREATED: string =
  "CREATE INDEX IF NOT EXISTS idx_run_store_created_at ON run_store(created_at)";
const SQL_INDEX_RUN_EVENT_RUN_SEQ: string =
  "CREATE INDEX IF NOT EXISTS idx_run_event_run_seq ON run_event(run_id, sequence)";
const SQL_INDEX_RUN_EVENT_CREATED: string =
  "CREATE INDEX IF NOT EXISTS idx_run_event_created_at ON run_event(created_at)";
// 跨进程并发时给 (run_id, sequence) 兜底；旧库若已有重复序列，创建会失败并被 tryExecuteSql 跳过。
const SQL_INDEX_RUN_EVENT_RUN_SEQ_UNIQUE: string =
  "CREATE UNIQUE INDEX IF NOT EXISTS uq_run_event_run_seq ON run_event(run_id, sequence)";
// SQLite 跨进程写锁等待：两个进程同时写时先等 5s，而不是立即 SQLITE_BUSY。
const SQL_PRAGMA_BUSY_TIMEOUT: string = 'PRAGMA busy_timeout = 5000';

// StudyPlanWritePort（v16 → v17）：study_plan 加 version 列做 CAS，另建幂等操作表。
// 语义仍是待办（ADR-0022）：只加版本与操作记录，不加评分/掌握度字段。
// v18：HITL 审批哈希落位（ADR-0019 (d)）——审批属于检查点，用 approved_at 标记。
// v20（ADR-0024 / spec 040）：WriteJob 持久队列 + 跨进程 handoff。
// 队列单执行者（UI 进程）claim 租约；:agent 扩展的单次整理内联执行（ADR-0024 §2.7），不经过此队列。
const SQL_CREATE_AGENT_JOB: string = `
CREATE TABLE IF NOT EXISTS agent_job (
  job_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  priority TEXT NOT NULL,
  payload_text TEXT NOT NULL,
  source TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 0,
  fingerprint TEXT NOT NULL,
  lease_owner TEXT NOT NULL DEFAULT '',
  lease_expires_at INTEGER NOT NULL DEFAULT 0,
  error TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

const SQL_INDEX_AGENT_JOB_PICK: string =
  "CREATE INDEX IF NOT EXISTS idx_agent_job_pick ON agent_job(status, priority, created_at)";
// 同 fingerprint 的非终态 job 唯一：跨进程重复入队只保留一条（queued/running 才参与）。
const SQL_INDEX_AGENT_JOB_ACTIVE_FP: string =
  "CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_job_active_fp ON agent_job(fingerprint) WHERE status IN ('queued', 'running')";
const SQL_INDEX_AGENT_JOB_UPDATED: string =
  "CREATE INDEX IF NOT EXISTS idx_agent_job_updated ON agent_job(status, updated_at)";

const SQL_MIGRATE_CHECKPOINT_APPROVED: string =
  'ALTER TABLE note_generation_checkpoint ADD COLUMN approved_at INTEGER NOT NULL DEFAULT 0';
const SQL_MIGRATE_STUDY_PLAN_VERSION: string =
  "ALTER TABLE study_plan ADD COLUMN version INTEGER NOT NULL DEFAULT 1";
const SQL_MIGRATE_NOTE_SIGNATURE: string =
  "ALTER TABLE knowledge_unit ADD COLUMN signature TEXT NOT NULL DEFAULT \"\"";
// v22：笔记类型（normal / atomic / summary）。为原子笔记与汇总笔记分层铺路，
// 本轮只落库不改行为；旧数据一律 normal。
const SQL_MIGRATE_NOTE_KIND: string =
  "ALTER TABLE knowledge_unit ADD COLUMN kind TEXT NOT NULL DEFAULT 'normal'";

const SQL_CREATE_STUDY_PLAN_OP: string = `
CREATE TABLE IF NOT EXISTS study_plan_op (
  operation_id TEXT PRIMARY KEY,
  plan_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  version INTEGER NOT NULL,
  committed_at INTEGER NOT NULL
)`;

const SQL_INDEX_STUDY_PLAN_OP_PLAN: string =
  "CREATE INDEX IF NOT EXISTS idx_study_plan_op_plan ON study_plan_op(plan_id)";

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
const SQL_INDEX_CHAT_MESSAGE_STABLE_ORDER: string =
  "CREATE INDEX IF NOT EXISTS idx_chat_message_stable_order ON chat_message(session_id, sequence, created_at, id)";
const SQL_INDEX_CHAT_MESSAGE_KEY: string =
  "CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_message_session_key ON chat_message(session_id, message_key)";
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
const SQL_MIGRATE_KNOWLEDGE_SOURCE_IMAGE_ID: string =
  "ALTER TABLE knowledge_unit ADD COLUMN source_image_id TEXT NOT NULL DEFAULT \"\"";
const SQL_MIGRATE_KNOWLEDGE_SOURCE_REGION: string =
  "ALTER TABLE knowledge_unit ADD COLUMN source_region TEXT NOT NULL DEFAULT \"\"";
const SQL_MIGRATE_KNOWLEDGE_OCR_CONFIDENCE: string =
  "ALTER TABLE knowledge_unit ADD COLUMN ocr_confidence REAL NOT NULL DEFAULT 0";
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
const SQL_MIGRATE_CHAT_MESSAGE_KEY: string =
  "ALTER TABLE chat_message ADD COLUMN message_key TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHAT_RUN_ID: string =
  "ALTER TABLE chat_message ADD COLUMN run_id TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_CHAT_SEQUENCE: string =
  "ALTER TABLE chat_message ADD COLUMN sequence INTEGER NOT NULL DEFAULT 0";
const SQL_MIGRATE_CHAT_ORIGIN: string =
  "ALTER TABLE chat_message ADD COLUMN origin TEXT NOT NULL DEFAULT 'legacy'";
const SQL_MIGRATE_CHAT_OUTCOME: string =
  "ALTER TABLE chat_message ADD COLUMN outcome TEXT NOT NULL DEFAULT 'completed'";
const SQL_MIGRATE_GENERATION_ORIGIN_SESSION: string =
  "ALTER TABLE note_generation_run ADD COLUMN origin_session_id TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_GENERATION_PARENT_RUN: string =
  "ALTER TABLE note_generation_run ADD COLUMN parent_conversation_run_id TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_GENERATION_CLARIFICATION: string =
  "ALTER TABLE note_generation_run ADD COLUMN clarification_json TEXT NOT NULL DEFAULT ''";
const SQL_MIGRATE_GENERATION_CONTEXT_BUDGET: string =
  "ALTER TABLE note_generation_run ADD COLUMN context_budget_tokens INTEGER NOT NULL DEFAULT 0";
const SQL_MIGRATE_GENERATION_SOURCE_PROVENANCE: string =
  "ALTER TABLE note_generation_source ADD COLUMN provenance_ids TEXT NOT NULL DEFAULT '[]'";
const SQL_BACKFILL_CHAT_MESSAGE_KEY: string =
  "UPDATE chat_message SET message_key = id WHERE message_key = ''";
const SQL_BACKFILL_CHAT_SEQUENCE: string =
  "UPDATE chat_message SET sequence = created_at WHERE sequence = 0";
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
      SQL_CREATE_NOTE_FTS,
      SQL_CREATE_REVIEW_ITEM,
      SQL_CREATE_REVIEW_LOG,
      SQL_CREATE_REVIEW_OP,
      SQL_CREATE_RUN_STORE,
      SQL_CREATE_RUN_EVENT,
      SQL_CREATE_AGENT_JOB,
      SQL_CREATE_STUDY_PLAN_OP,
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
      SQL_INDEX_REVIEW_ITEM_DUE,
      SQL_INDEX_REVIEW_ITEM_UNIT,
      SQL_INDEX_REVIEW_LOG_ITEM,
      SQL_INDEX_RUN_STORE_STATUS,
      SQL_INDEX_RUN_STORE_CREATED,
      SQL_INDEX_RUN_EVENT_RUN_SEQ,
      SQL_INDEX_RUN_EVENT_CREATED,
      SQL_INDEX_AGENT_JOB_PICK,
      SQL_INDEX_AGENT_JOB_ACTIVE_FP,
      SQL_INDEX_AGENT_JOB_UPDATED,
      SQL_INDEX_STUDY_PLAN_OP_PLAN,
    ];

    for (const sql of statements) {
      await DatabaseHelper.executeSql(store, sql);
    }
    // 唯一索引是增量加固：老库有重复序列时跳过，不阻塞启动。
    await DatabaseHelper.tryExecuteSql(store, SQL_INDEX_RUN_EVENT_RUN_SEQ_UNIQUE);
    await DatabaseHelper.applyBusyTimeout(store);

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
    const hasSourceImageId: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "source_image_id");
    if (!hasSourceImageId) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_KNOWLEDGE_SOURCE_IMAGE_ID);
    }
    const hasSourceRegion: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "source_region");
    if (!hasSourceRegion) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_KNOWLEDGE_SOURCE_REGION);
    }
    const hasOcrConfidence: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "ocr_confidence");
    if (!hasOcrConfidence) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_KNOWLEDGE_OCR_CONFIDENCE);
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
    const hasMessageKey: boolean = await DatabaseHelper.hasColumn(store, "chat_message", "message_key");
    if (!hasMessageKey) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHAT_MESSAGE_KEY); }
    const hasChatRunId: boolean = await DatabaseHelper.hasColumn(store, "chat_message", "run_id");
    if (!hasChatRunId) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHAT_RUN_ID); }
    const hasChatSequence: boolean = await DatabaseHelper.hasColumn(store, "chat_message", "sequence");
    if (!hasChatSequence) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHAT_SEQUENCE); }
    const hasChatOrigin: boolean = await DatabaseHelper.hasColumn(store, "chat_message", "origin");
    if (!hasChatOrigin) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHAT_ORIGIN); }
    const hasChatOutcome: boolean = await DatabaseHelper.hasColumn(store, "chat_message", "outcome");
    if (!hasChatOutcome) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHAT_OUTCOME); }
    const hasGenerationOriginSession: boolean = await DatabaseHelper.hasColumn(store, "note_generation_run", "origin_session_id");
    if (!hasGenerationOriginSession) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_ORIGIN_SESSION); }
    const hasGenerationParentRun: boolean = await DatabaseHelper.hasColumn(store, "note_generation_run", "parent_conversation_run_id");
    if (!hasGenerationParentRun) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_PARENT_RUN); }
    const hasGenerationClarification: boolean = await DatabaseHelper.hasColumn(store, "note_generation_run", "clarification_json");
    if (!hasGenerationClarification) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_CLARIFICATION); }
    const hasGenerationContextBudget: boolean = await DatabaseHelper.hasColumn(store, "note_generation_run", "context_budget_tokens");
    if (!hasGenerationContextBudget) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_CONTEXT_BUDGET); }
    const hasGenerationSourceProvenance: boolean = await DatabaseHelper.hasColumn(store, "note_generation_source", "provenance_ids");
    if (!hasGenerationSourceProvenance) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_GENERATION_SOURCE_PROVENANCE); }
    // v17：待办写端口需要 CAS 版本列（ADR-0022 仍保持待办语义，不加复习字段）
    const hasStudyPlanVersion: boolean = await DatabaseHelper.hasColumn(store, "study_plan", "version");
    if (!hasStudyPlanVersion) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_STUDY_PLAN_VERSION); }
    // v18：检查点审批标记列（幂等）。
    const hasCheckpointApproved: boolean = await DatabaseHelper.hasColumn(store, "note_generation_checkpoint", "approved_at");
    if (!hasCheckpointApproved) { await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_CHECKPOINT_APPROVED); }

    // v19：RAG 检索 FTS 回填（从 knowledge_unit 全量重建，仅首次迁移执行）。
    if (store.version < 19) {
      await DatabaseHelper.executeSql(store, "DELETE FROM note_fts");
      await DatabaseHelper.executeSql(store, SQL_BACKFILL_NOTE_FTS);
    }

    // v21：数学签名列（按标题计算后回填），供检索与查重直出。
    const hasSignature: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "signature");
    if (!hasSignature) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_NOTE_SIGNATURE);
    }
    await DatabaseHelper.backfillNoteSignatures(store);

    // v22：笔记类型列；旧数据由 DEFAULT 填成 normal，不需要回填。
    const hasKind: boolean = await DatabaseHelper.hasColumn(store, "knowledge_unit", "kind");
    if (!hasKind) {
      await DatabaseHelper.executeAddColumn(store, SQL_MIGRATE_NOTE_KIND);
    }

    await DatabaseHelper.executeSql(store, SQL_BACKFILL_CHAT_MESSAGE_KEY);
    await DatabaseHelper.executeSql(store, SQL_BACKFILL_CHAT_SEQUENCE);
    await DatabaseHelper.executeSql(store, SQL_INDEX_CHAT_MESSAGE_STABLE_ORDER);
    await DatabaseHelper.executeSql(store, SQL_INDEX_CHAT_MESSAGE_KEY);

    await DatabaseHelper.executeSql(store, SQL_BACKFILL_NOTE_REVISION);

    if (store.version < DB_SCHEMA_VERSION) {
      store.version = DB_SCHEMA_VERSION;
    }
  }

  /** v21 签名回填：只处理 signature 为空的行，按标题计算；失败保持空串。 */
  private static async backfillNoteSignatures(store: relationalStore.RdbStore): Promise<void> {
    try {
      const rows: SignatureBackfillRow[] = await new Promise<SignatureBackfillRow[]>(
        (resolve: (value: SignatureBackfillRow[]) => void, reject: (reason: Error) => void): void => {
          store.querySql('SELECT id, title FROM knowledge_unit WHERE signature = ""', [],
            (err: BusinessError, rs: relationalStore.ResultSet) => {
              if (err) {
                reject(new Error(err.message));
                return;
              }
              const collected: SignatureBackfillRow[] = [];
              try {
                while (rs.goToNextRow()) {
                  collected.push({
                    id: rs.getString(rs.getColumnIndex('id')),
                    title: rs.getString(rs.getColumnIndex('title')),
                  });
                }
              } finally {
                rs.close();
              }
              resolve(collected);
            });
        });
      for (let i = 0; i < rows.length; i += 1) {
        const signature: string = extractMathSignature(rows[i].title);
        if (signature.length > 0) {
          await DatabaseHelper.executeSqlArgs(store,
            'UPDATE knowledge_unit SET signature = ? WHERE id = ?', [signature, rows[i].id]);
        }
      }
    } catch (error) {
      console.warn('[DatabaseHelper] signature backfill skipped: ' + (error as Error).message);
    }
  }

  private static async executeSqlArgs(store: relationalStore.RdbStore, sql: string,
    args: Array<string | number>): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      store.executeSql(sql, args, (err: BusinessError) => {
        if (err) {
          reject(new Error('DatabaseHelper.executeSqlArgs failed: ' + err.message));
          return;
        }
        resolve();
      });
    });
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

  /** 增量加固：失败只告警，不阻塞启动（例如老库已有重复数据导致唯一索引建不起来）。 */
  private static async tryExecuteSql(store: relationalStore.RdbStore, sql: string): Promise<void> {
    try {
      await DatabaseHelper.executeSql(store, sql);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      console.warn('[DatabaseHelper] optional SQL skipped: ' + message);
    }
  }

  /** 跨进程写锁等待；PRAGMA 不受 StoreConfig 支持，只能连接级设置。 */
  private static async applyBusyTimeout(store: relationalStore.RdbStore): Promise<void> {
    try {
      await DatabaseHelper.executeSql(store, SQL_PRAGMA_BUSY_TIMEOUT);
      console.info('[DatabaseHelper] PRAGMA busy_timeout=5000');
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      console.warn('[DatabaseHelper] PRAGMA busy_timeout failed: ' + message);
    }
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
