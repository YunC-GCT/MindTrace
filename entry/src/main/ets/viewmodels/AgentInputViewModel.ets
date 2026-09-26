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
 *   bind(service, resolveActiveSessionId, ensureActiveSession): 延迟绑定 (loadHistory 阶段调用)
 */

import { AgentChatService } from '../services/AgentChatService';
import { NoteDraftReadyEvent } from 'common';
import type { NoteGenerationRoute } from 'common';

export interface SessionUiState {
  composerText: string;
  imageUri: string;
  draft?: NoteDraftReadyEvent;
  progress?: string;
  error?: string;
  retryTarget?: string;
}

function emptySessionUiState(): SessionUiState {
  return { composerText: '', imageUri: '' };
}

function copySessionUiState(state: SessionUiState): SessionUiState {
  const copy: SessionUiState = { composerText: state.composerText, imageUri: state.imageUri };
  if (state.draft !== undefined) { copy.draft = state.draft; }
  if (state.progress !== undefined) { copy.progress = state.progress; }
  if (state.error !== undefined) { copy.error = state.error; }
  if (state.retryTarget !== undefined) { copy.retryTarget = state.retryTarget; }
  return copy;
}

export class SessionUiStateStore {
  private readonly states: Map<string, SessionUiState> = new Map<string, SessionUiState>();

  register(sessionId: string): void {
    if (!this.states.has(sessionId)) { this.states.set(sessionId, emptySessionUiState()); }
  }

  has(sessionId: string): boolean { return this.states.has(sessionId); }

  read(sessionId: string): SessionUiState {
    const state: SessionUiState | undefined = this.states.get(sessionId);
    return state === undefined ? emptySessionUiState() : copySessionUiState(state);
  }

  write(sessionId: string, state: SessionUiState): boolean {
    if (!this.states.has(sessionId)) { return false; }
    this.states.set(sessionId, copySessionUiState(state));
    return true;
  }

  setImage(sessionId: string, uri: string): boolean {
    const state: SessionUiState | undefined = this.states.get(sessionId);
    if (state === undefined) { return false; }
    state.imageUri = uri;
    return true;
  }

  setDraft(sessionId: string, draft: NoteDraftReadyEvent | undefined): boolean {
    const state: SessionUiState | undefined = this.states.get(sessionId);
    if (state === undefined) { return false; }
    state.draft = draft;
    return true;
  }

  setProgress(sessionId: string, progress: string | undefined): boolean {
    const state: SessionUiState | undefined = this.states.get(sessionId);
    if (state === undefined) { return false; }
    state.progress = progress;
    return true;
  }

  setError(sessionId: string, error: string | undefined): boolean {
    const state: SessionUiState | undefined = this.states.get(sessionId);
    if (state === undefined) { return false; }
    state.error = error;
    return true;
  }

  setRetryTarget(sessionId: string, retryTarget: string | undefined): boolean {
    const state: SessionUiState | undefined = this.states.get(sessionId);
    if (state === undefined) { return false; }
    state.retryTarget = retryTarget;
    return true;
  }

  remove(sessionId: string): void { this.states.delete(sessionId); }
}

@Observed
export class AgentInputViewModel {
  inputText: string = '';
  imagePreview: string = '';
  busy: boolean = false;
  private readonly busySessions: Set<string> = new Set<string>();
  private readonly uiStates: SessionUiStateStore = new SessionUiStateStore();
  private activeSessionId: string = '';
  route: NoteGenerationRoute = 'standard';

  private service: AgentChatService | null = null;
  private resolveActiveSessionId: (() => string) | null = null;
  private ensureActiveSession: (() => string) | null = null;

  bind(
    service: AgentChatService,
    resolveActiveSessionId: () => string,
    ensureActiveSession: (() => string) | null = null,
  ): void {
    this.service = service;
    this.resolveActiveSessionId = resolveActiveSessionId;
    this.ensureActiveSession = ensureActiveSession;
  }

  canSend(): boolean {
    const sessionId: string = this.resolveActiveSessionId === null ? '' : this.resolveActiveSessionId();
    return !this.isBusy(sessionId) && (this.inputText.trim().length > 0 || this.imagePreview.length > 0);
  }

