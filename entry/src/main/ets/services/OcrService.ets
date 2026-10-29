/**
 * OcrService.ets — 端侧 OCR 能力门面（只经 OcrRecognizer 端口，不直接碰 Kit）
 *
 * 路径: entry/src/main/ets/services/OcrService.ets
 * 职责: 把 A2A 收到的图片 part（base64 / file:// uri）与内置自检图统一转成纯文本，
 *       交给同一个整理链路（AgentIngestService.ingest → Dispatcher → 结构化 → 落库）。
 *       本文件只做字节/资源转换与门面适配，识别全部走 OcrRecognizerRegistry.require()。
 * 依赖: @kit.AbilityKit (common), @kit.PerformanceAnalysisKit (hilog),
 *       @kit.ArkTS (util), common (OcrRecognizer / OcrRecognizerRegistry / OcrTextResult)
 *
 * 数据流: AgentExtAbility / AgentIngestService → OcrService.recognize*
 *          → OcrRecognizerRegistry.require() (实现由各进程组合根安装)
 *          → CoreVisionOcrRecognizer.recognize(uri) / recognizeBase64(base64) → string
 *
 * 为什么放在 services：这是共享能力层，不属于某个入口。
 *   小艺入口（:agent）、应用内选图、分享入口都把它当同一种能力调用，
 *   识别完只产出文本，后面的 agent 链路不感知图片。
 * Process: 主进程与 :agent 都要能加载；Kit 实现由各自组合根安装，本文件零 Kit 依赖。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { OcrRecognizer, OcrRecognizerRegistry, OcrTextResult } from 'common';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'XiaoyiOcr';
const NEWLINE: string = String.fromCharCode(10);

export class OcrService {
  /** 设备是否具备端侧文本识别能力（端口未安装时视为不可用） */
  static isAvailable(): boolean {
    return OcrRecognizerRegistry.isInstalled() && OcrRecognizerRegistry.require().isAvailable();
  }

  /**
   * 自检：扩展进程里能力端口装好没有、真实识别能不能跑通。
   * 图片 part 目前还没从小艺下发，先用内置图证明「解码 → PixelMap → 识别」在 :agent 里成立。
   */
  static async probe(context: common.Context): Promise<string> {
    const available: boolean = OcrService.isAvailable();
    let message: string = '';
    let head: string = '';
    // 端口不可用时不再跑真实识别：保持 available=false init=false 的原返回形状。
    if (available) {
      try {
        const text: string = await OcrService.recognizeRawFile(context, 'ocr-probe.png');
        head = text.length > 60 ? text.substring(0, 60) : text;
        head = head.split(NEWLINE).join(' / ');
        message = 'ocrChars=' + text.length.toString();
      } catch (e) {
        message = 'ocrFailed:' + (e as Error).message;
      }
    }
    // 门面不再自己 init：init 直接复用 available（端口实现内部负责初始化）。
    hilog.info(DOMAIN, TAG, 'PROBE available=%{public}s init=%{public}s msg=%{public}s',
      available ? 'true' : 'false', available ? 'true' : 'false', message);
    return 'available=' + (available ? 'true' : 'false') + ' init='
      + (available ? 'true' : 'false') + (message.length > 0 ? ' (' + message + ')' : '')
      + (head.length > 0 ? ' → ' + head : '');
  }

  /** base64（raw part）→ 文本 */
  static async recognizeBase64(base64: string): Promise<string> {
    const recognizer: OcrRecognizer = OcrRecognizerRegistry.require();
    const result: OcrTextResult = await recognizer.recognizeBase64(base64);
    return result.text;
  }

  /** 应用内置图（rawfile）→ 文本，用于自检：不依赖任何外部输入 */
  static async recognizeRawFile(context: common.Context, name: string): Promise<string> {
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(name);
    const base64: string = new util.Base64Helper().encodeToStringSync(bytes);
    return OcrService.recognizeBase64(base64);
  }

  /** file:// uri（url part）→ 文本 */
  static async recognizeUri(uri: string): Promise<string> {
    const recognizer: OcrRecognizer = OcrRecognizerRegistry.require();
    const result: OcrTextResult = await recognizer.recognize(uri);
    return result.text;
  }
}
