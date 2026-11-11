/**
 * NoteReadPortAdapter.ets — NoteReadPort 的只读实现（投影 / 过滤 / 排序 / 分页）
 *
 * 路径: common/src/main/ets/ports/impl/NoteReadPortAdapter.ets
 * 职责: 把 NoteReadStore 的只读查询映射成端口语义：过滤、按 updatedAt 倒序、分页、投影；
 *       不持 RDB 句柄、不做写入（写实现留在 entry，见 ADR-0021）。
 * 依赖: ../NoteReadPort（契约与错误码）、../NoteWritePort（NotePortError）；均同模块相对路径。
 *
 * 数据流:
 *   UI / ReviewAgent / skill 工具 → list / get / search / listByIds → NoteReadStore → knowledge_unit 表
 *
 * 契约实现（#238 / ADR-0021）:
 *   - 参数非法（limit <= 0 / offset < 0）抛 INVALID_QUERY，不静默返回空数组。
 *   - 先过滤、再排序、最后分页；不原地排序 store 返回的数组。
 *   - search 只匹配元数据（title / summary / tags / subject / chapter），正文检索归 NoteSearchPort。
 *   - 存储读失败抛 NOTE_READ_FAILED(retryable=true)；get 的「不存在」返回 null。
 *   - 投影里的 tags 是副本；返回 NoteSummary / NoteDetail，不泄漏整行 KnowledgeUnit。
 *
 * ArkTS 1.1 strict 适配:
 *   - 静态工具方法用 private static；实例只持注入依赖；箭头函数显式标注参数与返回类型。
 */
import { NotePortError } from '../NoteWritePort';
import { NOTE_READ_ERROR_INVALID_QUERY, NOTE_READ_ERROR_READ_FAILED } from '../NoteReadPort';
import type { NoteDetail, NoteQuery, NoteReadPort, NoteReadStore, NoteSummary } from '../NoteReadPort';

export class NoteReadPortAdapter implements NoteReadPort {
  private readonly store: NoteReadStore;

  constructor(store: NoteReadStore) {
    this.store = store;
  }

  async get(id: string): Promise<NoteDetail | null> {
    if (id.length === 0) {
      throw new NotePortError(NOTE_READ_ERROR_INVALID_QUERY, 'note id must not be empty', false);
    }
    try {
      return await this.store.queryById(id);
    } catch (e) {
      if (e instanceof NotePortError) {
        throw new NotePortError(e.code, e.message, e.retryable);
      }
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError(NOTE_READ_ERROR_READ_FAILED, message, true);
    }
  }

  async list(query: NoteQuery): Promise<NoteSummary[]> {
    NoteReadPortAdapter.validate(query);
    const all: NoteDetail[] = await this.readAll();
    const matched: NoteDetail[] = all.filter((unit: NoteDetail): boolean => {
      return NoteReadPortAdapter.matches(unit, query);
    });
    const ordered: NoteDetail[] = matched.slice();
    ordered.sort((left: NoteDetail, right: NoteDetail): number => {
      return right.updatedAt - left.updatedAt;
    });
    const page: NoteDetail[] = ordered.slice(query.offset, query.offset + query.limit);
    return page.map((unit: NoteDetail): NoteSummary => NoteReadPortAdapter.toSummary(unit));
  }

  async search(query: NoteQuery): Promise<NoteSummary[]> {
    NoteReadPortAdapter.validate(query);
    const keyword: string | undefined = query.keyword;
    if (keyword === undefined || keyword.trim().length === 0) {
      return [];
    }
    return await this.list(query);
  }

  async listByIds(ids: string[]): Promise<NoteDetail[]> {
    const unique: string[] = [];
    for (const id of ids) {
      if (id.length > 0 && unique.indexOf(id) < 0) {
        unique.push(id);
      }
    }
    unique.sort();
    const found: NoteDetail[] = [];
    for (const id of unique) {
      const unit: NoteDetail | null = await this.get(id);
      if (unit !== null) {
        found.push(unit);
      }
    }
    return found;
  }

  private async readAll(): Promise<NoteDetail[]> {
    try {
      return await this.store.queryAllMetadata();
    } catch (e) {
      if (e instanceof NotePortError) {
        throw new NotePortError(e.code, e.message, e.retryable);
      }
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

  private static matches(unit: NoteDetail, query: NoteQuery): boolean {
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

  private static toSummary(unit: NoteDetail): NoteSummary {
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
