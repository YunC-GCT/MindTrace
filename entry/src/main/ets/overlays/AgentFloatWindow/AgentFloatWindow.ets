// ============================================================================
//  overlays/AgentFloatWindow/AgentFloatWindow.ets — 智能体浮窗(完整版)
//  ----------------------------------------------------------------------------
//  特性: 拖拽缩放(floatHeight) · 多会话(ChatSession + SessionCreator) · 拍照整链(captureReply)
//  子组件: ChatHeader / AgentMessageList / ImagePreviewBar / AgentInputPanel
//  业务: AgentChatService / ModelSelector / SessionCreator
//  ============================================================================

import {
  BG_DARK, TEXT, TEXT_4, BORDER,
  S_2, S_3, S_4, S_6, R_XL,
  F_MD, W_SEMIBOLD,
  OVERLAY_MASK, SCREEN_H,
  DUR_FAST, DUR_BASE,
} from 'common';
import { common } from '@kit.AbilityKit';
import window from '@ohos.window';
import { AgentChatService, AgentChatCallbacks } from '../../services/AgentChatService';
import { getChatFilesDirSeam } from '../../services/ChatFilesDirSeam';
import { ModelSelector } from '../../services/ModelSelector';
import { SessionCreator } from '../../services/SessionCreator';
import { CameraKitLauncher } from '../../services/CameraKitLauncher';
import { AlbumPickerLauncher } from '../../services/AlbumPickerLauncher';
import { ChatHeader } from './chat/ChatHeader';
import { ChatSessionManager } from './chat/ChatSession';
import {
  ChatMessageOrigin,
  ChatMessageOutcome,
  ChatMsg,
  ChatSession,
  ChatStatusMeta,
  applyStreamEventToChatMsg,
  transitionChatMessageOutcome,
  finishChatMsg,
  replaceChatMsgContent,
} from './chat/ChatModels';
import { SessionsPanel } from './chat/SessionsPanel';
import { AgentMessageList } from './AgentMessageList';
import { ImagePreviewBar } from './ImagePreviewBar';
import { AgentInputPanel } from './AgentInputPanel';
import { AgentInputViewModel } from '../../viewmodels/AgentInputViewModel';
import { SessionsPanelController } from '../../services/SessionsPanelController';
import { NoteDraftReadyEvent, NoteGenerationRun } from 'common';
import { NoteDetailOverlay } from '../NoteDetailOverlay/NoteDetailOverlay';
import { KnowledgeUnit } from 'common';
import type { StreamEvent } from 'common';
import { ConversationRunRef, chatMessageIdPolicy } from '../../services/ConversationIdentity';
import { AiService } from '../../services/AiService';
import { DraftRecoveryService } from '../../services/DraftRecoveryService';
import {
  SessionDeletionCoordinator,
  SessionDeletionResult,
} from '../../services/SessionDeletionCoordinator';
import { ChatContextProjectionService } from '../../services/ChatContextProjectionService';
import { ConversationSnapshotMapper } from '../../services/ConversationSnapshotMapper';
import { ConversationTitleService } from '../../services/ConversationTitleService';
import {
  ConversationSessionEvent,
  ConversationSessionReduceResult,
  ConversationSessionReducer,
} from '../../services/ConversationSessionReducer';
import { ConversationSessionSnapshot } from '../../models/ConversationSnapshotModels';

const FLOAT_SHEET_OPEN_OFFSET: number = 22;
const FLOAT_SHEET_CLOSE_OFFSET: number = 18;
const FLOAT_UNMOUNT_DELAY_MS: number = DUR_FAST + 40;
const CHAT_HEADER_HEIGHT: number = 44;
const HEADER_SEPARATOR_HEIGHT: number = 0.5;
const PANEL_MASK_TOP: number = S_6 + CHAT_HEADER_HEIGHT + HEADER_SEPARATOR_HEIGHT;
const PANEL_Z_INDEX: number = 2;
const PANEL_MASK_Z_INDEX: number = 1;

@Component
export struct AgentFloatWindow {
  @Prop @Watch('onShowChange') show: boolean = false;
  onClose: () => void = (): void => {};
  @Prop @Watch('onPendingImageChange') pendingImageUri: string = '';

