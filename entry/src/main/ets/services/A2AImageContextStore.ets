/**
 * A2AImageContextStore.ets — 记住上一张图片的 OCR 文本（spec 040 体验修订）
 *
 * 路径: entry/src/main/ets/services/A2AImageContextStore.ets
 * 职责: 小艺把「图片」和「整理成笔记」拆成两条消息时，第二条没有 image part；
 *       这里按会话键记住最近一次图片 OCR 文本，供「整理成笔记」直接内联整理（无需打开 App）。
 * 依赖: @kit.CoreFileKit（fileIo）、@kit.AbilityKit（common 类型）、./A2AConversationStore（key 规则）。
 * 数据流: handleImageQuestion(OCR 成功) → save；INTENT_PICK_CARD(整理意图) → load → ingestTextBatchNow
 */
import { fileIo } from '@kit.CoreFileKit';
import type { common } from '@kit.AbilityKit';
import { A2AConversationStore } from './A2AConversationStore';

export interface A2AImageMaterial {
  text: string;
  at: number;
}

const MAX_TEXT_CHARS: number = 6000;

export class A2AImageContextStore {
  static async save(context: common.Context, key: string, ocrText: string,
    mirrorToDefault: boolean = true): Promise<void> {
    const text: string = ocrText.trim();
    if (text.length === 0) {
      return;
    }
    try {
      const dir: string = context.filesDir + '/a2a';
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const material: A2AImageMaterial = {
        text: text.length > MAX_TEXT_CHARS ? text.substring(0, MAX_TEXT_CHARS) : text,
        at: Date.now(),
      };
      const file: fileIo.File = fileIo.openSync(A2AImageContextStore.pathOf(context, key),
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, JSON.stringify(material));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      // 记住图片内容失败不影响本轮问答
    }
    if (mirrorToDefault && key !== 'default') {
      try {
        const material: A2AImageMaterial = { text: text.length > MAX_TEXT_CHARS
          ? text.substring(0, MAX_TEXT_CHARS) : text, at: Date.now() };
        const file: fileIo.File = fileIo.openSync(A2AImageContextStore.pathOf(context, 'default'),
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, JSON.stringify(material));
        } finally {
          fileIo.closeSync(file);
        }
      } catch (e) {
        // 兜底写失败忽略
      }
    }
  }

  static async load(context: common.Context, key: string): Promise<A2AImageMaterial | null> {
    const own: A2AImageMaterial | null = await A2AImageContextStore.loadExact(context, key);
    if (own !== null || key === 'default') {
      return own;
    }
    return await A2AImageContextStore.loadExact(context, 'default');
  }

  private static async loadExact(context: common.Context, key: string): Promise<A2AImageMaterial | null> {
    try {
      const path: string = A2AImageContextStore.pathOf(context, key);
      if (!fileIo.accessSync(path)) {
        return null;
      }
      const parsed: Object = JSON.parse(fileIo.readTextSync(path));
      const material: A2AImageMaterial = parsed as A2AImageMaterial;
      if (typeof material.text !== 'string' || material.text.trim().length === 0) {
        return null;
      }
      return material;
    } catch (e) {
      return null;
    }
  }

  /** 清除某会话的图片材料（e2e 探针隔离用，避免污染真实会话）。 */
  static async clear(context: common.Context, key: string): Promise<void> {
    try {
      const path: string = A2AImageContextStore.pathOf(context, key);
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      // 忽略
    }
  }

  /** 删除超过保留期的图片材料文件；返回删除数量。 */
  static prune(context: common.Context, maxAgeMs: number): number {
    const dir: string = context.filesDir + '/a2a';
    if (!fileIo.accessSync(dir)) {
      return 0;
    }
    const now: number = Date.now();
    let removed: number = 0;
    try {
      const names: string[] = fileIo.listFileSync(dir);
      for (const name of names) {
        if (name.indexOf('image-') !== 0 || !name.endsWith('.json')) {
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

  private static pathOf(context: common.Context, key: string): string {
    return context.filesDir + '/a2a/image-' + A2AConversationStore.keyOf('', key) + '.json';
  }
}
