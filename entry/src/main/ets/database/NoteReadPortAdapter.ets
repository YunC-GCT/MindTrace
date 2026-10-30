/**
 * NoteReadPortAdapter.ets — NoteReadPort 的 entry 侧实现（DAO 之上的薄适配）
 *
 * 路径: entry/src/main/ets/database/NoteReadPortAdapter.ets
 * 职责: 把 NoteReadPort 的 list / get / search 映射到 NoteReadStore（生产是 NoteDao）；
 *       过滤、排序、分页、投影都在本层完成，DAO 不感知端口。
 * 依赖: common 的契约类型（type-only，编译期擦除）；运行期只依赖注入的 NoteReadStore。
 *
 * 数据流:
 *   UI / ReviewAgent → list / get / search → NoteReadStore（生产是 NoteDao）→ knowledge_unit 表
 *
 * 契约实现（#238 / §17.5）:
 *   - 参数非法（limit <= 0 / offset < 0）抛 NotePortError(INVALID_QUERY, retryable=false)。
 *   - list / search 共用同一套查询形状；先过滤、再按 updatedAt 倒序、最后分页（不排序后分页）。
 *   - 存储读失败统一抛 NotePortError(NOTE_READ_FAILED, retryable=true)；get 的「不存在」返回 null。
 *   - 投影里的 tags 是副本；查询结果数组不被原地排序（不动 store 返回的数组）。
 *
 * ArkTS 1.1 strict 适配:
 *   - 静态工具方法用 private static；实例只持注入依赖。
 *   - 不使用解构 / any / unknown；箭头函数显式标注参数与返回类型。
 */
import type { KnowledgeUnit } from 'common';
import type { NoteQuery, NoteReadPort, NoteReadStore, NoteSummary } from 'common';
import { NotePortError, NOTE_READ_ERROR_INVALID_QUERY, NOTE_READ_ERROR_READ_FAILED } from 'common';

export class NoteReadPortAdapter implements NoteReadPort {
  private readonly store: NoteReadStore;

  constructor(store: NoteReadStore) {
    this.store = store;
  }

  async get(id: string): Promise<KnowledgeUnit | null> {
    if (id.length === 0) {
      throw new NotePortError(NOTE_READ_ERROR_INVALID_QUERY, 'note id must not be empty', false);
    }
    try {
      return await this.store.queryById(id);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError(NOTE_READ_ERROR_READ_FAILED, message, true);
    }
  }

  async list(query: NoteQuery): Promise<NoteSummary[]> {
    NoteReadPortAdapter.validate(query);
    const all: KnowledgeUnit[] = await this.readAll();
    const matched: KnowledgeUnit[] = all.filter((unit: KnowledgeUnit): boolean => {
      return NoteReadPortAdapter.matches(unit, query);
    });
    const ordered: KnowledgeUnit[] = matched.slice();
    ordered.sort((left: KnowledgeUnit, right: KnowledgeUnit): number => {
      return right.updatedAt - left.updatedAt;
    });
    const page: KnowledgeUnit[] = ordered.slice(query.offset, query.offset + query.limit);
    return page.map((unit: KnowledgeUnit): NoteSummary => NoteReadPortAdapter.toSummary(unit));
  }

  async search(query: NoteQuery): Promise<NoteSummary[]> {
    NoteReadPortAdapter.validate(query);
    const keyword: string | undefined = query.keyword;
    if (keyword === undefined || keyword.trim().length === 0) {
      return [];
    }
    return await this.list(query);
  }

  async listByIds(ids: string[]): Promise<KnowledgeUnit[]> {
    const unique: string[] = [];
    for (const id of ids) {
      if (id.length > 0 && unique.indexOf(id) < 0) {
        unique.push(id);
      }
    }
    unique.sort();
    const found: KnowledgeUnit[] = [];
    for (const id of unique) {
      const unit: KnowledgeUnit | null = await this.get(id);
      if (unit !== null) {
        found.push(unit);
      }
    }
    return found;
  }

  private async readAll(): Promise<KnowledgeUnit[]> {
    try {
      return await this.store.queryAllMetadata();
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError(NOTE_READ_ERROR_READ_FAILED, message, true);
    }
  }

  private static validate(query: NoteQuery): void {
    if (query.limit <= 0) {
      throw new NotePortError(NOTE_READ_ERROR_INVALID_QUERY, 'limit must be greater than zero', false);
    }
    if (query.offset < 0) {
      throw new NotePortError(NOTE_READ_ERROR_INVALID_QUERY, 'offset must not be negative', false);
    }
  }

  private static matches(unit: KnowledgeUnit, query: NoteQuery): boolean {
    if (query.subject !== undefined && query.subject.length > 0 && unit.subject !== query.subject) {
      return false;
    }
    if (query.chapter !== undefined && query.chapter.length > 0 && unit.chapter !== query.chapter) {
      return false;
    }
    const keyword: string | undefined = query.keyword;
    if (keyword === undefined || keyword.trim().length === 0) {
      return true;
    }
    const needle: string = keyword.trim().toLowerCase();
    const haystacks: string[] = [unit.title, unit.summary, unit.subject, unit.chapter];
    for (const haystack of haystacks) {
      if (haystack.toLowerCase().indexOf(needle) >= 0) {
        return true;
      }
    }
    for (const tag of unit.tags) {
      if (tag.toLowerCase().indexOf(needle) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static toSummary(unit: KnowledgeUnit): NoteSummary {
    const summary: NoteSummary = {
      id: unit.id,
      title: unit.title,
      summary: unit.summary,
      subject: unit.subject,
      chapter: unit.chapter,
      category: unit.category,
      tags: unit.tags.slice(),
      difficulty: unit.difficulty,
      reviewStatus: unit.reviewStatus,
      nextReviewAt: unit.nextReviewAt,
      updatedAt: unit.updatedAt,
      version: unit.version,
    };
    return summary;
  }
}
