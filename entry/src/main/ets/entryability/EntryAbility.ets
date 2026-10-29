// ============================================================================
//  entryability/EntryAbility.ets — 应用入口
//  ----------------------------------------------------------------------------
//  路径: entry/src/main/ets/entryability/EntryAbility.ets
//  职责: 解析默认关闭的 NoteDetail benchmark + ArkWeb 启动期预热 + 初始化服务 + 加载首页。
//  依赖: NoteDetailBenchmarkLaunch, WebKeepAliveExperiment, ArkWebWarmupService,
//       LlmConfig, OcrConfig, OcrRecognizerRegistry, CoreVisionOcrRecognizer,
//       DatabaseHelper, Kit facades, ChatFilesDirSeam, ChatSessionManager。
//  沉浸式状态栏: app 内容延伸到 status bar 下方, status bar 背景透明。
//  视觉效果: 系统时间/电量/信号/wifi 浮在 app 内容上, 与 app 无缝衔接。
//  ============================================================================

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LlmConfig, OcrConfig, DatabaseHelper, OcrRecognizerRegistry, ImageSearchIndexRegistry, KnowledgeUnit } from 'common';
import { ReminderFacadeImpl } from '../kit/ReminderFacadeImpl';
import { CoreVisionOcrRecognizer } from '../services/CoreVisionOcrRecognizer';
import { CoreVisionImageSearchIndex } from '../services/CoreVisionImageSearchIndex';
import { DebugCaptureRunner } from '../services/DebugCaptureRunner';
import { ImageSearchWorkerProbe } from '../services/ImageSearchWorkerProbe';
import { FormCardFacadeImpl } from '../kit/FormCardFacadeImpl';
import { CardSnapshotService } from '../services/CardSnapshotService';
import { ArkWebWarmupService } from '../services/ArkWebWarmupService';
import { ChatFilesDirSeam, publishChatFilesDirSeam } from '../services/ChatFilesDirSeam';
import { ChatSessionManager } from '../overlays/AgentFloatWindow/chat/ChatSession';
import { WebKeepAliveExperiment } from '../services/WebKeepAliveExperiment';
import { ChatHistoryClearControl } from '../services/ChatHistoryClearControl';
import { A2AInboxIngestService } from '../services/A2AInboxIngestService';
import { AgentIngestService } from '../services/AgentIngestService';
import { AgentIngestRequest, buildIngestRequest, INGEST_SOURCE_APP_SHARE } from '../services/AgentIngestRequest';
import { AgentImagePart } from '../services/AgentImageParts';
import { KnowledgeUnitUiEffects } from '../services/KnowledgeUnitUiEffects';
import { CardUiEffectProvider } from '../services/KnowledgeUnitPostCommitEffects';
import {
  NOTE_DETAIL_BENCHMARK_CONFIG_KEY,
  NoteDetailBenchmarkLaunchConfig,
} from '../services/NoteDetailBenchmarkLaunch';

