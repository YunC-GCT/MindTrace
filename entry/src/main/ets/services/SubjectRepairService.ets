/**
 * SubjectRepairService.ets — 一次性修复历史笔记的学科名与标题。
 *
 * 路径: entry/src/main/ets/services/SubjectRepairService.ets
 * 职责: 启动后扫一遍 knowledge_unit，把非规范学科名归一、把标题里的复核标记剥掉。
 * 依赖: NoteDao(读全量) + KnowledgeUnitWriteService(带 revision 的正规写路径)
 *
 * 数据流:
 *   EntryAbility.loadContent → repairIfNeeded(context) → queryAll → 逐条 update
 *
 * Why: 归一与清洗是这次才加的，库里已经有一条「最优化」、一条「数学（优化理论/运筹学）」，
 *      光改采集链路治不了旧数据。用户会一直看到三个学科名，所以必须补一次修复。
 *
 * 语义边界:
 *   - 只在「非规范」时才写：subject 已规范、标题已干净的记录一条不碰（幂等）。
 *   - 走 update 的正规写路径（校验 + 版本递增 + revision），不直接改 SQL。
 *   - 单条失败不回滚整批：记 failed 计数继续下一条。
 *   - preferences 存 'subjectRepair.v1'，每台设备只跑一次；跑完就置位。
 *   - 空学科不算「可归一」：归一不出结果就写「其它」，避免校验失败。
 *
 * ArkTS 1.1 strict 适配:
 *   - 所有变量/参数/返回值显式标注类型；对象字面量绑定 interface。
 *   - 只用下标 for；不用展开运算符 / Object.assign。
 */

import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
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
const PREFS_NAME: string = 'mindtrace_maintenance';
const FLAG_KEY: string = 'subjectRepair.version';
// 清洗规则升级就 +1：置位过的设备会再跑一遍，不用手动清数据
const REPAIR_VERSION: number = 2;
const EMPTY_SUBJECT_FALLBACK: string = '其它';

export interface SubjectRepairReport {
  scanned: number;
  subjectFixed: number;
  titleFixed: number;
  failed: number;
}

export class SubjectRepairService {
  /** 每台设备只跑一次；已跑过或跑失败都不再重复（失败原因看 hilog）。 */
  static async repairIfNeeded(context: common.UIAbilityContext): Promise<SubjectRepairReport | null> {
    const prefs: preferences.Preferences = await preferences.getPreferences(context, PREFS_NAME);
    const stored: preferences.ValueType = await prefs.get(FLAG_KEY, 0);
    const applied: number = typeof stored === 'number' ? stored : 0;
    if (applied >= REPAIR_VERSION) {
      return null;
    }
    const report: SubjectRepairReport = await SubjectRepairService.repair(context);
    await prefs.put(FLAG_KEY, REPAIR_VERSION);
    await prefs.flush();
    return report;
  }

  static async repair(context: common.UIAbilityContext): Promise<SubjectRepairReport> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    const store: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context);
    const dao: NoteDao = new NoteDao(store);
    const units: KnowledgeUnit[] = await dao.queryAll();
    const writer: KnowledgeUnitWriteService = await KnowledgeUnitWriteServiceFactory.create(context);

    let subjectFixed: number = 0;
    let titleFixed: number = 0;
    let failed: number = 0;

    for (let i = 0; i < units.length; i++) {
      const unit: KnowledgeUnit = units[i];
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
          hilog.warn(DOMAIN, TAG, 'skip %{public}s: write not committed', unit.id);
          continue;
        }
        if (subjectChanged) {
          subjectFixed += 1;
        }
        if (titleChanged) {
          titleFixed += 1;
        }
      } catch (e) {
        failed += 1;
        const message: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'skip %{public}s: %{public}s', unit.id, message);
      }
    }

    const report: SubjectRepairReport = {
      scanned: units.length,
      subjectFixed: subjectFixed,
      titleFixed: titleFixed,
      failed: failed,
    };
    hilog.info(DOMAIN, TAG,
      'done scanned=%{public}d subject=%{public}d title=%{public}d failed=%{public}d',
      report.scanned, report.subjectFixed, report.titleFixed, report.failed);
    return report;
  }
}
