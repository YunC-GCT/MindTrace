/**
 * A2ADraftStore.ets — A2A 待确认草稿的落盘（跨轮次确认）
 *
 * 路径: entry/src/main/ets/services/A2ADraftStore.ets
 * 职责: 把「已生成待确认」的 NoteDraftReadyEvent 持久化到 <filesDir>/a2a/draft-<key>.json；
 *       用户下一轮回复「确认 / 取消」时读取。
 * 依赖: @kit.AbilityKit (common.Context)、@kit.CoreFileKit (fileIo)、A2ADraftModels。
 *
 * 约束:
 *   - load() 对文件不存在 / JSON 非法 / 字段缺失一律返回 null；
 *   - 超过 DRAFT_MAX_AGE_MS 的草稿视为过期并删除；
 *   - save/clear 失败只告警，不阻塞 A2A 回执。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { A2APendingDraft } from './A2ADraftModels';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'MindTraceA2A';
const DRAFT_DIR: string = 'a2a';
const DRAFT_FILE_PREFIX: string = 'draft-';
export const DRAFT_MAX_AGE_MS: number = 24 * 60 * 60 * 1000;

export class A2ADraftStore {
  static async load(context: common.Context, conversationKey: string): Promise<A2APendingDraft | null> {
    try {
      const path: string = A2ADraftStore.filePath(context, conversationKey);
      if (!fileIo.accessSync(path)) {
        return null;
      }
      const content: string = await A2ADraftStore.readText(path);
      if (content.trim().length === 0) {
        return null;
      }
      const parsed: A2APendingDraft = JSON.parse(content) as A2APendingDraft;
      if (parsed === null || parsed.event === undefined || parsed.event.candidate === undefined) {
        await A2ADraftStore.clear(context, conversationKey);
        return null;
      }
      if (Date.now() - parsed.createdAt > DRAFT_MAX_AGE_MS) {
        await A2ADraftStore.clear(context, conversationKey);
        hilog.info(DOMAIN, TAG, 'A2A_DRAFT expired key=%{public}s', conversationKey);
        return null;
      }
      return parsed;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'A2A_DRAFT_LOAD_FAILED %{public}s', (e as Error).message);
      return null;
    }
  }

  static async save(context: common.Context, draft: A2APendingDraft): Promise<void> {
    try {
      const dir: string = A2ADraftStore.dirPath(context);
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const file: fileIo.File = fileIo.openSync(A2ADraftStore.filePath(context, draft.conversationKey),
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, JSON.stringify(draft));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'A2A_DRAFT_SAVE_FAILED %{public}s', (e as Error).message);
    }
  }

  static async clear(context: common.Context, conversationKey: string): Promise<void> {
    try {
      const path: string = A2ADraftStore.filePath(context, conversationKey);
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'A2A_DRAFT_CLEAR_FAILED %{public}s', (e as Error).message);
    }
  }

  /** 删除超过保留期的草稿文件；返回删除数量。 */
  static prune(context: common.Context, maxAgeMs: number): number {
    const dir: string = A2ADraftStore.dirPath(context);
    if (!fileIo.accessSync(dir)) {
      return 0;
    }
    const now: number = Date.now();
    let removed: number = 0;
    try {
      const names: string[] = fileIo.listFileSync(dir);
      for (let i = 0; i < names.length; i += 1) {
        const name: string = names[i];
        if (name.indexOf(DRAFT_FILE_PREFIX) !== 0 || !name.endsWith('.json')) {
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
      hilog.warn(DOMAIN, TAG, 'A2A_DRAFT_PRUNE_FAILED %{public}s', (e as Error).message);
    }
    return removed;
  }

  private static async readText(path: string): Promise<string> {
    return fileIo.readTextSync(path);
  }

  private static dirPath(context: common.Context): string {
    return context.filesDir + '/' + DRAFT_DIR;
  }

  private static filePath(context: common.Context, conversationKey: string): string {
    return A2ADraftStore.dirPath(context) + '/' + DRAFT_FILE_PREFIX + conversationKey + '.json';
  }
}
