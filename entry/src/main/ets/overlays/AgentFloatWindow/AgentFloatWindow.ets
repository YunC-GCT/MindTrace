// ============================================================================
//  overlays/AgentFloatWindow/AgentFloatWindow.ets — 智能体浮窗(完整版)
//  ----------------------------------------------------------------------------
//  特性: 拖拽缩放(floatHeight) · 多会话(SessionBar+ChatSession) · 拍照整链(captureReply)
//  子组件: ChatHeader / SessionBar / AgentMessageList / QuickSuggestions / ImagePreviewBar / AgentInputBar
//  业务: AgentChatService
//  ============================================================================

import {
  BG_DARK, TEXT_4, BORDER,
  S_3, S_6, R_XL,
  OVERLAY_MASK, SCREEN_H,
  DUR_FAST, DUR_BASE,
} from 'common';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import window from '@ohos.window';
import { AgentChatService, AgentChatCallbacks } from '../../services/AgentChatService';
import { LlmConfig } from 'common';
import { ChatHeader } from './chat/ChatHeader';
import { QuickSuggestions } from './chat/QuickSuggestions';
import { ChatSessionManager, sid } from './chat/ChatSession';
import { SessionBar } from './chat/SessionBar';
import { ChatMsg, ChatSession, ChatStatusMeta } from './chat/ChatModels';
import { AgentMessageList } from './AgentMessageList';
import { ImagePreviewBar } from './ImagePreviewBar';
import { AgentInputBar } from './AgentInputBar';
import { NoteDraftReadyEvent } from 'common';
import { NoteDetailOverlay } from '../NoteDetailOverlay/NoteDetailOverlay';
import { KnowledgeUnit } from 'common';

function nowId(): number { return Date.now() * 1000 + Math.floor(Math.random() * 1000); }

const FLOAT_SHEET_OPEN_OFFSET: number = 22;
const FLOAT_SHEET_CLOSE_OFFSET: number = 18;
const FLOAT_UNMOUNT_DELAY_MS: number = DUR_FAST + 40;

@Component
export struct AgentFloatWindow {
  @Prop @Watch('onShowChange') show: boolean = false;
  onClose: () => void = (): void => {};
  onGoCamera: () => void = (): void => {};
  @Prop @Watch('onPendingImageChange') pendingImageUri: string = '';

  @State @Watch('onMessagesChange') messages: ChatMsg[] = [];
  @State inputText: string = '';
  @State busy: boolean = false;
  @State statusMeta: ChatStatusMeta | null = null;
  @State imagePreview: string = '';
  @State keyboardHeight: number = 0;
  @State sessions: ChatSession[] = [{ id: 's1', name: '会话 1', messages: [] }];
  @State activeSid: string = 's1';
  @State renderKey: number = 0;
  @State floatHeight: number = 48;
  @State overlayVisible: boolean = false;
  @State maskOpacity: number = 0;
  @State sheetOpacity: number = 0;
  @State sheetOffset: number = FLOAT_SHEET_OPEN_OFFSET;
  @State generatedDraft: NoteDraftReadyEvent | null = null;
  private motionSeq: number = 0;
  private dragStartH: number = 48;
  private mainWindow: window.Window | null = null;
  private scroller: Scroller = new Scroller();
  private sm: ChatSessionManager = new ChatSessionManager();
  private service: AgentChatService | null = null;

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
  aboutToDisappear(): void { if (this.mainWindow) { this.mainWindow.off('keyboardHeightChange'); }; this.sm.save(this.sessions); }
  onShowChange(): void {
    if (this.show) {
      this.openAnimated();
      return;
    }
    this.closeAnimated();
  }
  onPendingImageChange(): void { if (this.pendingImageUri.length > 0) { this.imagePreview = this.pendingImageUri; } }
  onMessagesChange(): void {
    if (this.messages.length > 0) {
      this.renderKey++;
      this.sync(); this.sm.save(this.sessions);
      setTimeout((): void => { this.scroller.scrollEdge(Edge.Bottom); }, 200);
    }
  }

  private initKeyboard(): void {
    try { const ctx = this.getUIContext().getHostContext();
      if (ctx) { window.getLastWindow(ctx).then((w: window.Window) => { this.mainWindow = w; w.on('keyboardHeightChange', (d: number) => { try { this.keyboardHeight = this.getUIContext().px2vp(d); } catch (e) { } }); }).catch(() => {}); }
    } catch (e) {}
  }

