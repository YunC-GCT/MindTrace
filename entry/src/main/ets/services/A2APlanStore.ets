/**
 * A2APlanStore.ets — A2A 多题整理计划的落盘（跨轮次「一题一题来」）
 *
 * 路径: entry/src/main/ets/services/A2APlanStore.ets
 * 职责: 把「已识别未整理完」的题目计划持久化到 <filesDir>/a2a/plan.json，
 *       用户下一轮回复「继续 / 第 N 题 / 全部 / 取消」时接着推进。
 * 依赖: @kit.AbilityKit (common.Context)、@kit.CoreFileKit (fileIo)、A2APlanModels。
 *
 * 约束:
 *   - load() 对文件不存在 / JSON 非法 / 字段缺失一律返回 null（只有坏数据被忽略）；
 *   - save/clear 失败只告警，不阻塞 A2A 回执。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { A2APlan, PLAN_KEY_DEFAULT, sanitizePlanKey } from './A2APlanModels';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'MindTraceA2A';
const PLAN_DIR: string = 'a2a';
const PLAN_FILE_PREFIX: string = 'plan-';
const PLAN_FILE_LEGACY: string = 'plan.json';

export class A2APlanStore {
  /** 读取待推进计划（按 taskId 隔离；兼容旧的单文件计划）；无计划/坏数据返回 null。 */
  static async load(context: common.Context, taskId: string): Promise<A2APlan | null> {
    try {
      let path: string = A2APlanStore.filePath(context, taskId);
      let migrated: boolean = false;
      if (!fileIo.accessSync(path)) {
        // 兼容旧版本单文件：任何 taskId 首次读取时迁移到自己的 keyed 文件（旧计划不丢）。
        const legacy: string = A2APlanStore.legacyPath(context);
        if (!fileIo.accessSync(legacy)) {
          return null;
        }
        path = legacy;
        migrated = true;
      }
      const content: string = await A2APlanStore.readText(path);
      if (content.trim().length === 0) {
        return null;
      }
      const parsed: A2APlan | null = JSON.parse(content) as A2APlan | null;
      if (parsed === null || parsed.items === undefined || parsed.done === undefined
        || parsed.items.length === 0) {
        return null;
      }
      if (migrated) {
        await A2APlanStore.save(context, taskId, parsed);
      }
      return parsed;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'PLAN_LOAD_FAILED %{public}s', (e as Error).message);
      return null;
    }
  }

  /** 保存计划（按 taskId 分文件覆盖；key API 与 load/clear 对齐）。 */
  static async save(context: common.Context, taskId: string, plan: A2APlan): Promise<void> {
    try {
      const dir: string = A2APlanStore.dirPath(context);
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const file: fileIo.File = fileIo.openSync(A2APlanStore.filePath(context, taskId),
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, JSON.stringify(plan));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'PLAN_SAVE_FAILED %{public}s', (e as Error).message);
    }
  }

  /** 清除计划（按 taskId；缺省同时清理旧的单文件计划）。 */
  static async clear(context: common.Context, taskId: string): Promise<void> {
    try {
      const path: string = A2APlanStore.filePath(context, taskId);
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
      if (sanitizePlanKey(taskId) === PLAN_KEY_DEFAULT) {
        const legacy: string = A2APlanStore.legacyPath(context);
        if (fileIo.accessSync(legacy)) {
          fileIo.unlinkSync(legacy);
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'PLAN_CLEAR_FAILED %{public}s', (e as Error).message);
    }
  }

  /** 删除超过保留期的计划文件（含旧单文件）；返回删除数量。 */
  static prune(context: common.Context, maxAgeMs: number): number {
    const dir: string = A2APlanStore.dirPath(context);
    if (!fileIo.accessSync(dir)) {
      return 0;
    }
    const now: number = Date.now();
    let removed: number = 0;
    try {
      const names: string[] = fileIo.listFileSync(dir);
      for (const name of names) {
        const isPlan: boolean = name.indexOf(PLAN_FILE_PREFIX) === 0 || name === PLAN_FILE_LEGACY;
        if (!isPlan || !name.endsWith('.json')) {
          continue;
        }
        const path: string = dir + '/' + name;
        try {
          const stat: fileIo.Stat = fileIo.statSync(path);
          if (now - stat.mtime * 1000 > maxAgeMs) {
            fileIo.unlinkSync(path);
            removed += 1;
          }
        } catch (e) {
          // 单文件失败不影响其余清理
        }
      }
    } catch (e) {
      return removed;
    }
    return removed;
  }

  private static dirPath(context: common.Context): string {
    return context.filesDir + '/' + PLAN_DIR;
  }

  private static filePath(context: common.Context, taskId: string): string {
    return A2APlanStore.dirPath(context) + '/' + PLAN_FILE_PREFIX + sanitizePlanKey(taskId) + '.json';
  }

  private static legacyPath(context: common.Context): string {
    return A2APlanStore.dirPath(context) + '/' + PLAN_FILE_LEGACY;
  }

  private static async readText(path: string): Promise<string> {
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      const size: number = stat.size;
      if (size <= 0) {
        return '';
      }
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const readLen: number = fileIo.readSync(file.fd, buffer);
      const bytes: Uint8Array = new Uint8Array(buffer, 0, readLen);
      let text: string = '';
      for (let i = 0; i < bytes.length; i += 1) {
        text += String.fromCharCode(bytes[i]);
      }
      return decodeURIComponent(escape(text));
    } finally {
      fileIo.closeSync(file);
    }
  }
}
