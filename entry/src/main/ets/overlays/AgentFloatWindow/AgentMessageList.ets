/**
 * AgentMessageList.ets — AI 浮窗消息列表
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets
 * 职责: Scroll 消息列表 + 空状态 + 处理中临时 AI 气泡
 * 依赖: ChatBubble, EmptyStateHint, ChatModels
 */

import { S_2, S_4, MINT, TEXT_4 } from 'common';
import { ChatBubble } from './chat/ChatBubble';
import { EmptyStateHint } from './chat/EmptyStateHint';
import { ChatMsg, ChatStatusMeta, chatItemKey } from './chat/ChatModels';

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
  @Prop statusMeta: ChatStatusMeta | null = null;
  scroller: Scroller = new Scroller();
  private dataSource: ChatMessageDataSource = new ChatMessageDataSource();
  private lastStreamProgressKey: string = '';
  onToggleReasoning: (msg: ChatMsg) => void = (_msg: ChatMsg): void => {};

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
            ChatBubble({
              msg: msg,
              onToggleReasoning: (toggleMsg: ChatMsg): void => { this.onToggleReasoning(toggleMsg); },
            });
          }
          .width('100%')
          .padding({ left: S_4, right: S_4, top: safeIndex(index) === 0 ? S_2 : 0 });
        },
        (msg: ChatMsg): string => chatItemKey(msg)
      );

      if (this.busy && (this.statusMeta === null || this.statusMeta.step !== 'completed')) {
        ListItem() {
          Row() {
            LoadingProgress().width(10).height(10).color(MINT)
            Text(this.statusMeta?.title ?? '处理中...').fontSize(11).fontColor(TEXT_4).margin({ left: 6 })
            if (this.statusMeta !== null && (this.statusMeta.detail ?? '').length > 0) {
              Text('· ' + (this.statusMeta.detail ?? '')).fontSize(10).fontColor(TEXT_4).margin({ left: 4 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .padding({ left: S_4, top: 4, bottom: 4 })
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
      }

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
    const reasoningLength: number = message.reasoning === undefined ? 0 : message.reasoning.length;
    return message.id.toString() + '_' + message.content.length.toString() + '_' + reasoningLength.toString();
  }
}
