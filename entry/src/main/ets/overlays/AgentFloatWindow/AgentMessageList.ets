/**
 * AgentMessageList.ets — AI 浮窗消息列表
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets
 * 职责: Scroll 消息列表 + 空状态 + 处理中临时 AI 气泡
 * 依赖: ChatBubble, EmptyStateHint, ChatModels
 */

import { S_2, S_4 } from 'common';
import { ChatBubble } from './chat/ChatBubble';
import { EmptyStateHint } from './chat/EmptyStateHint';
import { ChatMsg, chatItemKey } from './chat/ChatModels';

function safeIndex(index: number | undefined): number {
  return index === undefined ? 0 : index;
}

class ChatMessageDataSource implements IDataSource {
  private messages: ChatMsg[] = [];
  private listeners: DataChangeListener[] = [];
  private fallback: ChatMsg = { id: 0, role: 'ai', content: '', ts: 0, streaming: false, reasoning: '' };

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): ChatMsg {
    const message: ChatMsg | undefined = this.messages[index];
    return message === undefined ? this.fallback : message;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }

  setMessages(messages: ChatMsg[]): void {
    this.messages = messages.slice(0);
    this.notifyReload();
  }

  private notifyReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

@Component
export struct AgentMessageList {
  @Prop @Watch('onMessagesChanged') messages: ChatMsg[] = [];
  @Prop busy: boolean = false;
  scroller: Scroller = new Scroller();
  private dataSource: ChatMessageDataSource = new ChatMessageDataSource();
  private lastStreamProgressKey: string = '';

  aboutToAppear(): void {
    this.dataSource.setMessages(this.messages);
  }

  onMessagesChanged(): void {
    this.dataSource.setMessages(this.messages);
    // 流式消息自动滚到底部
    const progressKey: string = this.currentStreamProgressKey();
    if (progressKey.length > 0 && progressKey !== this.lastStreamProgressKey) {
      this.lastStreamProgressKey = progressKey;
      setTimeout((): void => { this.scroller.scrollEdge(Edge.Bottom); }, 50);
    }
  }

  build() {
    List({ scroller: this.scroller }) {
      if (this.messages.length === 0 && !this.busy) {
        ListItem() {
          EmptyStateHint();
        }
      }

      LazyForEach(this.dataSource,
        (msg: ChatMsg, index: number | undefined): void => {
          ListItem() {
            ChatBubble({ msg: msg });
          }
          .width('100%')
          .padding({ left: S_4, right: S_4, top: safeIndex(index) === 0 ? S_2 : 0 });
        },
        (msg: ChatMsg): string => chatItemKey(msg)
      );

      ListItem() {
        Column() {
          Blank().height(S_2);
        }
        .width('100%')
      }
    }
    .layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
  }
  private currentStreamProgressKey(): string {
    if (this.messages.length === 0) {
      return '';
    }
    const message: ChatMsg = this.messages[this.messages.length - 1];
    if (!message.streaming) {
      return '';
    }
    return chatItemKey(message);
  }
}
