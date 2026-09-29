/**
 * NoteRetrievalQuery.ets — 关键词检索请求的保守主题清洗
 *
 * 路径: entry/src/main/ets/services/NoteRetrievalQuery.ets
 * 职责: 去除句首请求用语和句尾问句包装，保留主题内部文字及数学表达式。
 * 依赖: 无平台依赖；不调用 LLM、不扩展同义词、不拆分数学符号。
 * 数据流: 普通聊天 / 笔记复习 → normalize → note_query_rag
 */
export class NoteRetrievalQuery {
  static normalize(input: string): string {
    let text: string = input.trim();
    // 只处理边界，不能全局删除“学习”等可能属于笔记标题的词。
    for (let round: number = 0; round < 8; round += 1) {
      const previous: string = text;
      text = text
        .replace(/^[，,：:；;\s]+|[？?。！，,：:；;\s]+$/g, '')
        .replace(/^(?:请问|请|麻烦你|麻烦|帮我|给我|为我)\s*/, '')
        .replace(/^(?:能不能|可不可以|能否|可以)\s*/, '')
        .replace(/^(?:根据|依据|参考|结合)?(?:我的|已保存的?|保存的?|个人)?(?:笔记|知识库|复习资料)(?:中|里)?的?\s*/, '')
        .replace(/^(?:解释|讲解|介绍|说明|讲讲|说说|比较|查找|查一下|找一下|搜索|检索)(?:一下|下)?\s*/, '')
        .replace(/^(?:什么是|我的)\s*/, '')
        .replace(/(?:吗|呢|吧|呀|啊)$/, '')
        .replace(/(?:是什么意思|是什么|怎么理解|如何理解|在哪里|在哪)$/, '')
        .replace(/(?:的笔记|相关笔记|笔记)$/, '')
        .trim();
      if (text === previous) {
        break;
      }
    }
    if (text === '这个' || text === '那个' || text === '这张' || text === '那张' || text === '它') {
      return '';
    }
    return text;
  }
}
