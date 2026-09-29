/**
 * ArkWebWarmupService.ets — ArkWeb startup warmup gate
 *
 * 路径: entry/src/main/ets/services/ArkWebWarmupService.ets
 * 职责: 在 EntryAbility 启动期固定 ArkWeb 单渲染进程模式并预热引擎，维护进程内基线前置状态。
 * 依赖: @ohos.web.webview, @kit.BasicServicesKit
 *
 * 数据流:
 *   EntryAbility.onCreate() → ArkWebWarmupService.warmup() → ArkWeb platform adapter → BenchmarkBaselinePrecondition query
 *
 * 说明: 不读取或写入用户 chat/OCR/LLM 内容，不修改 Preferences chat history；失败诊断只保留安全错误元数据。
 *
 * ArkTS 1.1 strict 适配:
 *   - catch 变量不标注类型，通过 BusinessError/Error 显式断言抽取安全字段。
 */

import { BusinessError } from '@kit.BasicServicesKit';
import webview from '@ohos.web.webview';

export interface ArkWebPlatformAdapter {
  setRenderProcessMode(mode: webview.RenderProcessMode): void;
  initializeWebEngine(): void;
}

export interface BenchmarkBaselinePrecondition {
  state: 'initial' | 'valid' | 'invalid';
  diagnostic: string;
}

export interface WarmupResult {
  success: boolean;
  // True only when a recoverable platform/API failure left the gate invalid.
  recoverable: boolean;
  diagnostic: string;
}

const INITIAL_DIAGNOSTIC: string = 'ArkWeb warmup has not been attempted';
const SUCCESS_DIAGNOSTIC: string = 'ArkWeb engine warmup completed';
const FAILURE_DIAGNOSTIC: string = 'ArkWeb engine warmup failed; baseline is unavailable';
const ERROR_CODE_NONE: string = 'none';

interface WarmupFailureMetadata {
  name: string;
  code: string;
}

class ArkWebStaticPlatformAdapter implements ArkWebPlatformAdapter {
  setRenderProcessMode(mode: webview.RenderProcessMode): void {
    webview.WebviewController.setRenderProcessMode(mode);
  }

  initializeWebEngine(): void {
    webview.WebviewController.initializeWebEngine();
  }
}

let platformAdapter: ArkWebPlatformAdapter = new ArkWebStaticPlatformAdapter();
let precondition: BenchmarkBaselinePrecondition = {
  state: 'initial',
  diagnostic: INITIAL_DIAGNOSTIC,
};

const sanitizeMetadata = (value: string, fallback: string): string => {
  let sanitized: string = '';
  let index: number = 0;
  while (index < value.length && sanitized.length < 64) {
    const character: string = value.charAt(index);
    const isLowercase: boolean = character >= 'a' && character <= 'z';
    const isUppercase: boolean = character >= 'A' && character <= 'Z';
    const isDigit: boolean = character >= '0' && character <= '9';
    if (isLowercase || isUppercase || isDigit || character === '_' || character === '-' || character === '.') {
      sanitized += character;
    } else {
      sanitized += '_';
    }
    index += 1;
  }
  return sanitized.length === 0 ? fallback : sanitized;
};

const buildFailureDiagnostic = (e: Object): string => {
  const error: Error = e as Error;
  const businessError: BusinessError = e as BusinessError;
  const rawName: string = error.name === undefined ? 'Error' : error.name;
  const rawCode: string = businessError.code === undefined ? ERROR_CODE_NONE : businessError.code.toString();
  const metadata: WarmupFailureMetadata = {
    name: sanitizeMetadata(rawName, 'Error'),
    code: sanitizeMetadata(rawCode, ERROR_CODE_NONE),
  };
  return FAILURE_DIAGNOSTIC
    + '; errorName=' + metadata.name
    + '; errorCode=' + metadata.code;
};

const setInvalid = (diagnostic: string): WarmupResult => {
  precondition = {
    state: 'invalid',
    diagnostic: diagnostic,
  };
  return {
    success: false,
    recoverable: true,
    diagnostic: diagnostic,
  };
};

export class ArkWebWarmupService {
  private static buildSuccessResult(): WarmupResult {
    return {
      success: true,
      recoverable: false,
      diagnostic: SUCCESS_DIAGNOSTIC,
    };
  }

  public static warmup(): WarmupResult {
    if (precondition.state === 'valid') {
      return ArkWebWarmupService.buildSuccessResult();
    }
    try {
      platformAdapter.setRenderProcessMode(webview.RenderProcessMode.SINGLE);
      platformAdapter.initializeWebEngine();
      precondition = {
        state: 'valid',
        diagnostic: SUCCESS_DIAGNOSTIC,
      };
      return ArkWebWarmupService.buildSuccessResult();
    } catch (e) {
      return setInvalid(buildFailureDiagnostic(e));
    }
  }

  public static getBenchmarkBaselinePrecondition(): BenchmarkBaselinePrecondition {
    return {
      state: precondition.state,
      diagnostic: precondition.diagnostic,
    };
  }

  public static setPlatformAdapterForTest(adapter: ArkWebPlatformAdapter): void {
    platformAdapter = adapter;
  }

  public static resetForTest(): void {
    platformAdapter = new ArkWebStaticPlatformAdapter();
    precondition = {
      state: 'initial',
      diagnostic: INITIAL_DIAGNOSTIC,
    };
  }
}
