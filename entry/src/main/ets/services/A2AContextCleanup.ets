/**
 * A2AContextCleanup.ets — A2A 会话 / 图片 / 计划文件的保留清理
 *
 * 路径: entry/src/main/ets/services/A2AContextCleanup.ets
 * 职责: 删除超过保留期的 a2a/*.json，避免 contextId / 图片材料 / 缓存计划文件无限增长。
 * 依赖: A2AConversationStore / A2AImageContextStore / A2APlanStore。
 */
import type { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { A2AConversationStore } from './A2AConversationStore';
import { A2AImageContextStore } from './A2AImageContextStore';
import { A2APlanStore } from './A2APlanStore';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'MindTraceA2A';

/** 7 天：超过后视为不再活跃的 A2A 会话材料。 */
export const A2A_CONTEXT_MAX_AGE_MS: number = 7 * 24 * 60 * 60 * 1000;

export interface A2AContextPruneSummary {
  chats: number;
  images: number;
  plans: number;
}

export class A2AContextCleanup {
  static run(context: common.Context): A2AContextPruneSummary {
    const chats: number = A2AConversationStore.prune(context, A2A_CONTEXT_MAX_AGE_MS);
    const images: number = A2AImageContextStore.prune(context, A2A_CONTEXT_MAX_AGE_MS);
    const plans: number = A2APlanStore.prune(context, A2A_CONTEXT_MAX_AGE_MS);
    const summary: A2AContextPruneSummary = { chats: chats, images: images, plans: plans };
    if (chats + images + plans > 0) {
      hilog.info(DOMAIN, TAG, 'A2A_CONTEXT_PRUNED chats=%{public}d images=%{public}d plans=%{public}d',
        chats, images, plans);
    }
    return summary;
  }
}