  // ===== 会话管理 =====

  private async loadHistory(): Promise<void> {
    const cbs: AgentChatCallbacks = {
      addAiMsg: (c: string): void => { this.messages = [...this.messages, { id: nowId(), role: 'ai', content: c, ts: Date.now(), streaming: false, reasoning: '' }]; },
      addAiMsgEmpty: (): number => {
        const id: number = nowId();
        this.messages = [...this.messages, { id, role: 'ai', content: '', ts: Date.now(), streaming: true, reasoning: '' }];
        return id;
      },
      appendAiMsg: (id: number, delta: string, kind?: 'reasoning' | 'content'): void => {
        if (kind === 'reasoning') {
          this.messages = this.messages.map((m: ChatMsg): ChatMsg => m.id === id ? { id: m.id, role: m.role, content: m.content, ts: m.ts, streaming: m.streaming, reasoning: (m.reasoning ?? '') + delta } : m);
        } else {
          this.messages = this.messages.map((m: ChatMsg): ChatMsg => m.id === id ? { id: m.id, role: m.role, content: m.content + delta, ts: m.ts, streaming: m.streaming, reasoning: m.reasoning } : m);
        }
      },
      finishAiMsg: (id: number): void => {
        this.messages = this.messages.map((m: ChatMsg): ChatMsg => m.id === id ? { id: m.id, role: m.role, content: m.content, ts: m.ts, streaming: false, reasoning: m.reasoning } : m);
      },
      setBusy: (v: boolean): void => { this.busy = v; },
      setStatusMeta: (meta: ChatStatusMeta | null): void => { this.statusMeta = meta; },
      getContext: (): common.UIAbilityContext => getContext(this) as common.UIAbilityContext,
      getConversationText: (excludeLatestUser: boolean): string => this.buildConversationText(excludeLatestUser),
      getSessionId: (): string => this.activeSid,
      onDraftReady: (event: NoteDraftReadyEvent): void => { this.generatedDraft = event; },
    };
    this.service = new AgentChatService(cbs);
    const ss: ChatSession[] = await this.sm.init(getContext(this));
    if (ss.length > 0) { this.sessions = ss; this.activeSid = ss[0].id; this.messages = ss[0].messages; return; }
    this.messages = [{ id: 1, role: 'ai', content: '👋 你好，我是 MindTrace AI。可以帮你分析题目、讲解知识点、整理笔记。试试问我吧 👉', ts: Date.now(), streaming: false, reasoning: '' }];
  }

