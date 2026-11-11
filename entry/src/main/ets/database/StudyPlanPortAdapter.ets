/**
 * StudyPlanPortAdapter.ets — StudyPlanReadPort 的 entry 侧实现
 *
 * 路径: entry/src/main/ets/database/StudyPlanPortAdapter.ets
 * 职责: 把 study_plan 的原始行映射成读侧待办项；过滤、排序、subject 派生都在本层。
 * 依赖: common 的类型（type-only，编译期擦除）+ 注入的 StudyPlanReadStore。
 *
 * 数据流:
 *   UI 待办页 → listPending / get → StudyPlanReadStore（生产是 StudyPlanDao）→ study_plan 表
 *
 * 契约实现（#238）:
 *   - listPending：排除 isDone=true；可选按 subject 过滤；排序 = 有截止时间的按 dueAt 升序在前，
 *     无截止（dueAt=0）排最后；相同 dueAt 保持存储返回顺序（端口项不含 createdAt，不做二次排序）。
 *   - get：按 id 返回（含已完成项，调用方自己判断 done）。
 *   - subject 现状没有列：由注入的 subjectResolver 从 linkedNoteId 派生；未注入或空关联时返回 ''。
 *   - 存储读取失败统一抛 NotePortError(STUDY_PLAN_READ_FAILED, retryable=true)。
 *
 * 领域边界:
 *   - 这是「待办」语义，不是间隔复习；升级复习计划要等 #242 拍板，本适配器不预埋复习字段。
 */
import { NotePortError } from 'common';
import type { StudyPlanItem, StudyPlanReadPort, StudyPlanReadStore, StudyPlanRecord } from 'common';

// subject 派生：组合根可注入一个基于 NoteReadPort 的实现；不注入时保持空串。
export type StudyPlanSubjectResolver = (linkedNoteId: string) => Promise<string>;

export class StudyPlanPortAdapter implements StudyPlanReadPort {
  private readonly store: StudyPlanReadStore;
  private readonly resolveSubject?: StudyPlanSubjectResolver;

  constructor(store: StudyPlanReadStore, resolveSubject?: StudyPlanSubjectResolver) {
    this.store = store;
    this.resolveSubject = resolveSubject;
  }

  async listPending(subject?: string): Promise<StudyPlanItem[]> {
    const records: StudyPlanRecord[] = await this.readAll();
    const pending: StudyPlanRecord[] = records.filter((record: StudyPlanRecord): boolean => !record.isDone);
    const mapped: StudyPlanItem[] = [];
    for (const record of pending) {
      const item: StudyPlanItem = await this.toItem(record);
      if (subject === undefined || subject.length === 0 || item.subject === subject) {
        mapped.push(item);
      }
    }
    mapped.sort(StudyPlanPortAdapter.compareDue);
    return mapped;
  }

  async get(id: string): Promise<StudyPlanItem | null> {
    const records: StudyPlanRecord[] = await this.readAll();
    for (const record of records) {
      if (record.id === id) {
        return await this.toItem(record);
      }
    }
    return null;
  }

  private async readAll(): Promise<StudyPlanRecord[]> {
    try {
      return await this.store.queryAll();
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError('STUDY_PLAN_READ_FAILED', message, true);
    }
  }

  private async toItem(record: StudyPlanRecord): Promise<StudyPlanItem> {
    let subject: string = '';
    const resolver: StudyPlanSubjectResolver | undefined = this.resolveSubject;
    if (resolver !== undefined && record.linkedNoteId.length > 0) {
      try {
        subject = await resolver(record.linkedNoteId);
      } catch (e) {
        subject = '';
      }
    }
    const item: StudyPlanItem = {
      id: record.id,
      subject: subject,
      title: record.title,
      dueAt: record.dueDate,
      done: record.isDone,
    };
    return item;
  }

  private static compareDue(left: StudyPlanItem, right: StudyPlanItem): number {
    const leftDue: number = left.dueAt;
    const rightDue: number = right.dueAt;
    if (leftDue === 0 && rightDue === 0) {
      return 0;
    }
    if (leftDue === 0) {
      return 1;
    }
    if (rightDue === 0) {
      return -1;
    }
    return leftDue - rightDue;
  }
}
