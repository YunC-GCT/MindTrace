/**
 * AgentInboxQueue.ets — 小艺待整理队列（应用沙箱里的一个 JSONL 文件）。
 *
 * 路径: entry/src/main/ets/services/AgentInboxQueue.ets
 * 职责: 队列文件的追加写 / 领取 / 收尾。扩展进程（:agent）只写，应用进程只领。
 * 依赖: @kit.AbilityKit (common.Context)、@kit.CoreFileKit (fileIo)、AgentInboxModels
 *
 * 为什么用文件而不是 RDB：notes 库由应用进程独占，扩展进程跨进程写 RDB 不可靠；
 * 同一 bundle 的 filesDir 是两个进程都能访问的安全区，所以队列走文件。
 * 领取时先把 pending 文件改名成 processing，再读 processing：应用中途被杀也不会重复整理，
 * 下次前台继续从 processing 读（单条失败只记日志，不阻塞其余条目）。
 */

import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AgentInboxItem, parseInboxItems, serializeInboxItem } from './AgentInboxModels';

const INBOX_DIR_NAME: string = 'a2a-inbox';
const PENDING_FILE_NAME: string = 'pending.jsonl';
const PROCESSING_FILE_NAME: string = 'processing.jsonl';

export class AgentInboxQueue {
  private static dirPath(context: common.Context): string {
    return context.filesDir + '/' + INBOX_DIR_NAME;
  }

  private static pendingPath(context: common.Context): string {
    return AgentInboxQueue.dirPath(context) + '/' + PENDING_FILE_NAME;
  }

  private static processingPath(context: common.Context): string {
    return AgentInboxQueue.dirPath(context) + '/' + PROCESSING_FILE_NAME;
  }

  private static ensureDir(context: common.Context): void {
    const dir: string = AgentInboxQueue.dirPath(context);
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
  }

  /** 追加一条；返回追加后的待整理条数（用于小艺侧回话「第 N 条」）。 */
  static async append(context: common.Context, item: AgentInboxItem): Promise<number> {
    AgentInboxQueue.ensureDir(context);
    const path: string = AgentInboxQueue.pendingPath(context);
    const file: fileIo.File = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND,
    );
    try {
      fileIo.writeSync(file.fd, serializeInboxItem(item));
    } finally {
      fileIo.closeSync(file);
    }
    return await AgentInboxQueue.pendingCount(context);
  }

  /** 待整理条数；文件不存在或全是坏行时返回 0。 */
  static async pendingCount(context: common.Context): Promise<number> {
    return AgentInboxQueue.readItems(context, AgentInboxQueue.pendingPath(context)).length;
  }

  /**
   * 领取：把 pending 改名成 processing 再读 processing。
   * 已经是 processing 的残留（上次应用中途退出）先并回结果，避免丢条目。
   */
  static async claim(context: common.Context): Promise<AgentInboxItem[]> {
    AgentInboxQueue.ensureDir(context);
    const pending: string = AgentInboxQueue.pendingPath(context);
    const processing: string = AgentInboxQueue.processingPath(context);
    const carried: AgentInboxItem[] = AgentInboxQueue.readItems(context, processing);
    if (fileIo.accessSync(pending) && fileIo.readTextSync(pending).trim().length > 0) {
      if (fileIo.accessSync(processing)) {
        fileIo.unlinkSync(processing);
      }
      fileIo.renameSync(pending, processing);
    }
    const claimed: AgentInboxItem[] = AgentInboxQueue.readItems(context, processing);
    if (carried.length === 0) {
      return claimed;
    }
    const all: AgentInboxItem[] = [];
    for (let i = 0; i < carried.length; i++) {
      all.push(carried[i]);
    }
    for (let i = 0; i < claimed.length; i++) {
      all.push(claimed[i]);
    }
    return all;
  }

  /** 一批整理结束后收尾；即使有条目失败也清空，避免同一条永远占着队列。 */
  static async complete(context: common.Context): Promise<void> {
    const processing: string = AgentInboxQueue.processingPath(context);
    if (fileIo.accessSync(processing)) {
      fileIo.unlinkSync(processing);
    }
  }

  private static readItems(context: common.Context, path: string): AgentInboxItem[] {
    if (!fileIo.accessSync(path)) {
      return [];
    }
    try {
      const raw: string = fileIo.readTextSync(path);
      return parseInboxItems(raw);
    } catch (error) {
      return [];
    }
  }
}