  private sync(): void {
    const s: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === this.activeSid);
    if (s !== undefined) { s.messages = this.messages; }
  }
  private buildConversationText(excludeLatestUser: boolean): string {
    const parts: string[] = [];
    const end: number = excludeLatestUser
      && this.messages.length > 0
      && this.messages[this.messages.length - 1].role === 'user'
      ? this.messages.length - 1
      : this.messages.length;
    let i: number = 0;
    while (i < end) {
      const msg: ChatMsg = this.messages[i];
      const role: string = msg.role === 'user' ? '用户' : 'AI';
      if (msg.content.trim().length > 0) {
        parts.push(role + ': ' + msg.content.trim());
      }
      i += 1;
    }
    return parts.join('\n\n');
  }
  private switchSession(sid: string): void {
    this.sync();
    // 取消旧会话中正在进行的流式消息
    if (this.messages.length > 0 && this.messages[this.messages.length - 1].streaming) {
      this.messages = this.messages.map((m: ChatMsg, i: number): ChatMsg =>
        i === this.messages.length - 1 ? { id: m.id, role: m.role, content: m.content, ts: m.ts, streaming: false, reasoning: m.reasoning } : m
      );
    }
    const s: ChatSession | undefined = this.sessions.find((item: ChatSession): boolean => item.id === sid);
    if (s !== undefined) { this.activeSid = sid; this.messages = s.messages; }
  }
  private newSession(): void { this.sync(); const s: ChatSession = { id: sid(), name: '会话 ' + (this.sessions.length + 1).toString(), messages: [] }; this.sessions = [...this.sessions, s]; this.activeSid = s.id; this.messages = []; this.sm.save(this.sessions); }
  private deleteSession(sid: string): void { if (this.sessions.length <= 1) { return; } const f = this.sessions.filter((s: ChatSession): boolean => s.id !== sid); this.sessions = f; if (sid === this.activeSid) { this.activeSid = f[0].id; this.messages = f[0].messages; }; this.sm.save(this.sessions); }

  // ===== 交互逻辑 =====

  private canSend = (): boolean => !this.busy && (this.inputText.trim().length > 0 || this.imagePreview.length > 0);

  private send = (text?: string): void => {
    const msg: string = (text ?? this.inputText).trim();
    const uri: string = this.imagePreview;
    this.messages = [...this.messages, { id: nowId(), role: 'user', content: msg || '[图片]', ts: Date.now(), streaming: false, reasoning: '' }];
    this.inputText = ''; this.imagePreview = '';
    if (uri.length > 0) {
      this.service?.captureReply(uri, msg);
    } else {
      this.service?.realReplyStream(msg);
    }
  };

  private modelLabel(): string {
    const model: string = LlmConfig.getInstance().getModel().trim();
    if (model === 'deepseek-v4-pro') {
      return 'DeepSeek-V4-Pro'
    }
    return model.length > 0 ? model : 'DeepSeek-V4-Pro'
  }

  private confirmDraft = async (candidate: KnowledgeUnit): Promise<KnowledgeUnit> => {
    if (this.generatedDraft === null || this.service === null) {
      throw new Error('草稿服务不可用');
    }
    return await this.service.confirmDraft(this.generatedDraft, candidate);
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
          // 拖拽手柄
          Row() { Row().width(36).height(5).borderRadius(3).backgroundColor(TEXT_4); }
          .width('100%').height(S_6).justifyContent(FlexAlign.Center)
          .gesture(PanGesture({ direction: PanDirection.Vertical })
            .onActionStart((): void => { this.dragStartH = this.floatHeight; })
            .onActionUpdate((event: GestureEvent): void => { this.floatHeight = Math.max(30, Math.min(90, this.dragStartH - event.offsetY / SCREEN_H * 100)); }));

          ChatHeader({
            modelName: this.modelLabel(),
            onNewChat: (): void => { this.newSession(); },
            onClose: this.onClose,
          });
          Row().width('100%').height(0.5).backgroundColor(BORDER);

          SessionBar({ sessions: this.sessions, activeSid: this.activeSid, onSwitch: (sid: string): void => { this.switchSession(sid); }, onDelete: (sid: string): void => { this.deleteSession(sid); }, onNew: (): void => { this.newSession(); } });

          AgentMessageList({ messages: this.messages, busy: this.busy, statusMeta: this.statusMeta, scroller: this.scroller, onToggleReasoning: (msg: ChatMsg): void => { this.messages = this.messages.map((m: ChatMsg): ChatMsg => m.id === msg.id ? { id: m.id, role: m.role, content: m.content, ts: m.ts, streaming: m.streaming, reasoning: m.reasoning, reasoningExpanded: !(m.reasoningExpanded ?? false) } : m); } });
          Row().width('100%').height(0.5).backgroundColor(BORDER);

          QuickSuggestions({ onSelect: (p: string): void => { this.send(p); } });
          ImagePreviewBar({ imagePreview: this.imagePreview, onClear: (): void => { this.imagePreview = ''; } });
          AgentInputBar({ inputText: this.inputText, canSend: this.canSend(), onTextChange: (v: string): void => { this.inputText = v; }, onSubmit: (): void => { this.send(); }, onCamera: (): void => { this.onGoCamera(); } });
        }
        .width('100%').height(this.floatHeight + '%').backgroundColor(BG_DARK)
        .borderRadius({ topLeft: R_XL, topRight: R_XL }).padding({ left: S_3, right: S_3 })
        .opacity(this.sheetOpacity)
        .position({ x: 0, y: '100%' }).markAnchor({ x: 0, y: '100%' }).translate({ y: -(74 + this.keyboardHeight) + this.sheetOffset });
      }
      if (this.generatedDraft !== null) {
        NoteDetailOverlay({
          generatedDraft: this.generatedDraft,
          onClose: (): void => { this.generatedDraft = null },
           onDraftCancel: (): void => {
             const cancelled: NoteDraftReadyEvent | null = this.generatedDraft;
             this.generatedDraft = null;
             if (cancelled !== null) {
               this.service?.cancelDraft(cancelled.runId).catch((): void => {});
             }
           },
          onDraftConfirm: this.confirmDraft,
          onSaved: (_unit: KnowledgeUnit): void => { this.generatedDraft = null },
        })
      }
    }.width('100%').height('100%').hitTestBehavior(this.overlayVisible ? HitTestMode.Default : HitTestMode.None);
  }
}
