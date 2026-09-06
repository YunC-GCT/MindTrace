// ============================================================================
//  services/ChatStatusMachine.ets — 13 步 Chat 状态机 (spec 007 PR2)
//  ----------------------------------------------------------------------------
//  职责: step → ChatStatusMeta 转换;13 步固定 title/detail 文案;
//        AgentChatService 通过 ChatStatusMachine.advance(step) 推进。
//  不负责: busy lifecycle (finishBusy 仍归 AgentChatService);
//          ChatStatusStep / ChatStatusMeta 联合定义 (仍归 overlays/.../ChatModels)
//  依赖: ../overlays/AgentFloatWindow/chat/ChatModels (ChatStatusStep / ChatStatusMeta)
//  seam: advance(step) 接受 ChatStatusStep, 返回 ChatStatusMeta, 无副作用 (纯函数)
//  ============================================================================

import type { ChatStatusMeta, ChatStatusStep } from '../overlays/AgentFloatWindow/chat/ChatModels';

interface MetaEntry {
  title: string;
  detail: string;
}

export class ChatStatusMachine {
  private static readonly META_TABLE: Map<ChatStatusStep, MetaEntry> =
    new Map<ChatStatusStep, MetaEntry>([
      ['intent_check',          { title: '判断任务',     detail: '确认这轮是直接回答还是整理成笔记。' }],
      ['reply_context_load',    { title: '读取上下文',   detail: '取当前会话里和问题有关的内容。' }],
      ['reply_model_call',      { title: '生成回答',     detail: '组织结论、步骤和必要条件。' }],
      ['image_message_save',    { title: '记录图片问题', detail: '先保存本轮图片和补充说明。' }],
      ['image_recognize',       { title: '识别图片内容', detail: '读取图片里的题目、公式和文字。' }],
      ['image_material_save',   { title: '整理识别材料', detail: '把识别结果留作后续笔记素材。' }],
      ['note_intent_check',     { title: '确认整理需求', detail: '确认这轮需要生成可保存的笔记。' }],
      ['note_context_load',     { title: '读取笔记材料', detail: '读取当前会话、图片识别结果和待整理内容。' }],
      ['note_source_prepare',   { title: '整理笔记素材', detail: '确定要写进笔记的原题、公式和关键步骤。' }],
      ['note_material_summary', { title: '汇总成笔记底稿', detail: '把零散材料合成一份完整底稿。' }],
      ['note_structure_save',   { title: '生成并保存笔记', detail: '结构化标题、章节、标签和正文。' }],
      ['note_finalize',         { title: '更新笔记列表', detail: '刷新本地笔记并标记材料已使用。' }],
      ['completed',             { title: '完成',         detail: '本轮处理已结束。' }],
    ]);

  public advance(step: ChatStatusStep): ChatStatusMeta {
    const entry: MetaEntry | undefined = ChatStatusMachine.META_TABLE.get(step);
    const title: string = entry !== undefined ? entry.title : '完成';
    const detail: string = entry !== undefined ? entry.detail : '本轮处理已结束。';
    return { step: step, title: title, detail: detail };
  }
}
