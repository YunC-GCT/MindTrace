// ============================================================================
//  services/CoreVisionOcrRecognizer.ets — CoreVisionKit OCR 适配器 (issue #227)
//  ----------------------------------------------------------------------------
//  Process: main only. 不得被 agent / agentUI 入口可达，也不得进 common barrel；
//  Kit 只允许在 UI 进程加载 (spec 033 R2/R3)。
//  路径: entry/src/main/ets/services/CoreVisionOcrRecognizer.ets
//  职责: 承接原 OcrTool 内的 CoreVisionKit + ImageKit 调用 (初始化 / 文本识别 /
//        资源释放 / 失败文案), 对 common 端口暴露纯文本结果。
//  依赖: @kit.CoreVisionKit (textRecognition), @kit.ImageKit (image),
//        common 端口契约 (OcrRecognizer / OcrTextResult)
//  数据流: OcrTool.recognizeImage → OcrRecognizerRegistry.require()
//          → CoreVisionOcrRecognizer.recognize(uri) → OcrTextResult
// ============================================================================

import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import type { OcrRecognizer, OcrTextResult } from 'common';

export class CoreVisionOcrRecognizer implements OcrRecognizer {
  isAvailable(): boolean {
    return canIUse('SystemCapability.AI.OCR.TextRecognition');
  }

  async recognize(uri: string): Promise<OcrTextResult> {
    if (!this.isAvailable()) {
      throw new Error('CoreVisionKit text OCR is not supported on this device');
    }

    const filePath: string = this.normalizeFilePath(uri);
    const source: image.ImageSource = image.createImageSource(filePath);
    let pixelMap: image.PixelMap | undefined = undefined;
    let serviceInitialized: boolean = false;

    try {
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
    return lines.join('\n');
  }

  private normalizeFilePath(uri: string): string {
    if (uri.startsWith('file://')) {
      return uri.substring('file://'.length);
    }
    return uri;
  }
}