  @State @Watch('onMessagesChange') messages: ChatMsg[] = [];
  @State keyboardHeight: number = 0;
  @State sessions: ChatSession[] = [];
  @State @Watch('onActiveSessionChange') activeSid: string = '';
  @State activeSessionTitle: string = '新对话';
  @State floatHeight: number = 48;
  @State overlayVisible: boolean = false;
  @State maskOpacity: number = 0;
  @State sheetOpacity: number = 0;
  @State sheetOffset: number = FLOAT_SHEET_OPEN_OFFSET;
  @State panelVisible: boolean = false;
  @State generatedDraft: NoteDraftReadyEvent | null = null;
  private generatedDraftSessionId: string = '';
  private motionSeq: number = 0;
  private dragStartH: number = 48;
  private mainWindow: window.Window | null = null;
  private scroller: Scroller = new Scroller();
  private sm: ChatSessionManager = new ChatSessionManager();
  private service: AgentChatService | null = null;
  private deletionCoordinator: SessionDeletionCoordinator | null = null;
  private draftRecovery: DraftRecoveryService | null = null;
  @State inputVm: AgentInputViewModel = new AgentInputViewModel();

  // ===== 生命周期 =====

  aboutToAppear(): void {
    this.loadHistory();
    this.initKeyboard();
    if (this.show) {
      this.overlayVisible = true;
      this.maskOpacity = 1;
      this.sheetOpacity = 1;
      this.sheetOffset = 0;
    }
  }
  aboutToDisappear(): void {
    this.service?.cancelAllRuns();
    if (this.mainWindow) {
      this.mainWindow.off('keyboardHeightChange');
    }
    this.sync();
    this.sm.flush(this.sessions).catch((): void => {});
  }
  onShowChange(): void {
    if (this.show) {
      this.openAnimated();
      return;
    }
    this.sync();
    this.sm.flush(this.sessions).catch((): void => {});
    this.closeAnimated();
  }
  onPendingImageChange(): void {
    this.sync();
    this.sm.flush(this.sessions).catch((): void => {});
    if (this.pendingImageUri.length > 0) {
      this.inputVm.setImagePreview(this.pendingImageUri);
    }
  }
  onMessagesChange(): void {
    if (this.messages.length > 0) {
      this.sync();
      this.sm.save(this.sessions).catch((): void => {});
    }
  }

  private initKeyboard(): void {
    try { const ctx = this.getUIContext().getHostContext();
      if (ctx) { window.getLastWindow(ctx).then((w: window.Window) => { this.mainWindow = w; w.on('keyboardHeightChange', (d: number) => { try { this.keyboardHeight = this.getUIContext().px2vp(d); } catch (e) { } }); }).catch(() => {}); }
    } catch (e) {}
  }

  // ===== 会话管理 =====

