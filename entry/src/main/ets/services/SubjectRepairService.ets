/**
 * SubjectRepairService.ets — 历史笔记的学科归一 / 标题清洗。
 *
 * 路径: entry/src/main/ets/services/SubjectRepairService.ets
 * 职责: 扫一遍 knowledge_unit，把非规范学科名归到已有学科、把标题里的复核标记剥掉；
 *       同时给出「整理前 / 整理后」的学科分布，供「我的 → 学科整理」页展示。
 * 依赖: NoteDao(读全量) + KnowledgeUnitWriteService(带 revision 的正规写路径)
 *
 * 触发时机: 只在「我的 → 学科整理」页由用户点击触发，启动路径里不再自动跑。
 *
 * 数据流:
 *   只在「我的 → 学科整理」页由用户点击触发: SubjectMaintenancePage → repair
 *   （不在启动路径里自动跑：改用户数据必须是他自己点的）
 *
 * Why: 归一与清洗是这次才加的，库里已经有一条「最优化」、一条「数学（优化理论/运筹学）」，
 *      光改采集链路治不了旧数据。用户会一直看到三个学科名，所以必须补一次修复。
 *
 * 语义边界:
 *   - 只在「非规范」时才写：subject 已规范、标题已干净的记录一条不碰（幂等）。
 *   - 走 update 的正规写路径（校验 + 版本递增 + revision），不直接改 SQL。
 *   - 单条失败不回滚整批：记 failed 计数继续下一条。
 *   - 空学科不算「可归一」：归一不出结果就写「其它」，避免校验失败。
 *
 * ArkTS 1.1 strict 适配:
 *   - 所有变量/参数/返回值显式标注类型；对象字面量绑定 interface。
 *   - 只用下标 for；不用展开运算符 / Object.assign。
 */

import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper, KnowledgeUnit } from 'common';
import {
  normalizeSubjectName,
  sanitizeNoteTitle,
  SubjectNormalization,
  TitleSanitization,
} from 'agents';
import { NoteDao } from '../database/NoteDao';
import { KnowledgeUnitWriteService } from './KnowledgeUnitWriteService';
import { KnowledgeUnitWriteResult } from '../models/KnowledgeUnitWriteModels';
import { KnowledgeUnitWriteServiceFactory } from './KnowledgeUnitWriteServiceFactory';

const DOMAIN: number = 0x0001;
const TAG: string = 'SubjectRepair';
const EMPTY_SUBJECT_FALLBACK: string = '其它';

/** 某个学科当前挂了几条笔记 */
export interface SubjectUsage {
  subject: string;
  count: number;
}

/** 一条归一记录：原学科名 → 归到哪个学科，涉及几条 */
export interface SubjectChange {
  from: string;
  to: string;
  count: number;
}

export interface SubjectRepairReport {
  scanned: number;
  subjectFixed: number;
  titleFixed: number;
  failed: number;
  before: SubjectUsage[];
  after: SubjectUsage[];
  changes: SubjectChange[];
}

function tally(subjects: string[]): SubjectUsage[] {
  const names: string[] = [];
  const counts: number[] = [];
  for (let i = 0; i < subjects.length; i++) {
    const name: string = subjects[i].trim();
    if (name.length === 0) {
      continue;
    }
    const at: number = names.indexOf(name);
    if (at >= 0) {
      counts[at] = counts[at] + 1;
    } else {
      names.push(name);
      counts.push(1);
    }
  }
  const usages: SubjectUsage[] = [];
  for (let i = 0; i < names.length; i++) {
    usages.push({ subject: names[i], count: counts[i] });
  }
  // 条数多的排前面；同条数按名字排，保证页面顺序稳定
  usages.sort((a: SubjectUsage, b: SubjectUsage): number => {
    if (b.count !== a.count) {
      return b.count - a.count;
    }
    if (a.subject === b.subject) {
      return 0;
    }
    return a.subject < b.subject ? -1 : 1;
  });
  return usages;
}

