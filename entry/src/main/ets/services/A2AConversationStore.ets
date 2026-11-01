/**
 * A2AConversationStore.ets — 小艺 A2A 会话上下文（spec 040 体验修订）
 *
 * 路径: entry/src/main/ets/services/A2AConversationStore.ets
 * 职责: 小艺端每轮请求 taskId 可能为空，但 message.contextId 稳定；按 contextId（回退 taskId）
 *       持久化最近 6 轮「用户/助手」对话，供下一轮聊天/图片问答注入 memoryContext。
 * 依赖: @kit.CoreFileKit（fileIo）、@kit.AbilityKit（common 类型）。
 * 数据流: AgentExtAbility.runQuery → load/format → A2AChatContext → ReplyContext.memoryContext
 */
import { fileIo } from '@kit.CoreFileKit';
import type { common } from '@kit.AbilityKit';

export interface A2AConversationTurn {
  user: string;
  assistant: string;
  at: number;
}

const MAX_TURNS: number = 6;
const MAX_USER_CHARS: number = 400;
const MAX_ASSISTANT_CHARS: number = 800;

export class A2AConversationStore {
  /** taskId 为空时用 contextId；两者都空用 default（单会话）。 */
  static keyOf(taskId: string, contextId: string): string {
    const raw: string = contextId.length > 0 ? contextId : (taskId.length > 0 ? taskId : 'default');
    let key: string = '';
    for (let i = 0; i < raw.length && key.length < 80; i += 1) {
      const ch: string = raw.charAt(i);
      const code: number = raw.charCodeAt(i);
      if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
        || ch === '-' || ch === '_') {
        key += ch;
      }
    }
    return key.length > 0 ? key : 'default';
  }

  static async load(context: common.Context, key: string): Promise<A2AConversationTurn[]> {
    try {
      const path: string = A2AConversationStore.pathOf(context, key);
      if (!fileIo.accessSync(path)) {
        return [];
      }
      const parsed: Object = JSON.parse(fileIo.readTextSync(path));
      if (!Array.isArray(parsed)) {
        return [];
      }
      const turns: A2AConversationTurn[] = [];
      const list: A2AConversationTurn[] = parsed as A2AConversationTurn[];
      const start: number = list.length > MAX_TURNS ? list.length - MAX_TURNS : 0;
      for (let i = start; i < list.length; i += 1) {
        const turn: A2AConversationTurn | undefined = list[i];
        if (turn !== undefined && typeof turn.user === 'string' && typeof turn.assistant === 'string') {
          turns.push(turn);
        }
      }
      return turns;
    } catch (e) {
      return [];
    }
  }

  static async append(context: common.Context, key: string,
    user: string, assistant: string): Promise<void> {
    if (user.trim().length === 0 || assistant.trim().length === 0) {
      return;
    }
    const turns: A2AConversationTurn[] = await A2AConversationStore.load(context, key);
    turns.push({ user: A2AConversationStore.clip(user, MAX_USER_CHARS),
      assistant: A2AConversationStore.clip(assistant, MAX_ASSISTANT_CHARS), at: Date.now() });
    const kept: A2AConversationTurn[] = turns.length > MAX_TURNS
      ? turns.slice(turns.length - MAX_TURNS) : turns;
    try {
      const dir: string = context.filesDir + '/a2a';
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const file: fileIo.File = fileIo.openSync(A2AConversationStore.pathOf(context, key),
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, JSON.stringify(kept));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      // 记忆失败不影响本轮回复
    }
  }

  /** 注入 ReplyContext.memoryContext 的文本；空历史返回空串。 */
  static format(turns: A2AConversationTurn[]): string {
    if (turns.length === 0) {
      return '';
    }
    const lines: string[] = [];
    for (let i = 0; i < turns.length; i += 1) {
      lines.push('用户: ' + turns[i].user);
      lines.push('助手: ' + turns[i].assistant);
    }
    return '最近对话（按时间顺序，供理解“上一条/刚才”指代）：\n' + lines.join('\n');
  }

  private static pathOf(context: common.Context, key: string): string {
    return context.filesDir + '/a2a/chat-' + A2AConversationStore.keyOf('', key) + '.json';
  }

  private static clip(text: string, limit: number): string {
    return text.length > limit ? text.substring(0, limit) : text;
  }
}
