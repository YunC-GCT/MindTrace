// MindTrace - ReminderFacadeImpl
// 2026-09-06 · F3 最小闭环 (spec 013 / ADR-0009 / 复赛冲刺序 2)
// ----------------------------------------------------------------------------
// 路径: entry/src/main/ets/kit/ReminderFacadeImpl.ets
// 职责: ReminderFacade 契约的 entry 端实现 — 复习提醒安排/取消 (系统日历提醒)
// 依赖: @kit.BackgroundTasksKit (reminderAgentManager) · @kit.AbilityKit (common) ·
//       @kit.ArkData (preferences) · common (ReminderFacade / ReviewReminderRequest 契约)
// 数据流: EntryAbility.onCreate 组合根注入 AppStorage('reminderFacade') → 消费方
//         getReminderFacade() → scheduleReviewReminder (先 cancelByUnit 去重 →
//         publishReminder) → 系统日历提醒; unitId→reminderId 持久化
//         preferences('kit_reminder_map'); 发布需设备通知开关开启
// 注: UI 入口按用户裁决暂不挂 (2026-09-06); ADR-0009 — 只有 entry import @kit
// ============================================================================

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import type { ReminderFacade, ReviewReminderRequest } from 'common';

const REMINDER_PREFS: string = 'kit_reminder_map';

export class ReminderFacadeImpl implements ReminderFacade {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async scheduleReviewReminder(request: ReviewReminderRequest): Promise<void> {
    // 契约语义: 同 unitId 重复安排先取消旧提醒
    await this.cancelByUnit(request.unitId);

    const fireAt: Date = new Date(request.fireAt);
    const dateTime: reminderAgentManager.LocalDateTime = {
      year: fireAt.getFullYear(),
      month: fireAt.getMonth() + 1,
      day: fireAt.getDate(),
      hour: fireAt.getHours(),
      minute: fireAt.getMinutes(),
    };
    const req: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: request.title,
      content: request.subtitle ?? '',
      wantAgent: {
        pkgName: this.context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
      },
    };

    const reminderId: number = await reminderAgentManager.publishReminder(req);
    const prefs: preferences.Preferences = await preferences.getPreferences(this.context, REMINDER_PREFS);
    await prefs.put(request.unitId, reminderId);
    await prefs.flush();
  }

  async cancelByUnit(unitId: string): Promise<void> {
    const prefs: preferences.Preferences = await preferences.getPreferences(this.context, REMINDER_PREFS);
    const saved: preferences.ValueType = await prefs.get(unitId, -1);
    if (typeof saved === 'number' && saved >= 0) {
      try {
        // 提醒可能已触发/已被系统清除 — best effort
        await reminderAgentManager.cancelReminder(saved);
      } catch (e) {
        console.warn('[ReminderFacadeImpl.cancelByUnit] ' + ((e as Error).message ?? String(e)));
      }
    }
    await prefs.delete(unitId);
    await prefs.flush();
  }
}

// 组合根之外的消费方经此取 facade (EntryAbility 注入 AppStorage)
export function getReminderFacade(): ReminderFacade | null {
  const impl: ReminderFacadeImpl | undefined = AppStorage.get<ReminderFacadeImpl>('reminderFacade');
  if (impl === undefined) {
    return null;
  }
  return impl;
}