  setBusy(value: boolean): void {
    this.busy = value;
  }

  setBusyForSession(sessionId: string, value: boolean): void {
    if (value) {
      this.busySessions.add(sessionId);
    } else {
      this.busySessions.delete(sessionId);
    }
    const active: string = this.resolveActiveSessionId === null ? '' : this.resolveActiveSessionId();
    this.busy = this.busySessions.has(active);
  }

  isBusy(sessionId: string): boolean {
    return this.busySessions.has(sessionId);
  }

  syncBusy(sessionId: string): void {
    this.busy = this.busySessions.has(sessionId);
  }

  updateText(value: string): void {
    this.inputText = value;
    this.saveProjectedState();
  }

  setRoute(route: NoteGenerationRoute): void {
    this.route = route;
  }

  setImagePreview(uri: string): void {
    this.imagePreview = uri;
    this.saveProjectedState();
  }

  setImagePreviewForSession(sessionId: string, uri: string): boolean {
    const accepted: boolean = this.uiStates.setImage(sessionId, uri);
    if (accepted && sessionId === this.activeSessionId) { this.imagePreview = uri; }
    return accepted;
  }

  clearImagePreview(): void {
    this.imagePreview = '';
    this.saveProjectedState();
  }

  registerSession(sessionId: string): void { this.uiStates.register(sessionId); }

  switchSession(sessionId: string): void {
    this.saveProjectedState();
    this.uiStates.register(sessionId);
    this.activeSessionId = sessionId;
    const state: SessionUiState = this.uiStates.read(sessionId);
    this.inputText = state.composerText;
    this.imagePreview = state.imageUri;
    this.syncBusy(sessionId);
  }

  removeSession(sessionId: string): void {
    this.uiStates.remove(sessionId);
    this.busySessions.delete(sessionId);
    if (this.activeSessionId === sessionId) {
      this.activeSessionId = '';
      this.inputText = '';
      this.imagePreview = '';
      this.busy = false;
    }
  }

  setDraftForSession(sessionId: string, draft: NoteDraftReadyEvent | undefined): boolean {
    return this.uiStates.setDraft(sessionId, draft);
  }

  draftForSession(sessionId: string): NoteDraftReadyEvent | undefined {
    return this.uiStates.read(sessionId).draft;
  }

  setProgressForSession(sessionId: string, progress: string | undefined): boolean {
    return this.uiStates.setProgress(sessionId, progress);
  }

  setErrorForSession(sessionId: string, error: string | undefined): boolean {
    return this.uiStates.setError(sessionId, error);
  }

  setRetryTargetForSession(sessionId: string, retryTarget: string | undefined): boolean {
    return this.uiStates.setRetryTarget(sessionId, retryTarget);
  }

  stateForSession(sessionId: string): SessionUiState { return this.uiStates.read(sessionId); }

  send(): void {
    if (this.service === null || this.resolveActiveSessionId === null) {
      return;
    }
    if (!this.canSend()) {
      return;
    }
    const msg: string = this.inputText.trim();
    const uri: string = this.imagePreview;
    const sessionId: string = this.ensureActiveSession === null
      ? this.resolveActiveSessionId()
      : this.ensureActiveSession();
    if (sessionId.length === 0) {
      return;
    }
    const route: NoteGenerationRoute = this.route;
    this.inputText = '';
    this.imagePreview = '';
    this.saveProjectedState();
    if (uri.length > 0) {
      this.service.captureReply(sessionId, uri, msg, route);
    } else {
      this.service.realReplyStream(sessionId, msg, route);
    }
  }

  stop(): void {
    if (this.service !== null && this.resolveActiveSessionId !== null) {
      this.service.cancelSessionRun(this.resolveActiveSessionId());
    }
    const active: string = this.resolveActiveSessionId === null ? '' : this.resolveActiveSessionId();
    this.setBusyForSession(active, false);
  }

  private saveProjectedState(): void {
    if (this.activeSessionId.length === 0 || !this.uiStates.has(this.activeSessionId)) { return; }
    const current: SessionUiState = this.uiStates.read(this.activeSessionId);
    current.composerText = this.inputText;
    current.imageUri = this.imagePreview;
    this.uiStates.write(this.activeSessionId, current);
  }
}
