/**
 * AgentInboxModels.ets — 小艺消息「入队」协议与判定（纯函数）。
 *
 * 路径: entry/src/main/ets/services/AgentInboxModels.ets
 * 职责: 定义待整理条目的形状、JSONL 序列化/解析，以及「这条小艺消息要不要入队」的判定。
 *       不做文件 IO、不依赖 Context，便于契约测试。
 * 依赖: 无
 *
 * 为什么要有队列：端A2A 的扩展跑在 :agent 进程，不能直接写 notes 库（跨进程 RDB 不可靠），
 * 所以小艺侧只把用户要整理的原文排进应用沙箱里的队列文件，应用回到前台时用正规写路径
 * （AiService → Dispatcher → KnowledgeUnitWriteService）逐条整理入库。
 *
 * 数据流:
 *   小艺 → AgentExtAbility.onData → shouldEnqueue() / buildInboxItem()
 *        → serializeInboxItem() → AgentInboxQueue.append()
 *   应用前台 → AgentInboxQueue.claim() → parseInboxItems() → A2AInboxIngestService 逐条 ingest
 */

/** 队列里的一条待整理原文。id 用来去重，channel 记录来源（当前只有小艺）。 */
export interface AgentInboxItem {
  id: string;
  text: string;
  receivedAt: number;
  channel: string;
}

/**
 * 触发入队的显式指令短语。
 * 只认「要点明是在存笔记」的说法：单纯的「整理一下」仍走普通对话，
 * 避免长问题被误当成待整理原文排进队列。
 */
export const INBOX_INTENT_PHRASES: string[] = [
  '存笔记',
  '记笔记',
  '整理成笔记',
  '存为笔记',
  '存到笔记',
  '记录到笔记',
  '笔记入库',
  '存进笔记',
];

/** 入队正文下限：太短的多半是「存笔记」三个字本身，没有可整理的原文。 */
export const MIN_INBOX_CHARS: number = 8;

function containsPhrase(text: string): boolean {
  for (let i = 0; i < INBOX_INTENT_PHRASES.length; i++) {
    if (text.indexOf(INBOX_INTENT_PHRASES[i]) >= 0) {
      return true;
    }
  }
  return false;
}

/** 命中显式指令短语、且正文足够长，才认为用户在让小艺「把这段原文存成笔记」。 */
export function shouldEnqueue(text: string): boolean {
  const body: string = text.trim();
  if (body.length < MIN_INBOX_CHARS) {
    return false;
  }
  return containsPhrase(body);
}

/** 构造队列条目；id 用时间戳 + 正文长度，重复投递同一条原文时便于排查。 */
export function buildInboxItem(text: string, receivedAt: number): AgentInboxItem {
  const body: string = text.trim();
  const item: AgentInboxItem = {
    id: 'xiaoyi-' + receivedAt.toString() + '-' + body.length.toString(),
    text: body,
    receivedAt: receivedAt,
    channel: 'xiaoyi',
  };
  return item;
}

/** 一条一行 JSON，便于追加写与坏行隔离。 */
export function serializeInboxItem(item: AgentInboxItem): string {
  return JSON.stringify(item) + '\n';
}

/** 解析队列文件；坏行直接跳过，绝不因为一行脏数据让整批整理失败。 */
export function parseInboxItems(raw: string): AgentInboxItem[] {
  const items: AgentInboxItem[] = [];
  if (raw.length === 0) {
    return items;
  }
  const lines: string[] = raw.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i].trim();
    if (line.length === 0) {
      continue;
    }
    try {
      const parsed = JSON.parse(line) as AgentInboxItem;
      if (typeof parsed.text !== 'string' || parsed.text.trim().length === 0) {
        continue;
      }
      const item: AgentInboxItem = {
        id: typeof parsed.id === 'string' && parsed.id.length > 0 ? parsed.id : 'inbox-' + i.toString(),
        text: parsed.text,
        receivedAt: typeof parsed.receivedAt === 'number' ? parsed.receivedAt : 0,
        channel: typeof parsed.channel === 'string' && parsed.channel.length > 0 ? parsed.channel : 'xiaoyi',
      };
      items.push(item);
    } catch (error) {
      continue;
    }
  }
  return items;
}
