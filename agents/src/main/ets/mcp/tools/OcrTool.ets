import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { OcrConfig } from 'common';

export interface OcrRecognitionResult {
  success: boolean;
  formulas: string[];
  textLines: string[];
  text: string;
  message: string;
}

interface FormulaResponse {
  success: boolean;
  count: number;
  formulas: string[];
  message: string;
}

interface CombinedOcrResponse {
  success: boolean;
  formula_count: number;
  formulas: string[];
  text_line_count: number;
  text_lines: string[];
  text: string;
  message: string;
  mode?: string;
  formula_skipped?: boolean;
  formula_timeout?: boolean;
  formula_rejected?: boolean;
}

interface OcrError {
  code?: number;
  message?: string;
}

interface OcrUploadFile {
  filePath: string;
  fileName: string;
  contentType: string;
}

/**
 * Hybrid image recognition:
 * - HarmonyOS CoreVisionKit recognizes ordinary text on supported devices.
 * - The local OCR service is used as fallback text OCR and formula OCR.
 * - A partial result still succeeds when either text or formula recognition works.
 */
export class OcrTool {
  private formulaEndpoint: string;

  constructor(formulaEndpoint?: string) {
    this.formulaEndpoint = formulaEndpoint ??
      'http://127.0.0.1:8000/api/v1/formula/recognize';
  }

  async recognizeBytes(imageBytes: ArrayBuffer, fileName: string = 'upload.png'): Promise<OcrRecognitionResult> {
    return await this.recognizeBytesWithEndpoint(imageBytes, OcrConfig.getInstance().getEndpoint(), fileName);
  }