export class SubjectRepairService {
  /** 只读：当前学科分布，用于整理前预览。 */
  static async preview(context: common.UIAbilityContext): Promise<SubjectUsage[]> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    const store: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context);
    const dao: NoteDao = new NoteDao(store);
    const units: KnowledgeUnit[] = await dao.queryAllMetadata();
    const subjects: string[] = [];
    for (let i = 0; i < units.length; i++) {
      subjects.push(units[i].subject);
    }
    return tally(subjects);
  }

  static async repair(context: common.UIAbilityContext): Promise<SubjectRepairReport> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    const store: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context);
    const dao: NoteDao = new NoteDao(store);
    const units: KnowledgeUnit[] = await dao.queryAll();
    const writer: KnowledgeUnitWriteService = await KnowledgeUnitWriteServiceFactory.create(context);

    const beforeSubjects: string[] = [];
    for (let i = 0; i < units.length; i++) {
      beforeSubjects.push(units[i].subject);
    }

    const changeFrom: string[] = [];
    const changeTo: string[] = [];
    const changeCount: number[] = [];
    let subjectFixed: number = 0;
    let titleFixed: number = 0;
    let failed: number = 0;

    for (let i = 0; i < units.length; i++) {
      const unit: KnowledgeUnit = units[i];
      const originalSubject: string = unit.subject;
      const subjectResult: SubjectNormalization = normalizeSubjectName(unit.subject);
      const titleResult: TitleSanitization = sanitizeNoteTitle(unit.title);

      const nextSubject: string = subjectResult.subject.length > 0
        ? subjectResult.subject
        : EMPTY_SUBJECT_FALLBACK;
      // 标题剥完为空说明整条标题都是标记，保留原样比清空更安全。
      const nextTitle: string = titleResult.title.length > 0 ? titleResult.title : unit.title;

      const subjectChanged: boolean = nextSubject !== unit.subject;
      const titleChanged: boolean = nextTitle !== unit.title;
      if (!subjectChanged && !titleChanged) {
        continue;
      }

      unit.subject = nextSubject;
      unit.title = nextTitle;
      try {
        const result: KnowledgeUnitWriteResult = await writer.update(unit, unit.version, 'subject_repair');
        if (!result.committed) {
          failed += 1;
          // 写失败要把内存里的改动还原，否则「整理后分布」会显示没落库的名字
          unit.subject = originalSubject;
          hilog.warn(DOMAIN, TAG, 'skip %{public}s: write not committed', unit.id);
          continue;
        }
        if (subjectChanged) {
          subjectFixed += 1;
          const at: number = changeFrom.indexOf(originalSubject);
          if (at >= 0 && changeTo[at] === nextSubject) {
            changeCount[at] = changeCount[at] + 1;
          } else {
            changeFrom.push(originalSubject);
            changeTo.push(nextSubject);
            changeCount.push(1);
          }
        }
        if (titleChanged) {
          titleFixed += 1;
        }
      } catch (e) {
        failed += 1;
        unit.subject = originalSubject;
        const message: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'skip %{public}s: %{public}s', unit.id, message);
      }
    }

    const afterSubjects: string[] = [];
    for (let i = 0; i < units.length; i++) {
      afterSubjects.push(units[i].subject);
    }
    const changes: SubjectChange[] = [];
    for (let i = 0; i < changeFrom.length; i++) {
      changes.push({ from: changeFrom[i], to: changeTo[i], count: changeCount[i] });
    }

    const report: SubjectRepairReport = {
      scanned: units.length,
      subjectFixed: subjectFixed,
      titleFixed: titleFixed,
      failed: failed,
      before: tally(beforeSubjects),
      after: tally(afterSubjects),
      changes: changes,
    };
    hilog.info(DOMAIN, TAG,
      'done scanned=%{public}d subject=%{public}d title=%{public}d failed=%{public}d',
      report.scanned, report.subjectFixed, report.titleFixed, report.failed);
    return report;
  }
}