  private async loadHistory(): Promise<void> {
    // ticket-0.3 (#121): 每次浮窗初始化重读 seam,把解析到的 filesDir 交给非 UI 协作者
    const seam = getChatFilesDirSeam();
    this.sm.recordFilesDir(seam !== null ? seam.filesDir : '');
    const inputVm: AgentInputViewModel = this.inputVm;
    const cbs: AgentChatCallbacks = {
      addUserMsg: (ref: ConversationRunRef, content: string, origin: ChatMessageOrigin): number => {
        const id: number = chatMessageIdPolicy.create();
        const session: ChatSession | undefined = this.sessions.find(
          (item: ChatSession): boolean => item.id === ref.sessionId,
        );
        const firstUserMessage: boolean = session !== undefined
          && !session.messages.some((message: ChatMsg): boolean => message.role === 'user');
        const accepted: boolean = this.updateSessionMessages(ref, 'add-user-message', (messages: ChatMsg[]): ChatMsg[] => [...messages, {
          id: id, messageKey: ref.runId + ':user', sequence: id, role: 'user', content: content,
          ts: Date.now(), streaming: false, reasoning: '', origin: origin, outcome: 'completed', runId: ref.runId,
        }]);
        if (accepted && firstUserMessage) {
          this.updateSessionTitle(ref.sessionId, ConversationTitleService.fromFirstMessage(content));
        }
        return accepted ? id : -1;
      },
      addAiMsg: (ref: ConversationRunRef, c: string, origin?: ChatMessageOrigin, outcome?: ChatMessageOutcome): number => {
        const id: number = chatMessageIdPolicy.create();
        this.updateSessionMessages(ref, 'add-ai-message', (messages: ChatMsg[]): ChatMsg[] => [...messages, {
          id: id, messageKey: ref.runId + ':assistant:' + id.toString(), sequence: id, role: 'ai', content: c,
          ts: Date.now(), streaming: false, reasoning: '', origin: origin ?? 'chat',
          outcome: outcome ?? 'completed', runId: ref.runId,
        }]);
        return id;
      },
      addAiMsgEmpty: (ref: ConversationRunRef, origin: ChatMessageOrigin): number => {
        const id: number = chatMessageIdPolicy.create();
        this.updateSessionMessages(ref, 'add-ai-placeholder', (messages: ChatMsg[]): ChatMsg[] => [...messages, {
          id: id, messageKey: ref.runId + ':assistant:' + id.toString(), sequence: id, role: 'ai', content: '',
          ts: Date.now(), streaming: true, reasoning: '', origin: origin, runId: ref.runId,
        }]);
        return id;
      },
appendAiMsg: (ref: ConversationRunRef, id: number, event: StreamEvent): void => {
        this.updateSessionMessages(ref, 'append-ai-message', (messages: ChatMsg[]): ChatMsg[] => messages.map((m: ChatMsg): ChatMsg => m.id === id ? applyStreamEventToChatMsg(m, event) : m));
      },
      replaceAiMsg: (ref: ConversationRunRef, id: number, content: string): void => {
        this.updateSessionMessages(ref, 'replace-ai-message', (messages: ChatMsg[]): ChatMsg[] => messages.map((m: ChatMsg): ChatMsg => m.id === id ? replaceChatMsgContent(m, content) : m));
      },
      finishAiMsg: (ref: ConversationRunRef, id: number, outcome?: ChatMessageOutcome): void => {
        this.updateSessionMessages(ref, 'finish-ai-message', (messages: ChatMsg[]): ChatMsg[] => messages.map((m: ChatMsg): ChatMsg => m.id === id ? transitionChatMessageOutcome(m, outcome ?? 'completed') : m));
        this.sync();
        this.sm.flush(this.sessions).catch((): void => {});
      },
      terminateAiRun: (ref: ConversationRunRef, outcome: ChatMessageOutcome): void => {
        this.updateSessionMessages(ref, 'finish-ai-message', (messages: ChatMsg[]): ChatMsg[] => messages.map((m: ChatMsg): ChatMsg => {
          if (m.role === 'ai' && m.runId === ref.runId && m.outcome === undefined) {
            return transitionChatMessageOutcome(m, outcome);
          }
          return m;
        }));
        this.sync();
        this.sm.flush(this.sessions).catch((): void => {});
      },
      getUserMessageId: (ref: ConversationRunRef): number => {
        const session: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === ref.sessionId);
        if (session === undefined) { return -1; }
        for (const message of session.messages) {
          if (message.role === 'user' && message.runId === ref.runId) { return message.id; }
        }
        return -1;
      },
      commitHistory: async (ref: ConversationRunRef): Promise<boolean> => {
        if (!this.sessionExists(ref.sessionId)) { return false; }
        this.sync();
        const result = await this.sm.flush(this.sessions);
        return result.success;
      },
      reportDiagnostic: (ref: ConversationRunRef, diagnostic: string): void => {
        this.inputVm.setErrorForSession(ref.sessionId, diagnostic);
        this.inputVm.setRetryTargetForSession(ref.sessionId, ref.runId);
      },
      cancelDraftsByRun: async (sessionId: string, parentConversationRunId: string): Promise<void> => {
        await new AiService(getContext(this) as common.UIAbilityContext)
          .cancelDraftsByParentRun(sessionId, parentConversationRunId);
      },
      setBusy: (ref: ConversationRunRef, v: boolean): void => { inputVm.setBusyForSession(ref.sessionId, v); },
      setStatusMeta: (ref: ConversationRunRef, meta: ChatStatusMeta | null): void => {
        inputVm.setProgressForSession(ref.sessionId, meta === null ? undefined : meta.title);
      },
      getContext: (): common.UIAbilityContext => getContext(this) as common.UIAbilityContext,
      getConversationText: (ref: ConversationRunRef, excludeLatestUser: boolean): string => this.buildConversationTextForSession(ref, excludeLatestUser),
      onDraftReady: (ref: ConversationRunRef, event: NoteDraftReadyEvent): void => {
        if (event.originSessionId === ref.sessionId && this.service?.isCurrentRun(ref) === true
          && this.sessionExists(ref.sessionId) && this.inputVm.setDraftForSession(ref.sessionId, event)) {
          if (ref.sessionId === this.activeSid) {
            this.generatedDraft = event;
            this.generatedDraftSessionId = ref.sessionId;
          }
        } else {
          console.warn('[ConversationRun] code=DRAFT_TARGET_REJECTED; sessionId=' + ref.sessionId + '; runId=' + ref.runId);
        }
      },
    };
    const service: AgentChatService = new AgentChatService(cbs);
    this.service = service;
    this.draftRecovery = new DraftRecoveryService(getContext(this) as common.UIAbilityContext);
    const ss: ChatSession[] = await this.sm.init(getContext(this));
    const snapshotPath: string = this.sm.getResolvedSnapshotPath();
    this.deletionCoordinator = new SessionDeletionCoordinator(
      getContext(this) as common.UIAbilityContext,
      snapshotPath.length > 0 ? snapshotPath + '.deletions' : '',
      (sessions: ConversationSessionSnapshot[]) => this.sm.flush(ConversationSnapshotMapper.retainExistingSessions(sessions, this.sessions)),
      async (sessionId: string): Promise<void> => {
        await service.cancelSessionRun(sessionId);
      },
    );
    // Development reset: s1 was the old bootstrap conversation and must not
    // be promoted to a real history item after the lazy-session migration.
    const loadedSessions: ChatSession[] = ss.filter((session: ChatSession): boolean => session.id !== 's1');
    await this.deletionCoordinator.replay(ConversationSnapshotMapper.fromSessions(loadedSessions));
    const projection = await new ChatContextProjectionService(
      getContext(this) as common.UIAbilityContext,
    ).reconcile(ConversationSnapshotMapper.fromSessions(loadedSessions));
    if (projection.failures > 0) { console.warn('[ChatProjection] ' + projection.diagnostic); }
    if (loadedSessions.length > 0) {
      this.sessions = loadedSessions;
      this.activateSession(loadedSessions[0]);
    } else {
      this.sessions = [];
      this.activeSid = '';
      this.activeSessionTitle = '新对话';
      this.messages = [];
    }
    this.inputVm.bind(
      service,
      (): string => this.activeSid,
      (): string => this.ensureActiveSession(),
    );
    for (const session of loadedSessions) {
      this.inputVm.registerSession(session.id);
    }
    await this.restoreDraftsAfterHistoryLoad(service, loadedSessions);
  }

  private async restoreDraftsAfterHistoryLoad(
    service: AgentChatService,
    loadedSessions: ChatSession[],
  ): Promise<void> {
    let detached: NoteDraftReadyEvent | null = null;
    try {
      const recoverable: NoteGenerationRun[] = await service.listRecoverableDrafts();
      for (const draft of recoverable) {
        if (draft.originSessionId === undefined) {
          try {
            if (this.draftRecovery === null) { throw new Error('DETACHED_DRAFT_RECOVERY_UNAVAILABLE'); }
            detached = await this.draftRecovery.restore(draft.id);
          } catch (error) {
            console.warn('[NoteDraftRecovery] code=DETACHED_DRAFT_RESTORE_FAILED; runId=' + draft.id);
          }
          continue;
        }
        const session: ChatSession | undefined = loadedSessions.find(
          (candidate: ChatSession): boolean => candidate.id === draft.originSessionId,
        );
        if (session === undefined) { continue; }
        try {
          const event: NoteDraftReadyEvent | null = await service.checkAndRestoreDrafts(session.id);
          if (event !== null) {
            this.inputVm.setDraftForSession(session.id, event);
            if (session.id === this.activeSid) {
              this.generatedDraft = event;
              this.generatedDraftSessionId = session.id;
            }
          }
        } catch (error) {
          console.warn('[NoteDraftRecovery] code=SESSION_DRAFT_RESTORE_FAILED; sessionId=' + session.id);
        }
      }
    } catch (error) {
      console.warn('[NoteDraftRecovery] code=LIST_RECOVERABLE_DRAFTS_FAILED');
    }
    if (this.generatedDraft === null && detached !== null) {
      this.generatedDraft = detached;
      this.generatedDraftSessionId = '';
    }
  }

  private sync(): void {
    const s: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === this.activeSid);
    if (s !== undefined) { s.messages = this.messages; }
  }

  private buildConversationText(messages: ChatMsg[], excludeLatestUser: boolean): string {
    const parts: string[] = [];
    const end: number = excludeLatestUser
      && messages.length > 0
      && messages[messages.length - 1].role === 'user'
      ? messages.length - 1
      : messages.length;
    let i: number = 0;
    while (i < end) {
      const msg: ChatMsg = messages[i];
      const role: string = msg.role === 'user' ? '用户' : 'AI';
      if (msg.content.trim().length > 0) {
        parts.push(role + ': ' + msg.content.trim());
      }
      i += 1;
    }
    return parts.join('\n\n');
  }
  private sessionExists(sessionId: string): boolean { return this.sessions.some((item: ChatSession): boolean => item.id === sessionId); }
  private buildConversationTextForSession(ref: ConversationRunRef, excludeLatestUser: boolean): string {
    if (this.service?.isCurrentRun(ref) !== true) { return ''; }
    const target: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === ref.sessionId);
    if (target === undefined) { return ''; }
    return this.buildConversationText(target.messages, excludeLatestUser);
  }
  private updateSessionMessages(ref: ConversationRunRef, event: ConversationSessionEvent, update: (messages: ChatMsg[]) => ChatMsg[]): boolean {
    const current: boolean = this.service?.isCurrentRun(ref) === true;
    const result: ConversationSessionReduceResult = ConversationSessionReducer.updateMessages(this.sessions, ref, current, event, update);
    if (!result.accepted) {
      console.warn('[ConversationRun] ' + result.diagnostic);
      return false;
    }
    this.sessions = result.sessions;
    if (ref.sessionId === this.activeSid) {
      const target: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === ref.sessionId);
      if (target !== undefined) { this.messages = target.messages; }
    }
    return true;
  }

  private updateSessionTitle(sessionId: string, title: string): void {
    const next: ChatSession[] = [];
    for (const session of this.sessions) {
      if (session.id === sessionId) {
        next.push({ id: session.id, name: title, messages: session.messages });
      } else {
        next.push(session);
      }
    }
    this.sessions = next;
    if (this.activeSid === sessionId) { this.activeSessionTitle = title; }
  }
  private switchSession(sid: string): void {
    this.sync();
    this.sm.flush(this.sessions).catch((): void => {});
    const s: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === sid);
    if (s !== undefined) {
      this.activateSession(s);
      this.inputVm.syncBusy(sid);
      const draft: NoteDraftReadyEvent | undefined = this.inputVm.draftForSession(sid);
      this.generatedDraft = draft ?? null;
      this.generatedDraftSessionId = draft === undefined ? '' : sid;
    }
  }
  private newSession(): void {
    this.sync();
    const session: ChatSession = SessionCreator.newSession(this.sessions.length);
    this.sessions = [...this.sessions, session];
    this.activateSession(session);
    this.inputVm.switchSession(session.id);
    this.generatedDraft = null;
    this.generatedDraftSessionId = '';
    this.sm.flush(this.sessions).catch((): void => {});
    this.panelVisible = false;
  }

  private ensureActiveSession(): string {
    if (this.activeSid.length > 0 && this.sessionExists(this.activeSid)) {
      return this.activeSid;
    }
    const session: ChatSession = SessionCreator.newSession(this.sessions.length);
    this.sessions = [...this.sessions, session];
    this.activateSession(session);
    this.inputVm.switchSession(session.id);
    this.generatedDraft = null;
    this.generatedDraftSessionId = '';
    return session.id;
  }

  private togglePanel(): void { this.panelVisible = !this.panelVisible; }
  private closePanel(): void { this.panelVisible = false; }

  private activateSession(session: ChatSession): void {
    this.inputVm.registerSession(session.id);
    this.inputVm.switchSession(session.id);
    this.activeSessionTitle = session.name;
    this.activeSid = session.id;
    this.messages = session.messages;
  }

  private onActiveSessionChange(): void {
    const session: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === this.activeSid);
    if (session !== undefined && this.activeSessionTitle !== session.name) {
      this.activeSessionTitle = session.name;
    }
  }

  private onSelectSession(sid: string): void { this.switchSession(sid); this.panelVisible = false; }

  private onRequestSessionDelete(sid: string): void {
    if (this.sessions.length <= 1) {
      return;
    }
    const target: ChatSession | undefined = this.sessions.find((s: ChatSession): boolean => s.id === sid);
    if (target === undefined) {
      return;
    }
    SessionsPanelController.requestDelete(
      this.getUIContext().getPromptAction(),
      sid,
      target.name,
      (deletedSid: string): void => { this.deleteSession(deletedSid).catch((): void => {}); },
      (): void => { this.showToast('无法打开删除确认，请稍后重试'); }
    );
  }
  private async deleteSession(sid: string): Promise<void> {
    if (this.sessions.length <= 1) {
      return;
    }
    this.sync();
    const remaining: ChatSession[] = this.sessions.filter((s: ChatSession): boolean => s.id !== sid);
    if (this.deletionCoordinator === null) { return; }
    const result: SessionDeletionResult = await this.deletionCoordinator.deleteSession(
      sid,
      ConversationSnapshotMapper.fromSessions(remaining),
    );
    if (result.state === 'failed-before-commit') {
      console.warn('[SessionDeletion] ' + result.diagnostic + '; sessionId=' + sid);
      return;
    }
    this.inputVm.removeSession(sid);
    this.sessions = remaining;
    if (sid === this.activeSid) {
      this.activateSession(remaining[0]);
      const draft: NoteDraftReadyEvent | undefined = this.inputVm.draftForSession(this.activeSid);
      this.generatedDraft = draft ?? null;
      this.generatedDraftSessionId = draft === undefined ? '' : this.activeSid;
    }
    if (result.state === 'cleanup-pending') {
      console.warn('[SessionDeletion] ' + result.diagnostic + '; sessionId=' + sid);
    }
  }

  private finishMessage(message: ChatMsg): ChatMsg { return transitionChatMessageOutcome(message, 'completed'); }

  // ===== 交互逻辑 (输入面板已迁出至 AgentInputViewModel; 模型显示已迁出至 ModelSelector; 会话创建已迁出至 SessionCreator; 相机/相册已迁出至 CameraKitLauncher / AlbumPickerLauncher) =====

  private stopStreaming = (): void => {
    this.inputVm.stop();
    this.finishCurrentStreamingMessage();
    this.sync();
    this.sm.flush(this.sessions).catch((): void => {});
  };

  private finishCurrentStreamingMessage(): boolean {
    if (this.messages.length === 0 || !this.messages[this.messages.length - 1].streaming) {
      return false;
    }
    this.messages = this.messages.map((message: ChatMsg, index: number): ChatMsg =>
      index === this.messages.length - 1 ? this.finishMessage(message) : message,
    );
    return true;
  }

  // Toast 反馈 (替代 deprecated promptAction.showToast, 用 UIContext.getPromptAction)
  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 1500,
      });
    } catch (e) {
      console.warn('[AgentFloatWindow] toast failed: ' + (e as Error).message);
    }
  }

  // + 弹窗 → 相机: 拉起 HarmonyOS 系统相机选择器, 拍完写入 VM + Toast
  private onCameraAction = (): void => {
    this.sync();
    this.sm.flush(this.sessions).catch((): void => {});
    const originSessionId: string = this.ensureActiveSession();
    CameraKitLauncher.capture(getContext(this) as common.UIAbilityContext)
      .then((uri: string): void => {
        if (!this.inputVm.setImagePreviewForSession(originSessionId, uri)) {
          console.warn('[SessionUiState] code=LATE_PICKER_TARGET_DELETED; sessionId=' + originSessionId);
          return;
        }
        this.showToast('已选图片');
      })
      .catch((e: Error): void => {
        this.showToast('相机启动失败: ' + e.message);
      });
  };

  // + 弹窗 → 相册: 拉起 HarmonyOS 系统相册选择器, 选完写入 VM + Toast
  private onAlbumAction = (): void => {
    this.sync();
    this.sm.flush(this.sessions).catch((): void => {});
    const originSessionId: string = this.ensureActiveSession();
    AlbumPickerLauncher.pick(getContext(this) as common.UIAbilityContext)
      .then((uris: string[]): void => {
        if (uris.length > 0) {
          if (!this.inputVm.setImagePreviewForSession(originSessionId, uris[0])) {
            console.warn('[SessionUiState] code=LATE_PICKER_TARGET_DELETED; sessionId=' + originSessionId);
            return;
          }
          this.showToast('已选图片');
        } else {
          this.showToast('未选择图片');
        }
      })
      .catch((e: Error): void => {
        this.showToast('相册启动失败: ' + e.message);
      });
  };

  private confirmDraft = async (candidate: KnowledgeUnit): Promise<KnowledgeUnit> => {
    if (this.generatedDraft === null || this.service === null) {
      throw new Error('草稿服务不可用');
    }
    if (this.generatedDraftSessionId.length === 0) {
      if (this.draftRecovery === null) { throw new Error('DETACHED_DRAFT_RECOVERY_UNAVAILABLE'); }
      return await this.draftRecovery.confirm(this.generatedDraft, candidate);
    }
    return await this.service.confirmDraft(this.generatedDraftSessionId, this.generatedDraft, candidate);
  }

  private openAnimated(): void {
    this.motionSeq += 1;
    const seq: number = this.motionSeq;
    this.overlayVisible = true;
    this.maskOpacity = 0;
    this.sheetOpacity = 0;
    this.sheetOffset = FLOAT_SHEET_OPEN_OFFSET;
    setTimeout((): void => {
      if (seq !== this.motionSeq || !this.show) {
        return;
      }
      animateTo({ duration: DUR_BASE, curve: Curve.FastOutSlowIn }, (): void => {
        this.maskOpacity = 1;
        this.sheetOpacity = 1;
        this.sheetOffset = 0;
      });
    }, 0);
  }

  private closeAnimated(): void {
    this.motionSeq += 1;
    const seq: number = this.motionSeq;
    this.panelVisible = false;
    if (!this.overlayVisible) {
      return;
    }
    animateTo({ duration: DUR_FAST, curve: Curve.FastOutSlowIn }, (): void => {
      this.maskOpacity = 0;
      this.sheetOpacity = 0;
      this.sheetOffset = FLOAT_SHEET_CLOSE_OFFSET;
    });
    setTimeout((): void => {
      if (seq === this.motionSeq && !this.show) {
        this.overlayVisible = false;
      }
    }, FLOAT_UNMOUNT_DELAY_MS);
  }

  // ===== build =====

  build() {
    Stack() {
      if (this.overlayVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(OVERLAY_MASK)
          .opacity(this.maskOpacity)
          .onClick((): void => this.onClose());
        Column() {
          // 拖拽手柄 (独立 Row, 全宽, 灰条居中)
          Row() {
            Row()
              .width(36)
              .height(5)
              .borderRadius(3)
              .backgroundColor(TEXT_4)
          }
          .width('100%')
          .height(S_6)
          .justifyContent(FlexAlign.Center)
          .gesture(PanGesture({ direction: PanDirection.Vertical })
            .onActionStart((): void => { this.dragStartH = this.floatHeight; })
            .onActionUpdate((event: GestureEvent): void => { this.floatHeight = Math.max(30, Math.min(90, this.dragStartH - event.offsetY / SCREEN_H * 100)); }));

          Stack({ alignContent: Alignment.TopStart }) {
            ChatHeader({
              onToggleHistory: (): void => { this.togglePanel(); },
              onCreateSession: (): void => { this.newSession(); },
            });
            Text(this.activeSessionTitle)
              .id('chat-session-title-' + this.activeSid)
              .width('100%')
              .height(CHAT_HEADER_HEIGHT)
              .textAlign(TextAlign.Center)
              .fontSize(F_MD)
              .fontColor(TEXT)
              .fontWeight(W_SEMIBOLD)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: S_3, right: S_3 })
              .position({ x: 0, y: 0 })
              .hitTestBehavior(HitTestMode.None);
          }
          .width('100%')
          .height(CHAT_HEADER_HEIGHT);
          Row().width('100%').height(0.5).backgroundColor(BORDER);

          if (this.panelVisible) {
            Column()
              .width('100%').height('100%')
              .backgroundColor(Color.Transparent)
              .position({ x: 0, y: PANEL_MASK_TOP })
              .markAnchor({ x: 0, y: 0 })
              .zIndex(PANEL_MASK_Z_INDEX)
              .onClick((): void => { this.closePanel(); });
            SessionsPanel({
              sessions: this.sessions,
              activeSid: this.activeSid,
              onSelect: (sid: string): void => { this.onSelectSession(sid); },
              onRequestDelete: (sid: string): void => { this.onRequestSessionDelete(sid); },
            })
              .position({ x: S_3 + S_4, y: PANEL_MASK_TOP + S_2 })
              .markAnchor({ x: 0, y: 0 })
              .zIndex(PANEL_Z_INDEX);
          }

          AgentMessageList({ messages: this.messages, busy: this.inputVm.busy, scroller: this.scroller });
          Row().width('100%').height(0.5).backgroundColor(BORDER);

          ImagePreviewBar({ imagePreview: this.inputVm.imagePreview, onClear: (): void => { this.inputVm.clearImagePreview(); } });
          AgentInputPanel({
            vm: this.inputVm,
            modelName: ModelSelector.currentLabel(),
            onCamera: this.onCameraAction,
            onAlbum: this.onAlbumAction,
            onStop: (): void => { this.stopStreaming(); },
          });
        }
        .width('100%').height(this.floatHeight + '%').backgroundColor(BG_DARK)
        .borderRadius({ topLeft: R_XL, topRight: R_XL }).padding({ left: S_3, right: S_3 })
        .opacity(this.sheetOpacity)
        .position({ x: 0, y: '100%' }).markAnchor({ x: 0, y: '100%' }).translate({ y: -(74 + this.keyboardHeight) + this.sheetOffset });
      }
      if (this.generatedDraft !== null) {
        NoteDetailOverlay({
          generatedDraft: this.generatedDraft,
          onClose: (): void => {
            this.inputVm.setDraftForSession(this.generatedDraftSessionId, undefined);
            this.generatedDraft = null;
            this.generatedDraftSessionId = '';
          },
           onDraftCancel: (): void => {
             const cancelled: NoteDraftReadyEvent | null = this.generatedDraft;
             const cancelledSessionId: string = this.generatedDraftSessionId;
             this.inputVm.setDraftForSession(cancelledSessionId, undefined);
             this.generatedDraft = null;
             this.generatedDraftSessionId = '';
             if (cancelled !== null) {
               if (cancelledSessionId.length > 0 && this.service !== null) {
                 this.service.cancelDraft(cancelledSessionId, cancelled.runId).catch((): void => {});
               } else if (cancelledSessionId.length === 0) {
                 this.draftRecovery?.cancel(cancelled.runId).catch((): void => {});
               }
             }
           },
          onDraftConfirm: this.confirmDraft,
          onSaved: (_unit: KnowledgeUnit): void => {
            this.inputVm.setDraftForSession(this.generatedDraftSessionId, undefined);
            this.generatedDraft = null;
            this.generatedDraftSessionId = '';
          },
        })
      }
    }.width('100%').height('100%').hitTestBehavior(this.overlayVisible ? HitTestMode.Default : HitTestMode.None);
  }
}