  async recognizeBytesWithEndpoint(
    imageBytes: ArrayBuffer,
    endpoint: string,
    fileName: string = 'upload.png',
    mode?: string,
  ): Promise<OcrRecognitionResult> {
    let lastError: string = '';
    const target: string = endpoint.trim().length > 0
      ? this.withOcrMode(OcrConfig.normalizeEndpointInput(endpoint), mode ?? OcrConfig.getInstance().getMode())
      : this.resolveOcrEndpoint(mode);
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const raw: string = await this.postBytes(target, imageBytes, fileName);
        const response: CombinedOcrResponse = JSON.parse(raw) as CombinedOcrResponse;
        return {
          success: response.success,
          formulas: response.formulas ?? [],
          textLines: response.text_lines ?? [],
          text: response.text ?? '',
          message: response.message ?? '',
        };
      } catch (e) {
        lastError = this.errorText(e as OcrError);
      }
    }
    return {
      success: false,
      formulas: [],
      textLines: [],
      text: '',
      message: 'OCR request failed: ' + lastError,
    };
  }

  async recognize(imageUri: string): Promise<string> {
    const result: OcrRecognitionResult = await this.recognizeImage(imageUri);
    if (!result.success) {
      throw new Error('OCR failed: ' + result.message);
    }

    const promptText: string = this.toPromptText(result);
    if (promptText.trim().length === 0) {
      throw new Error('OCR returned empty text');
    }
    return promptText;
  }

  async recognizeImage(imageUri: string): Promise<OcrRecognitionResult> {
    const filePath: string = this.normalizeFilePath(imageUri);
    const mode: string = OcrConfig.getInstance().getMode();
    let textLines: string[] = [];
    let formulas: string[] = [];
    let textError: string = '';
    let serverError: string = '';
    let usedServerFallback: boolean = false;

    try {
      textLines = await this.recognizeLocalText(filePath);
    } catch (e) {
      textError = this.errorText(e as OcrError);
    }

    if (textError.length > 0 || mode !== 'text') {
      try {
        const response: CombinedOcrResponse = await this.requestCombinedWithRetry(filePath, mode);
        if (response.success) {
          if (textLines.length === 0) {
            textLines = response.text_lines ?? [];
            if (textLines.length === 0 && response.text.trim().length > 0) {
              textLines.push(response.text.trim());
            }
          }
          formulas = response.formulas ?? [];
          if (textLines.length > 0 || formulas.length > 0) {
            textError = '';
            usedServerFallback = true;
          }
          if ((response.formula_timeout === true || response.formula_rejected === true) && formulas.length === 0) {
            serverError = response.message;
          }
        } else {
          serverError = response.message;
        }
      } catch (e) {
        serverError = this.errorText(e as OcrError);
      }
    }

    const text: string = textLines.join('\n');
    const success: boolean = text.trim().length > 0 || formulas.length > 0;
    const messages: string[] = [];
    if (!success && textError.length > 0) {
      messages.push('Local text OCR: ' + textError);
    }
    if (!success && serverError.length > 0) {
      messages.push('Server OCR: ' + serverError);
    }
    if (messages.length === 0) {
      const source: string = usedServerFallback ? 'server fallback' : 'on-device text OCR';
      messages.push('Recognized ' + textLines.length.toString() +
        ' text lines and ' + formulas.length.toString() + ' formulas using ' + source);
    }

    return {
      success: success,
      formulas: formulas,
      textLines: textLines,
      text: text,
      message: messages.join('; '),
    };
  }

  private async recognizeLocalText(filePath: string): Promise<string[]> {
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      throw new Error('CoreVisionKit text OCR is not supported on this device');
    }

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
      return this.extractTextLines(result);
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

  private extractTextLines(result: textRecognition.TextRecognitionResult): string[] {
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
    return lines;
  }

  private resolveFormulaEndpoint(): string {
    const ocrEndpoint: string = OcrConfig.getInstance().getEndpoint();
    const ocrSuffix: string = '/api/v1/ocr/recognize';
    if (ocrEndpoint.endsWith(ocrSuffix)) {
      return ocrEndpoint.substring(0, ocrEndpoint.length - ocrSuffix.length) + '/api/v1/formula/recognize';
    }

    const routerSuffix: string = '/recognize';
    if (ocrEndpoint.endsWith(routerSuffix)) {
      return ocrEndpoint.substring(0, ocrEndpoint.length - routerSuffix.length) + '/formula/recognize';
    }

    return this.formulaEndpoint;
  }

  private resolveOcrEndpoint(mode?: string): string {
    return this.withOcrMode(OcrConfig.getInstance().getEndpoint(), mode ?? OcrConfig.getInstance().getMode());
  }

  private withOcrMode(endpoint: string, mode: string): string {
    const normalizedMode: string = OcrConfig.normalizeModeInput(mode);
    const separator: string = endpoint.indexOf('?') >= 0 ? '&' : '?';
    return endpoint + separator + 'mode=' + normalizedMode + '&formula_timeout=30';
  }

  private async requestFormulaWithRetry(filePath: string): Promise<FormulaResponse> {
    let lastError: string = '';
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const responseText: string = await this.postImage(this.resolveFormulaEndpoint(), filePath);
        return JSON.parse(responseText) as FormulaResponse;
      } catch (e) {
        lastError = this.errorText(e as OcrError);
      }
    }
    throw new Error('Formula request failed: ' + lastError);
  }

  private async requestCombinedWithRetry(filePath: string, mode?: string): Promise<CombinedOcrResponse> {
    let lastError: string = '';
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const responseText: string = await this.postImage(this.resolveOcrEndpoint(mode), filePath);
        return JSON.parse(responseText) as CombinedOcrResponse;
      } catch (e) {
        lastError = this.errorText(e as OcrError);
      }
    }
    throw new Error('Fallback OCR request failed: ' + lastError);
  }

  private async postImage(endpoint: string, filePath: string): Promise<string> {
    const uploadFile: OcrUploadFile = await this.prepareUploadFile(filePath);
    const httpReq: http.HttpRequest = http.createHttp();

    try {
      const response: http.HttpResponse = await httpReq.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'multipart/form-data',
        },
        multiFormDataList: [
          {
            name: 'file',
            contentType: uploadFile.contentType,
            filePath: uploadFile.filePath,
            remoteFileName: uploadFile.fileName,
          },
        ],
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 300000,
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('HTTP ' + response.responseCode.toString() + ': ' +
          (response.result as string));
      }
      return response.result as string;
    } finally {
      httpReq.destroy();
    }
  }

  private async prepareUploadFile(filePath: string): Promise<OcrUploadFile> {
    return {
      filePath: filePath,
      fileName: this.fileNameFromUri(filePath),
      contentType: this.mimeFromName(filePath),
    };
  }

  private async postBytes(endpoint: string, imageBytes: ArrayBuffer, fileName: string): Promise<string> {
    const boundary: string = '----MindTraceOcr' + Date.now().toString();
    const fileBytes: Uint8Array = new Uint8Array(imageBytes);
    const header: Uint8Array = this.strToUtf8(
      '--' + boundary + '\r\n' +
      'Content-Disposition: form-data; name="file"; filename="' + fileName + '"\r\n' +
      'Content-Type: ' + this.mimeFromName(fileName) + '\r\n\r\n',
    );
    const footer: Uint8Array = this.strToUtf8('\r\n--' + boundary + '--\r\n');
    const body: Uint8Array = new Uint8Array(header.length + fileBytes.length + footer.length);
    body.set(header, 0);
    body.set(fileBytes, header.length);
    body.set(footer, header.length + fileBytes.length);

    const httpReq: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpReq.request(endpoint, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'multipart/form-data; boundary=' + boundary },
        extraData: body.buffer as ArrayBuffer,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 120000,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('HTTP ' + response.responseCode.toString() + ': ' + (response.result as string));
      }
      return response.result as string;
    } finally {
      httpReq.destroy();
    }
  }

  private strToUtf8(value: string): Uint8Array {
    const buffer: Uint8Array = new Uint8Array(value.length * 3);
    let offset: number = 0;
    for (let i = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i);
      if (code < 0x80) {
        buffer[offset] = code;
        offset = offset + 1;
      } else if (code < 0x800) {
        buffer[offset] = 0xC0 | (code >> 6);
        buffer[offset + 1] = 0x80 | (code & 0x3F);
        offset = offset + 2;
      } else {
        buffer[offset] = 0xE0 | (code >> 12);
        buffer[offset + 1] = 0x80 | ((code >> 6) & 0x3F);
        buffer[offset + 2] = 0x80 | (code & 0x3F);
        offset = offset + 3;
      }
    }
    return buffer.slice(0, offset);
  }

  private toPromptText(result: OcrRecognitionResult): string {
    const parts: string[] = [];
    const text: string = result.text.trim();
    if (text.length > 0) {
      parts.push(text);
    }
    if (result.formulas.length > 0) {
      parts.push('LaTeX formulas:\n' + result.formulas.join('\n'));
    }
    return parts.join('\n\n');
  }

  private errorText(error: OcrError): string {
    const message: string = error.message ?? 'Unknown error';
    if (error.code === undefined) {
      return message;
    }
    return 'code=' + error.code.toString() + ', message=' + message;
  }

  private normalizeFilePath(imageUri: string): string {
    if (imageUri.startsWith('file://')) {
      return imageUri.substring('file://'.length);
    }
    return imageUri;
  }

  private fileNameFromUri(uri: string): string {
    const clean: string = uri.split('?')[0];
    const slash: number = clean.lastIndexOf('/');
    const backslash: number = clean.lastIndexOf('\\');
    const index: number = Math.max(slash, backslash);
    if (index >= 0 && index + 1 < clean.length) {
      return clean.substring(index + 1);
    }
    return 'upload.png';
  }

  private mimeFromName(fileName: string): string {
    const lower: string = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.bmp')) {
      return 'image/bmp';
    }
    return 'image/png';
  }
}
