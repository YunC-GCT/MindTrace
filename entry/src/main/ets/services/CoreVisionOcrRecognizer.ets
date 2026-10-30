// ============================================================================
//  services/CoreVisionOcrRecognizer.ets — CoreVisionKit OCR 适配器 (issue #227)
//  ----------------------------------------------------------------------------
//  Process: main 与 :agent 都会安装它 (EntryAbility.onCreate / AgentExtAbility.onCreate
//  各自的组合根)；真机实测 :agent 里 PROBE available=true init=true (ocrChars=48)。
//  仍不得进 common 的 barrel (common/Index.ets 不导出本文件)。
//  路径: entry/src/main/ets/services/CoreVisionOcrRecognizer.ets
//  职责: 承接原 OcrTool 内的 CoreVisionKit + ImageKit 调用 (初始化 / 文本识别 /
//        资源释放 / 失败文案), 对 common 端口暴露纯文本结果。
//  依赖: @kit.CoreVisionKit (textRecognition), @kit.ImageKit (image), @kit.ArkTS (util),
//        @kit.PerformanceAnalysisKit (hilog), common 端口契约 (OcrRecognizer / OcrTextResult)
//  数据流: 组合根 install → OcrRecognizerRegistry.require()
//          → recognize(uri) / recognizeBase64(base64) → recognizeSource(source)
//          → OcrTextResult
// ============================================================================

import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { OcrRecognizer, OcrTextResult } from 'common';

const NEWLINE: string = String.fromCharCode(10);
// 与入口侧 OcrService 同一 TAG/域：真机上一条 hilog 过滤就能看到识别结果行。
const DOMAIN: number = 0xA2A0;
const TAG: string = 'XiaoyiOcr';

export class CoreVisionOcrRecognizer implements OcrRecognizer {
  isAvailable(): boolean {
    return canIUse('SystemCapability.AI.OCR.TextRecognition');
  }

  async recognize(uri: string): Promise<OcrTextResult> {
    const filePath: string = this.normalizeFilePath(uri);
    const source: image.ImageSource = image.createImageSource(filePath);
    return this.recognizeSource(source);
  }

  async recognizeBase64(base64: string): Promise<OcrTextResult> {
    const helper: util.Base64Helper = new util.Base64Helper();
    const bytes: Uint8Array = helper.decodeSync(base64);
    const source: image.ImageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
    return this.recognizeSource(source);
  }

  /** 一张 ImageSource → 多行文本。recognize(uri) 与 recognizeBase64 共用同一条 Kit 调用链。 */
  private async recognizeSource(source: image.ImageSource): Promise<OcrTextResult> {
    let pixelMap: image.PixelMap | undefined = undefined;
    let serviceInitialized: boolean = false;

    try {
      if (!this.isAvailable()) {
        throw new Error('CoreVisionKit text OCR is not supported on this device');
      }
      pixelMap = await source.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      });

      serviceInitialized = await textRecognition.init();
      if (!serviceInitialized) {
        throw new Error('CoreVisionKit initialization failed');
      }

      const result: textRecognition.TextRecognitionResult =
        await textRecognition.recognizeText({ pixelMap: pixelMap });
      return {
        text: this.extractText(result),
        // CoreVisionKit 只回文本与坐标, 不暴露置信度; 0 表示未知。
        confidence: 0,
      };
    } finally {
      if (serviceInitialized) {
        await textRecognition.release();
      }
      if (pixelMap !== undefined) {
        await pixelMap.release();
      }
      await source.release();
    }
  }

  private extractText(result: textRecognition.TextRecognitionResult): string {
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

    const fullText: string = result.value.trim();
    if (lines.length === 0 && fullText.length > 0) {
      lines.push(fullText);
    }
    const text: string = lines.join(NEWLINE);
    hilog.info(DOMAIN, TAG, 'OCR done lines=%{public}d chars=%{public}d', lines.length, text.length);
    return text;
  }

  private normalizeFilePath(uri: string): string {
    if (uri.startsWith('file://')) {
      return uri.substring('file://'.length);
    }
    return uri;
  }
}
