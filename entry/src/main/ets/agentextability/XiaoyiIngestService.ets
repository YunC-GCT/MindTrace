/**
 * XiaoyiIngestService.ets — 小艺会话内直接跑整理入库（在扩展进程 :agent 里执行）。
 *
 * 路径: entry/src/main/ets/agentextability/XiaoyiIngestService.ets
 * 职责: 拿到用户在小艺里发的原文后，不依赖用户回到应用，就地走
 *       DatabaseHelper.init → AiService.ingestText → Dispatcher → 结构化 → KnowledgeUnitWriteService 落库。
 * 依赖: common (DatabaseHelper / KnowledgeUnit)、services/AiService
 *
 * 为什么能在这里写库：notes 库文件在同一 bundle 的沙箱里，扩展进程用 ExtensionContext 初始化
 * 同一个 MindTrace.db 即可；写完应用侧再查是能读到的（WAL）。
 * 为什么不带 UI 副作用：扩展进程没有 UIAbilityContext，卡片刷新这类副作用必须关掉
 * （AiService 第二个参数 includeUiEffects = false）。
 */

import { common } from '@kit.AbilityKit';
import { DatabaseHelper, KnowledgeUnit } from 'common';
import { AiService } from '../services/AiService';

export class XiaoyiIngestService {
  /** 整理一段原文并入库；失败向上抛，由调用方决定是否退回队列。 */
  static async ingest(context: common.Context, text: string): Promise<KnowledgeUnit> {
    await DatabaseHelper.init(context);
    const service: AiService = new AiService(context, false);
    return await service.ingestText(text);
  }
}
