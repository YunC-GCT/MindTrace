/**
 * AgentInputViewModel.ets — AI 浮窗输入面板 ViewModel
 *
 * 路径: entry/src/main/ets/viewmodels/AgentInputViewModel.ets
 * 职责: 输入面板状态 + 业务意图 (发送/停止/输入更新)
 * 依赖: services/AgentChatService
 *
 * 三层架构:
 *   UI 层       : AgentInputPanel / SendButton / PlusButton / ModeChip (纯渲染)
 *   ViewModel 层: AgentInputViewModel  ← 本文件 (状态 + 意图)
 *   Service 层   : AgentChatService    (LLM 调用编排)
 *
 * 状态字段:
 *   inputText:    当前输入文本
 *   imagePreview: 待发送图片 URI
 *   busy:         AI 是否正在响应
 *
 * 计算方法:
 *   canSend(): 是否可发送 (无 busy 且有内容/图片)
 *
 * 行为:
 *   updateText(v)       : 输入变更
 *   setImagePreview(u)  : 设置待发图片
 *   clearImagePreview() : 清除待发图片
 *   setBusy(v)          : 由 service.setBusy 回调驱动
 *   send()              : 推送 user msg + 调 service captureReply/realReplyStream
 *   stop()              : 停止当前响应 (TODO: 接 service.cancelReply)
 *
 * 依赖注入:
 *   bind(service, addUserMessage): 延迟绑定 (loadHistory 阶段调用)
 */

import { AgentChatService } from '../services/AgentChatService';

@Observed
export class AgentInputViewModel {
  inputText: string = '';
  imagePreview: string = '';
  busy: boolean = false;

  private service: AgentChatService | null = null;
  private addUserMessage: ((content: string) => void) | null = null;

  bind(service: AgentChatService, addUserMessage: (content: string) => void): void {
    this.service = service;
    this.addUserMessage = addUserMessage;
  }

  canSend(): boolean {
    return !this.busy && (this.inputText.trim().length > 0 || this.imagePreview.length > 0);
  }

  setBusy(value: boolean): void {
    this.busy = value;
  }

  updateText(value: string): void {
    this.inputText = value;
  }

  setImagePreview(uri: string): void {
    this.imagePreview = uri;
  }

  clearImagePreview(): void {
    this.imagePreview = '';
  }

  send(): void {
    if (this.service === null || this.addUserMessage === null) {
      return;
    }
    if (!this.canSend()) {
      return;
    }
    const msg: string = this.inputText.trim();
    const uri: string = this.imagePreview;
    const display: string = msg.length > 0 ? msg : '[图片]';
    this.addUserMessage(display);
    this.inputText = '';
    this.imagePreview = '';
    if (uri.length > 0) {
      this.service.captureReply(uri, msg);
    } else {
      this.service.realReplyStream(msg);
    }
  }

  stop(): void {
    // TODO: 接 service.cancelReply (AgentChatService 暂无该方法, 需扩展)
    this.busy = false;
  }
}
