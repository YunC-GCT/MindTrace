/**
 * AgentIngestService.ets — 所有入口的整理端口（唯一写入口）。
 *
 * 路径: entry/src/main/ets/services/AgentIngestService.ets
 * 职责: 收一个 AgentIngestRequest（文字 + 可选图片），需要时先调 OcrService 把图变成文本，
 *       再走 DatabaseHelper.init → AiService.ingestText → Dispatcher → 结构化 → KnowledgeUnitWriteService。
 * 依赖: common (DatabaseHelper / KnowledgeUnit)、services/AiService、services/OcrService
 *
 * 为什么这么分层：
 *   入口层（小艺 extension / 应用内选图 / 分享）只负责「把外部协议翻译成 AgentIngestRequest」，
 *   传输差异到此为止；识别是共享能力（OcrService），编排与落库也是共享的（Dispatcher + 写路径）。
 *   新入口 = 新 adapter，不需要复制任何整理逻辑。
 *
 * 进程约束：扩展进程（:agent）没有 UIAbilityContext，副作用必须关掉
 *   （AiService 第二个参数 includeUiEffects = false），卡片刷新由主进程注册。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper, KnowledgeUnit } from 'common';
import { AiService } from './AiService';
import { AgentImagePart } from './AgentImageParts';
import { AgentIngestRequest } from './AgentIngestRequest';
import { OcrService } from './OcrService';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'AgentIngest';

/** 一次最多识别几张图：小艺/分享单条消息很少超过 3 张，多则截断 */
const MAX_IMAGES: number = 3;
const NEWLINE: string = String.fromCharCode(10);

export class AgentIngestService {
  /** 端口入口：文字、图片、混合都从这里进；失败向上抛，由调用方决定是否退回队列。 */
  static async ingest(context: common.Context, request: AgentIngestRequest): Promise<KnowledgeUnit> {
    hilog.info(DOMAIN, TAG, 'INGEST source=%{public}s textChars=%{public}d images=%{public}d',
      request.source, request.text.length, request.images.length);
    const text: string = request.images.length > 0
      ? await AgentIngestService.ocrImages(request)
      : request.text.trim();
    if (text.length === 0) {
      throw new Error('empty payload');
    }
    await DatabaseHelper.init(context);
    const service: AiService = new AiService(context, false);
    return await service.ingestText(text);
  }

  /** 图片 → 文本（单张失败不拖垮整批；全失败抛错，不写空笔记） */
  private static async ocrImages(request: AgentIngestRequest): Promise<string> {
    const total: number = request.images.length > MAX_IMAGES ? MAX_IMAGES : request.images.length;
    const texts: string[] = [];
    for (let i = 0; i < total; i++) {
      const image: AgentImagePart = request.images[i];
      try {
        const text: string = image.kind === 'uri'
          ? await OcrService.recognizeUri(image.value)
          : await OcrService.recognizeBase64(image.value);
        hilog.info(DOMAIN, TAG, 'IMAGE_OCR index=%{public}d chars=%{public}d', i, text.length);
        if (text.trim().length > 0) {
          texts.push(text.trim());
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'IMAGE_OCR_FAILED index=%{public}d %{public}s', i, (e as Error).message);
      }
    }
    if (texts.length === 0) {
      throw new Error('no text recognised in images');
    }
    const body: string = texts.join(NEWLINE + NEWLINE);
    // 用户在图片旁打的字（如「存笔记」）当提示，不覆盖正文
    return request.text.trim().length > 0 ? request.text.trim() + NEWLINE + body : body;
  }
}