const DOMAIN = 0x0000;
/** 系统分享图片进来的两种 action（相册/文件管理器 → 分享 → MindTrace） */
const SHARE_ACTION_SEND_DATA: string = 'ohos.want.action.sendData';
const SHARE_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 卡片刷新这类 UI 副作用只能在主进程加载：注册一次，共享写路径按注册表取用
    KnowledgeUnitUiEffects.register(new CardUiEffectProvider());
    const benchmarkConfig: NoteDetailBenchmarkLaunchConfig =
      NoteDetailBenchmarkLaunchConfig.fromUri(want.uri ?? '');
    AppStorage.setOrCreate<NoteDetailBenchmarkLaunchConfig>(
      NOTE_DETAIL_BENCHMARK_CONFIG_KEY,
      benchmarkConfig,
    );
    WebKeepAliveExperiment.configure(benchmarkConfig.webKeepAliveEnabled);
    const warmupResult = ArkWebWarmupService.warmup();
    if (warmupResult.success) {
      hilog.info(DOMAIN, 'testTag', '%{public}s', warmupResult.diagnostic);
    } else {
      hilog.warn(DOMAIN, 'testTag', '%{public}s', warmupResult.diagnostic);
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // issue #227: OCR 端口实现在 entry 侧注册 — Kit 只在本进程加载, agents 只依赖 common 契约
    OcrRecognizerRegistry.install(new CoreVisionOcrRecognizer());
    // 文搜图端口实现同样在 entry 注册: textSearchImage 属 Core Vision Kit, 只能在 UI 进程加载
    ImageSearchIndexRegistry.install(new CoreVisionImageSearchIndex());
    // 初始化 LLM 配置(持久化 API key/endpoint/model)
    LlmConfig.getInstance().init(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'LlmConfig init failed: %{public}s', e.message);
    });
    // 初始化 OCR 配置(持久化 endpoint/enabled)
    OcrConfig.getInstance().init(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'OcrConfig init failed: %{public}s', e.message);
    });
    // 清空对话历史控制状态: 同步打开 Preferences, 失败降级且不阻断启动
    try {
      new ChatHistoryClearControl().init(this.context);
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'ChatHistoryClearControl init failed: %{public}s', JSON.stringify(e));
    }
    // 初始化数据库
    DatabaseHelper.init(this.context)
      .then((): Promise<void> => CardSnapshotService.refresh(this.context))
      .catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'DB/card init failed: %{public}s', e.message);
      });
    // F3 最小闭环 (spec 013 / ADR-0009): ReminderFacade 实现在组合根构造并注入
    AppStorage.setOrCreate<ReminderFacadeImpl>('reminderFacade', new ReminderFacadeImpl(this.context));
    AppStorage.setOrCreate<FormCardFacadeImpl>('formCardFacade', new FormCardFacadeImpl(this.context));
    // ticket-0.3 (#121): 应用级 filesDir 缝 — 组合根解析一次,发布纯字符串 seam(无 UI 上下文)
    const chatFilesDirSeam = ChatFilesDirSeam.fromApplicationContext(this.context.getApplicationContext());
    this.ingestSharedImage(want);
    publishChatFilesDirSeam(chatFilesDirSeam);
    if (chatFilesDirSeam.state === 'resolved') {
      hilog.info(DOMAIN, 'testTag', '%{public}s', chatFilesDirSeam.diagnostic);
    } else {
      hilog.warn(DOMAIN, 'testTag', '%{public}s', chatFilesDirSeam.diagnostic);
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /** 应用已在前台时又被分享拉起 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.ingestSharedImage(want);
  }

  /**
   * 系统分享进来的图片（相册 → 分享 → MindTrace）。
   *
   * 小艺客户端目前不把图片 part 转发给第三方智能体，所以图片进应用只能走这条系统分享通道。
   * 它和「存笔记」走的是同一个整理端口：OcrService 端侧识别 → 同一条 agent 链路 → 同一条写路径。
   */
  private ingestSharedImage(want: Want): void {
    const action: string = want.action ?? '';
    const uri: string = want.uri ?? '';
    const isShare: boolean = action === SHARE_ACTION_SEND_DATA || action === SHARE_ACTION_VIEW_DATA;
    if (!isShare || uri.length === 0) {
      return;
    }
    hilog.info(DOMAIN, 'testTag', 'SHARE_INGEST start action=%{public}s uri=%{public}s', action, uri);
    const image: AgentImagePart = { kind: 'uri', value: uri };
    const request: AgentIngestRequest = buildIngestRequest(INGEST_SOURCE_APP_SHARE, '', [image]);
    AgentIngestService.ingest(this.context, request)
      .then((unit: KnowledgeUnit): void => {
        hilog.info(DOMAIN, 'testTag', 'SHARE_INGEST done subject=%{public}s title=%{public}s',
          unit.subject, unit.title);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, 'testTag', 'SHARE_INGEST failed %{public}s', e.message);
      });
  }

  /**
   * 启动参数 e2e=true 时自动跑一次批量链路自检。
   * 给真机脚本用：`aa start ... --ps e2e true`，省去连点标题再滑到底找按钮的 UI 路径。
   * e2e=search 只跑检索探针；e2e=worker 跑 S1 Worker 可用性探针。
   */
  private async runE2eIfRequested(): Promise<void> {
    const flag: Object | undefined = this.launchWant?.parameters?.['e2e'];
    if (flag === undefined) {
      return;
    }
    const mode: string = flag.toString();
    hilog.info(0xE2E0, 'E2E', '%{public}s', 'launch-param e2e=' + mode + ', 触发自检');
    if (mode === 'search') {
      DebugCaptureRunner.runSearchProbe().catch((e: Error) => {
        hilog.error(0xE2E0, 'E2E', '%{public}s', '检索探针异常: ' + e.message);
      });
      return;
    }
    if (mode === 'worker') {
      try {
        const ok: boolean = await ImageSearchWorkerProbe.run();
        hilog.info(0xE2E0, 'E2E', '%{public}s',
          'stage=worker-probe ok=' + (ok ? 'true' : 'false'));
      } catch (error) {
        const e: Error = error as Error;
        hilog.error(0xE2E0, 'E2E', '%{public}s', 'stage=worker-probe ok=false err=' + e.message);
      }
      return;
    }
    if (mode !== 'true') {
      return;
    }
    DebugCaptureRunner.run(this.context).catch((e: Error) => {
      hilog.error(0xE2E0, 'E2E', '%{public}s', '批量自检异常: ' + e.message);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 沉浸式状态栏: app 内容延伸到 status bar 下方, status bar 背景透明
    // 视觉效果: 系统时间/电量/信号/wifi 浮在 app 内容上, 与 app 无缝衔接
    windowStage.getMainWindow().then((win: window.Window) => {
      // 1. 沉浸式全屏(app 内容延伸到 status bar 下方)
      win.setWindowLayoutFullScreen(true);
      // 2. 状态栏背景透明(使 app 背景透出, 与 status bar 融为一体)
      win.setSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#FFFFFFFF'  // 白色图标(适配深色 app 背景)
      });
      // 3. 获取状态栏高度存入 AppStorage, 各页面据此偏移避免重叠
      try {
        const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        AppStorage.setOrCreate('statusBarHeight', px2vp(avoidArea.topRect.height));
        const navigationArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate('navigationBarHeight', px2vp(navigationArea.bottomRect.height));
        win.on('avoidAreaChange', (event) => {
          if (event.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
            AppStorage.setOrCreate('navigationBarHeight', px2vp(event.area.bottomRect.height));
          }
        });
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'Failed to get statusBarHeight. Cause: %{public}s', JSON.stringify(e));
      }
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to set immersive status bar. Cause: %{public}s', JSON.stringify(err));
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 自检依赖窗口/OCR 就绪，必须等内容加载完成再跑（onCreate 阶段跑会卡在 Dispatcher）
      setTimeout((): void => {
        this.runE2eIfRequested().catch((e: Error) => {
          hilog.error(0xE2E0, 'E2E', '%{public}s', '自检异常: ' + e.message);
        });
      }, 1200);
    });
  }

  onWindowStageDestroy(): void { hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy'); }
  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 小艺侧排进队列的待整理原文：回到应用时逐条走正规写路径入库（队列空则立即返回）
    A2AInboxIngestService.consume(this.context).catch((e: Error): void => {
      hilog.error(DOMAIN, 'testTag', 'A2A inbox consume failed: %{public}s', e.message);
    });
    A2AInboxIngestService.startWatch(this.context);
  }
  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    A2AInboxIngestService.stopWatch();
    ChatSessionManager.flushActive().catch((e: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'Chat history flush failed: %{public}s', e.message);
    });
    this.refreshCardSnapshot().catch((e: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'Card refresh failed: %{public}s', e.message);
    });
  }

  // v1 不做复习同步/备份，卡片快照改为退到后台时直接刷新，不再申请后台任务
  private async refreshCardSnapshot(): Promise<void> {
    await CardSnapshotService.refresh(this.context);
  }
}
