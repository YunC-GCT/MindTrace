// ============================================================================
//  services/IntentClassifier.ets — 意图分类 + 提示词构建 (spec 007 PR1)
//  ----------------------------------------------------------------------------
//  职责: 判定 note_generation / chat 意图 (关键词前置, 远程 LLM 兜底, LlmGuard 校验重试);
//        构建聊天回复 system prompt (画像/记忆注入, MM-MD-v1 + JSON/LaTeX 约束);
//        从用户指令中提取笔记素材文本
//  依赖: common.LlmGuard (JSON 校验重试 + extractJsonObject, 不再私有复制)
//  seam: 构造可注入 LlmGuard (生产缺省 new LlmGuard(), 测试传 mock LlmCaller)
//  ============================================================================

import { ChatMessage, JSON_ONLY_RULES, LATEX_GENERATION_RULES, LlmConfig, LlmGuard } from 'common';
import type { LlmGuardValidationResult } from 'common';

export type TextIntent = 'note_generation' | 'chat';

export class IntentClassifier {
  private guard: LlmGuard;

  constructor(guard?: LlmGuard) {
    this.guard = guard !== undefined ? guard : new LlmGuard();
  }

  // ===== 意图判定 (关键词前置 → 远程 LLM 兜底, 失败回退 chat) =====
  public async classify(userText: string): Promise<TextIntent> {
    const normalized: string = userText.trim();
    if (normalized.length === 0) { return 'chat'; }
    if (this.hasNoteGenerationDenyIntent(normalized)) { return 'chat'; }
    if (this.hasExplicitNoteGenerationIntent(normalized)) { return 'note_generation'; }
    if (!this.shouldUseRemoteIntentClassifier(normalized)) { return 'chat'; }

    try {
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) { return 'chat'; }
      const messages: ChatMessage[] = this.buildIntentMessages(normalized);
      const result = await this.guard.callJsonWithRetry(messages, {
        maxTokens: 80,
        timeoutMs: 30000,
        responseFormat: { type: 'json_object' },
        label: 'text intent classification',
      }, (json: Record<string, Object>): LlmGuardValidationResult => this.validateTextIntentJson(json));
      return this.parseTextIntent(result.raw);
    } catch (e) {
      console.warn('[IntentClassifier] text intent classify failed: ' + IntentClassifier.errorMessage(e));
      return 'chat';
    }
  }

  private buildIntentMessages(userContent: string): ChatMessage[] {
    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: 'Classify the MindTrace user message intent. Return strict JSON only: {"intent":"note_generation"} or {"intent":"chat"}. note_generation means the user wants current/previous/provided content turned into saveable learning material, such as a note, knowledge point, notebook entry, retained problem record, or material to store for later review. This includes natural requests like remembering/saving the above problem as study material even if the wording is informal. Return chat for normal Q&A, explanation, calculation, practice generation, casual chat, or temporary summarization/organization where the user only wants an answer and does not imply saving or forming reusable learning material. If uncertain, return chat.',
      },
      {
        role: 'user',
        content: userContent,
      },
    ];
    return messages;
  }

  private parseTextIntent(raw: string): TextIntent {
    const jsonText: string = this.guard.extractJsonObject(raw);
    if (jsonText.length === 0) { return 'chat'; }
    try {
      const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
      const value: Object | undefined = parsed['intent'];
      if (typeof value === 'string' && value === 'note_generation') {
        return 'note_generation';
      }
    } catch (e) {
      console.warn('[IntentClassifier] parse intent json failed: ' + IntentClassifier.errorMessage(e));
    }
    return 'chat';
  }

  private validateTextIntentJson(json: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    const intent: Object | undefined = json['intent'];
    if (typeof intent !== 'string') {
      issues.push('intent must be a string');
    } else if (intent !== 'note_generation' && intent !== 'chat') {
      issues.push('intent must be note_generation or chat');
    }
    return {
      ok: issues.length === 0,
      issues: issues,
    };
  }

  private shouldUseRemoteIntentClassifier(text: string): boolean {
    const intentWords: string[] = [
      '生成',
      '创建',
      '新建',
      '整理',
      '保存',
      '存',
      '记',
      '总结',
      '归纳',
      '提炼',
      '收进',
      '加入',
      '转成',
      '转为',
      '做成',
      '笔记',
      '知识点',
      '上面',
      '上文',
      '刚才',
      '这段',
      '这些',
      '内容',
    ];
    return this.includesAny(text, intentWords);
  }

  private hasNoteGenerationDenyIntent(text: string): boolean {
    const denyPhrases: string[] = [
      '不要生成',
      '别生成',
      '无需生成',
      '不用生成',
      '不要创建',
      '别创建',
      '不要保存',
      '别保存',
      '不要记',
      '别记',
      '不用记',
      '不要笔记',
      '不用笔记',
      '无需笔记',
    ];
    return this.includesAny(text, denyPhrases);
  }

  private hasExplicitNoteGenerationIntent(text: string): boolean {
    const phrases: string[] = [
      '生成笔记',
      '创建笔记',
      '新建笔记',
      '整理成笔记',
      '整理为笔记',
      '保存为笔记',
      '保存成笔记',
      '总结成笔记',
      '总结为笔记',
      '归纳成笔记',
      '归纳为笔记',
      '做成笔记',
      '转成笔记',
      '转为笔记',
      '记一下',
      '记下',
      '记下来',
      '帮我记下来',
      '这个记下来',
      '把这个记下来',
      '把这题记下来',
      '把上面记下来',
      '把刚才记下来',
      '收进笔记',
      '加入笔记',
      '存到笔记',
      '存进笔记',
      '留作笔记',
      '保存这个知识点',
      '把这个知识点存起来',
      '这个知识点存起来',
      '知识点存起来',
      '生成知识点',
      '整理成知识点',
      '整理为知识点',
      '总结成知识点',
      '总结为知识点',
      '提炼成知识点',
      '提炼为知识点',
    ];
    if (this.includesAny(text, phrases)) { return true; }

    const createActions: string[] = ['生成', '创建', '新建'];
    const transformActions: string[] = ['整理成', '整理为', '保存为', '保存成', '总结成', '总结为', '归纳成', '归纳为', '做成', '转成', '转为', '提炼成', '提炼为', '收进', '加入', '存到', '存进', '留作'];
    const noteTargets: string[] = ['笔记', '知识点'];
    const rememberActions: string[] = ['记', '保存', '存'];
    const currentTargets: string[] = ['这个', '这题', '上面', '上文', '刚才', '这段', '这些', '知识点'];
    return this.hasActionNearTarget(text, createActions, noteTargets, 4)
      || this.hasActionNearTarget(text, transformActions, noteTargets, 6)
      || this.hasActionNearTarget(text, currentTargets, rememberActions, 8);
  }

  private includesAny(text: string, phrases: string[]): boolean {
    for (const phrase of phrases) {
      if (text.indexOf(phrase) >= 0) { return true; }
    }
    return false;
  }

  private hasActionNearTarget(text: string, actions: string[], targets: string[], maxGap: number): boolean {
    for (const action of actions) {
      let actionIndex: number = text.indexOf(action);
      while (actionIndex >= 0) {
        const afterAction: number = actionIndex + action.length;
        for (const target of targets) {
          const targetIndex: number = text.indexOf(target, afterAction);
          if (targetIndex >= 0 && targetIndex - afterAction <= maxGap) {
            return true;
          }
        }
        actionIndex = text.indexOf(action, afterAction);
      }
    }
    return false;
  }

  // ===== 笔记素材提取 (从用户指令剥离指令语, 留下可保存内容) =====
  public inlineNoteMaterial(userInstruction: string): string {
    let text: string = userInstruction.trim();
    const separators: string[] = ['：', ':', '\n'];
    for (const separator of separators) {
      const idx: number = text.indexOf(separator);
      if (idx >= 0 && idx + separator.length < text.length) {
        const tail: string = text.substring(idx + separator.length).trim();
        if (tail.length >= 8) {
          return tail;
        }
      }
    }

    const removablePhrases: string[] = [
      '请帮我',
      '帮我',
      '把这个',
      '把这题',
      '把这段',
      '把上面',
      '把刚才',
      '生成笔记',
      '创建笔记',
      '新建笔记',
      '整理成笔记',
      '整理为笔记',
      '保存为笔记',
      '保存成笔记',
      '总结成笔记',
      '总结为笔记',
      '归纳成笔记',
      '归纳为笔记',
      '做成笔记',
      '转成笔记',
      '转为笔记',
      '收进笔记',
      '加入笔记',
      '存到笔记',
      '存进笔记',
      '留作笔记',
      '记一下',
      '记下来',
      '记下',
    ];
    for (const phrase of removablePhrases) {
      text = text.replace(phrase, ' ');
    }
    text = text.replace(/\s+/g, ' ').trim();
    if (text.length >= 12) {
      return text;
    }
    return '';
  }

  // ===== 聊天回复 system prompt (MM-MD-v1 子集 + JSON/LaTeX 约束 + 画像/记忆注入) =====
  public buildReplyMessages(memoryContext: string, learnerProfileContext: string, userContent: string): ChatMessage[] {
    let systemPrompt: string = '你是 MindTrace AI 数学助手。回答要求：\n'
      + '1. 先判断用户当前意图，再结合 Learner profile 的生效水平调整解释密度；不要把所有问题套成同一种结构。\n'
      + '2. 当前用户明确要求“详细讲”“像小白一样讲”“直接给答案”“不要展开”时，本轮优先服从当前指令，而不是画像。\n'
      + '3. beginner：少术语，多直观解释、例子和关键易错点；步骤可以更细，但仍要避免空泛寒暄。\n'
      + '4. novice：默认给思路、必要步骤和结论；只在概念题、用户困惑或关键门槛处补直观解释，不要每题都写完整四段式。\n'
      + '5. advanced：默认直接给公式、推导主线、结论和边界条件；压缩基础定义、直观比喻、常见误区，除非用户要求展开。\n'
      + '6. 简单事实或短计算：先给答案，再用 1-3 个短步骤说明理由。\n'
      + '7. 总结/整理/复盘：使用标题和要点，覆盖核心结论、原因、方法、待补充内容；不要只输出一句总结。\n'
      + '8. 信息不足时先说明缺少什么，可以基于上文给出合理假设；无法确定时追问，不编造题目或结论。\n'
      + '9. 不要主动生成笔记；只有系统已判定用户明确要保存/生成笔记时，才会走笔记生成链路。\n'
      + '10. 只输出严格 JSON 对象，格式固定为 {"answer":"..."}；不要输出 JSON 代码块、解释或额外文本。\n'
      + '11. answer 字段采用 MM-MD-v1 子集：只使用标题、段落、单层有序/无序列表、加粗、行内代码和代码块；不要输出原始 HTML、Markdown 表格、任务列表、脚注或 Mermaid。\n'
      + '12. 短公式必须融入文字并用单个美元符定界，例如 $a>0$；不要输出裸 \\mu、\\sigma、\\Phi、\\operatorname，也不要使用单独的 [ ] 充当公式边界。\n'
      + '13. 重要公式、长公式和多行推导使用展示公式，起止 $$ 必须各占独立一行；不要写成 $$公式$$，不要在 $$ 内嵌套单个美元符，也不要用 Markdown 代码块包公式。\n'
      + '14. 多行公式只能在独立的 $$ 块内使用 \\begin{aligned}...\\end{aligned}；不要使用 align 或 align* 环境。\n'
      + '15. 列表项内只允许短行内公式；长公式和 $$ 定界符必须移到列表外，绝不能写成“1. $$”“2. 公式”“3. $$”。如需分步推导，用“第 1 步：”文字段落，再另起独立 $$ 块。\n\n'
      + JSON_ONLY_RULES + '\n'
      + LATEX_GENERATION_RULES;
    const profileContext: string = learnerProfileContext.trim();
    if (profileContext.length > 0) {
      systemPrompt += '\n\n用户画像如下，只用于控制解释密度和回答粒度，不要在回答中复述画像：\n' + profileContext;
    }
    const context: string = memoryContext.trim();
    if (context.length > 0) {
      systemPrompt += '\n\n可参考的会话记忆如下，只在相关时使用，不要主动生成笔记：\n' + this.clip(context, 12000);
    }
    const messages: ChatMessage[] = [
      {
        role: 'system',
        content: systemPrompt,
      },
      {
        role: 'user',
        content: userContent,
      },
    ];
    return messages;
  }

  private clip(text: string, limit: number): string {
    if (text.length <= limit) { return text; }
    return text.substring(0, limit) + '\n...';
  }

  private static errorMessage(e: Object): string {
    const message: string | undefined = (e as Error).message;
    if (message !== undefined && message.length > 0) {
      return message;
    }
    return JSON.stringify(e);
  }
}
