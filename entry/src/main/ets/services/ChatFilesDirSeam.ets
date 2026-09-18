/**
 * ChatFilesDirSeam.ets — 聊天文件目录上下文缝(ticket-0.3, #121)
 *
 * 路径: entry/src/main/ets/services/ChatFilesDirSeam.ets
 * 职责: 解析应用级 filesDir 并发布只读 seam(纯字符串 + 状态 + 形状诊断),
 *      供 AgentFloatWindow/ChatSessionManager 使用文件快照路径。
 * 依赖: @kit.AbilityKit(common.ApplicationContext); AppStorage(ArkUI 全局)
 *
 * 注入链路:
 *   EntryAbility.onCreate → publishChatFilesDirSeam → AppStorage
 *   → AgentFloatWindow.loadHistory → ChatSessionManager.recordFilesDir
 *
 * 边界(ticket-0.3 硬门禁):
 * - 不 import / 调用 AtomicFile 与 TaskPool;filesDir 只发布给持久化服务。
 * - 诊断仅由 seam 状态 + filesDir 派生形状构成,绝不含聊天内容/会话名/推理/密钥。
 * - Preferences 聊天历史(chat_history/sessions)仅作为迁移读取源,本文件不读写历史内容。
 *
 * ArkTS 1.1 strict 适配: static 方法内不用 this,一律用类名;catch 变量不标注类型。
 */

import { common } from '@kit.AbilityKit';

// seam 状态: 解析成功或阻塞(空 filesDir / 读取失败)
export type ChatFilesDirSeamState = 'resolved' | 'blocked';

// 未来快照的相对形状(spec 021 §10 固定): <filesDir>/chat-history/sessions.json
const RELATIVE_SHAPE_VALUE: string = 'chat-history/sessions.json';

// AppStorage 存储键(组合根注入约定)
const CHAT_FILES_DIR_SEAM_KEY: string = 'chatFilesDirSeam';

export class ChatFilesDirSeam {
  readonly filesDir: string;
  readonly state: ChatFilesDirSeamState;
  readonly diagnostic: string;

  static readonly RELATIVE_SHAPE: string = RELATIVE_SHAPE_VALUE;

  constructor(filesDir: string, state: ChatFilesDirSeamState, diagnostic: string) {
    this.filesDir = filesDir;
    this.state = state;
    this.diagnostic = diagnostic;
  }

  // 纯形状助手: <filesDir>/chat-history
  static snapshotDir(filesDir: string): string {
    return filesDir + '/chat-history';
  }

  // 纯形状助手: <filesDir>/chat-history/sessions.json
  static snapshotFile(filesDir: string): string {
    return ChatFilesDirSeam.snapshotDir(filesDir) + '/sessions.json';
  }

  // 纯工厂: 非空解析,空则阻塞,绝不伪造目录
  static fromFilesDir(filesDir: string): ChatFilesDirSeam {
    if (filesDir.length > 0) {
      return new ChatFilesDirSeam(filesDir, 'resolved', ChatFilesDirSeam.buildResolvedDiagnostic());
    }
    return new ChatFilesDirSeam('', 'blocked', ChatFilesDirSeam.buildBlockedDiagnostic());
  }

  // 薄适配器: 读取应用级 filesDir;空值或抛错均落到 blocked
  static fromApplicationContext(ctx: common.ApplicationContext): ChatFilesDirSeam {
    try {
      return ChatFilesDirSeam.fromFilesDir(ctx.filesDir);
    } catch (e) {
      return ChatFilesDirSeam.fromFilesDir('');
    }
  }

  private static buildResolvedDiagnostic(): string {
    return 'seam=resolved; shape=' + ChatFilesDirSeam.RELATIVE_SHAPE;
  }

  private static buildBlockedDiagnostic(): string {
    return 'seam=blocked; filesDir unavailable; shape=' + ChatFilesDirSeam.RELATIVE_SHAPE;
  }
}

// 可注入存储: 生产实现基于 AppStorage,测试用内存 fake 替换
export interface ChatFilesDirSeamStore {
  read(): ChatFilesDirSeam | null;
  write(seam: ChatFilesDirSeam): void;
}

class AppStorageChatFilesDirSeamStore implements ChatFilesDirSeamStore {
  read(): ChatFilesDirSeam | null {
    const value: ChatFilesDirSeam | undefined = AppStorage.get<ChatFilesDirSeam>(CHAT_FILES_DIR_SEAM_KEY);
    return value === undefined ? null : value;
  }

  write(seam: ChatFilesDirSeam): void {
    AppStorage.setOrCreate<ChatFilesDirSeam>(CHAT_FILES_DIR_SEAM_KEY, seam);
  }
}

let activeStore: ChatFilesDirSeamStore = new AppStorageChatFilesDirSeamStore();

// 组合根(EntryAbility)发布 seam;重发覆盖旧值
export function publishChatFilesDirSeam(seam: ChatFilesDirSeam): void {
  activeStore.write(seam);
}

// 浮窗读取 seam;未发布时返回 null
export function getChatFilesDirSeam(): ChatFilesDirSeam | null {
  return activeStore.read();
}

// 测试缝: 替换存储实现(镜像 ArkWebWarmupService 适配器模式)
export function setChatFilesDirSeamStoreForTest(store: ChatFilesDirSeamStore): void {
  activeStore = store;
}

// 测试缝: 恢复生产 AppStorage 实现
export function resetChatFilesDirSeamForTest(): void {
  activeStore = new AppStorageChatFilesDirSeamStore();
}
