/**
 * SessionCreator.ets — 会话创建业务
 *
 * 路径: entry/src/main/ets/services/SessionCreator.ets
 * 职责: 创建新 ChatSession (命名 + ID 生成)
 * 依赖: chat/ChatSession (sid), chat/ChatModels (ChatSession 类型)
 *
 * 用法:
 *   import { SessionCreator } from '../../services/SessionCreator';
 *   const s: ChatSession = SessionCreator.newSession(this.sessions.length);
 *   this.sessions = [...this.sessions, s];
 *
 * 当前阶段: 仅创建逻辑, 不含模板/AI 推荐会话名等扩展
 * 后续扩展: 根据最近消息自动命名 / 模板会话 / 导入历史会话等
 */

import { ChatSession } from '../overlays/AgentFloatWindow/chat/ChatModels';
import { sessionIdPolicy } from './ConversationIdentity';

/**
 * 会话创建器 (静态方法, 无状态)
 */
export class SessionCreator {
  /**
   * 创建新会话
   * @param existingCount 当前已存在会话数 (用于命名 "会话 N+1")
   * @returns 新的 ChatSession 实例 (id 已生成, messages 为空)
   */
  static newSession(existingCount: number): ChatSession {
    const nextIndex: number = existingCount + 1;
    return {
      id: sessionIdPolicy.create(),
      name: '会话 ' + nextIndex.toString(),
      messages: [],
    };
  }
}
