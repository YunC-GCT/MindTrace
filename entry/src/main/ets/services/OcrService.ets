/**
 * OcrService.ets — 端侧 OCR 能力（CoreVisionKit），所有入口共用
 *
 * 路径: entry/src/main/ets/services/OcrService.ets
 * 职责: 把 A2A 收到的图片 part（base64 或 file:// uri）识别成纯文本，
 *       交给同一个整理链路（XiaoyiIngestService.ingest → Dispatcher → 结构化 → 落库）。
 * 依赖: @kit.CoreVisionKit (textRecognition), @kit.ImageKit (image), @kit.ArkTS (util)
 *
 * 为什么放在 services：这是共享能力层，不属于某个入口。
 *   小艺入口（:agent）、应用内选图、分享入口都把它当同一种能力调用，
 *   识别完只产出文本，后面的 agent 链路不感知图片。
 * Process: 主进程与 :agent 都要能加载（见 spec 033 §4 的 RESTRICTED 表）。
 */

import { common } from '@kit.AbilityKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'XiaoyiOcr';

export class OcrService {
  /** 设备是否具备端侧文本识别能力 */
  static isAvailable(): boolean {
    return canIUse('SystemCapability.AI.OCR.TextRecognition');
  }

  /**
   * 自检：扩展进程里 Kit 能不能加载、OCR 服务能不能 init。
   * 图片 part 目前还没从小艺下发，先用这个探针证明「识别能力本身在 :agent 里可用」。
   */
  static async probe(context: common.Context): Promise<string> {
    const available: boolean = OcrService.isAvailable();
    let initialized: boolean = false;
    let message: string = '';
    if (available) {
      try {
        initialized = await textRecognition.init();
      } catch (e) {
        message = (e as Error).message;
      }
    }
    // 再拿一张内置图跑一遍真实识别：证明「解码 → PixelMap → recognizeText」在 :agent 里成立
    let head: string = '';
    if (initialized) {
      try {
        const text: string = await OcrService.recognizeRawFile(context, 'ocr-probe.png');
        head = text.length > 60 ? text.substring(0, 60) : text;
        head = head.split('\n').join(' / ');
        message = message.length > 0 ? message : ('ocrChars=' + text.length.toString());
      } catch (e) {
        message = 'ocrFailed:' + (e as Error).message;
      }
    }
    hilog.info(DOMAIN, TAG, 'PROBE available=%{public}s init=%{public}s msg=%{public}s',
      available ? 'true' : 'false', initialized ? 'true' : 'false', message);
    if (initialized) {
      await textRecognition.release();
    }
    return 'available=' + (available ? 'true' : 'false') + ' init='
      + (initialized ? 'true' : 'false') + (message.length > 0 ? ' (' + message + ')' : '')
      + (head.length > 0 ? ' → ' + head : '');
  }

  /** base64（raw part）→ 文本 */
  static async recognizeBase64(base64: string): Promise<string> {
    const helper: util.Base64Helper = new util.Base64Helper();
    const bytes: Uint8Array = helper.decodeSync(base64);
    const source: image.ImageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
    return OcrService.recognizeSource(source);
  }

  /** 应用内置图（rawfile）→ 文本，用于自检：不依赖任何外部输入 */
  static async recognizeRawFile(context: common.Context, name: string): Promise<string> {
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(name);
    const source: image.ImageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
    return OcrService.recognizeSource(source);
  }

  /** file:// uri（url part）→ 文本 */
  static async recognizeUri(uri: string): Promise<string> {
    const path: string = uri.startsWith('file://') ? uri.substring('file://'.length) : uri;
    const source: image.ImageSource = image.createImageSource(path);
    return OcrService.recognizeSource(source);
  }

  /** 一张图 → 多行文本（按视觉顺序拼行） */
  private static async recognizeSource(source: image.ImageSource): Promise<string> {
    if (!OcrService.isAvailable()) {
      throw new Error('CoreVisionKit text OCR is not supported on this device');
    }
    let pixelMap: image.PixelMap | undefined = undefined;
    let initialized: boolean = false;
    try {
      pixelMap = await source.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      });
      initialized = await textRecognition.init();
      if (!initialized) {
        throw new Error('CoreVisionKit initialization failed');
      }
      const result: textRecognition.TextRecognitionResult =
        await textRecognition.recognizeText({ pixelMap: pixelMap });
      return OcrService.extractText(result);
    } finally {
      if (initialized) {
        await textRecognition.release();
      }
      if (pixelMap !== undefined) {
        await pixelMap.release();
      }
      await source.release();
    }
  }

  private static extractText(result: textRecognition.TextRecognitionResult): string {
    const lines: string[] = [];
    for (let blockIndex = 0; blockIndex < result.blocks.length; blockIndex++) {
      const block: textRecognition.TextBlock = result.blocks[blockIndex];
      for (let lineIndex = 0; lineIndex < block.lines.length; lineIndex++) {
        const value: string = block.lines[lineIndex].value.trim();
        if (value.length > 0) {
          lines.push(value);
        }
      }
    }
    if (lines.length === 0) {
      const whole: string = result.value.trim();
      if (whole.length > 0) {
        lines.push(whole);
      }
    }
    hilog.info(DOMAIN, TAG, 'OCR done lines=%{public}d chars=%{public}d', lines.length,
      lines.join('\n').length);
    return lines.join('\n');
  }
}
