/**
 * XiaoyiIngestService.ets — 小艺会话内直接跑整理入库（在扩展进程 :agent 里执行）。
 *
 * 路径: entry/src/main/ets/agentextability/XiaoyiIngestService.ets
 * 职责: 拿到用户在小艺里发的原文（或图片先经 OCR 变成的文本）后，不依赖用户回到应用，就地走
 *       DatabaseHelper.init → AiService.ingestText → Dispatcher → 结构化 → KnowledgeUnitWriteService 落库。
 * 依赖: common (DatabaseHelper / KnowledgeUnit)、services/AiService、本目录 XiaoyiOcrService
 *
 * 为什么能在这里写库：notes 库文件在同一 bundle 的沙箱里，扩展进程用 ExtensionContext 初始化
 * 同一个 MindTrace.db 即可；写完应用侧再查是能读到的（WAL）。
 * 为什么不带 UI 副作用：扩展进程没有 UIAbilityContext，卡片刷新这类副作用必须关掉
 * （AiService 第二个参数 includeUiEffects = false）。
 *
 * 图片链路：小艺入口发图 → collectImageParts → 本文件 ingestImages → 逐张 OCR →
 *   把文本喂进与「文字入口」完全相同的 ingest(text)，后续节点不感知图片。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper, KnowledgeUnit } from 'common';
import { AiService } from '../services/AiService';
import { AgentImagePart } from '../services/AgentImageParts';
import { XiaoyiOcrService } from './XiaoyiOcrService';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'XiaoyiOcr';

/** 一次最多识别几张图：小艺单条消息很少超过 3 张，多则截断并告知 */
const MAX_IMAGES: number = 3;

export class XiaoyiIngestService {
  /** 整理一段原文并入库；失败向上抛，由调用方决定是否退回队列。 */
  static async ingest(context: common.Context, text: string): Promise<KnowledgeUnit> {
    await DatabaseHelper.init(context);
    const service: AiService = new AiService(context, false);
    return await service.ingestText(text);
  }

  /**
   * 图片入口：先端侧 OCR 成文本，再走同一个整理节点。
   * 全部图片都没识别出文字时抛错（调用方回「没认出文字」），不写空笔记。
   */
  static async ingestImages(context: common.Context, images: AgentImagePart[],
    hint: string): Promise<KnowledgeUnit> {
    const total: number = images.length > MAX_IMAGES ? MAX_IMAGES : images.length;
    const texts: string[] = [];
    for (let i = 0; i < total; i++) {
      const image: AgentImagePart = images[i];
      try {
        const text: string = image.kind === 'uri'
          ? await XiaoyiOcrService.recognizeUri(image.value)
          : await XiaoyiOcrService.recognizeBase64(image.value);
        hilog.info(DOMAIN, TAG, 'IMAGE_OCR index=%{public}d chars=%{public}d', i, text.length);
        if (text.trim().length > 0) {
          texts.push(text.trim());
        }
      } catch (e) {
        // 单张失败不影响其它图；全失败才算这轮失败
        hilog.error(DOMAIN, TAG, 'IMAGE_OCR_FAILED index=%{public}d %{public}s', i, (e as Error).message);
      }
    }
    if (texts.length === 0) {
      throw new Error('没有从图片里识别出文字');
    }
    const body: string = texts.join('\n\n');
    // 用户在图旁边打的字（如「存笔记」）当提示，不覆盖正文
    const query: string = hint.trim().length > 0 ? hint.trim() + '\n' + body : body;
    hilog.info(DOMAIN, TAG, 'IMAGE_OCR merged images=%{public}d chars=%{public}d', texts.length, body.length);
    return XiaoyiIngestService.ingest(context, query);
  }
}
