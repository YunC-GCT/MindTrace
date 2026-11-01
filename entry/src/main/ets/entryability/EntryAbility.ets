// ============================================================================
//  entryability/EntryAbility.ets — 应用入口
//  ----------------------------------------------------------------------------
//  路径: entry/src/main/ets/entryability/EntryAbility.ets
//  职责: 解析默认关闭的 NoteDetail benchmark + ArkWeb 启动期预热 + 初始化服务 + 加载首页 +
//       消费小艺 AgentUiCard 回传的 mtAction（pick_from_card / camera_from_card）。
//  依赖: NoteDetailBenchmarkLaunch, WebKeepAliveExperiment, ArkWebWarmupService,
//       LlmConfig, OcrConfig, OcrRecognizerRegistry, CoreVisionOcrRecognizer,
//       DatabaseHelper, Kit facades, ChatFilesDirSeam, ChatSessionManager,
//       AlbumPickerLauncher, CameraKitLauncher, AgentIngestService。
//  沉浸式状态栏: app 内容延伸到 status bar 下方, status bar 背景透明。
//  视觉效果: 系统时间/电量/信号/wifi 浮在 app 内容上, 与 app 无缝衔接。
//  ============================================================================

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LlmConfig, OcrConfig, DatabaseHelper, OcrRecognizerRegistry, ImageSearchIndexRegistry, KnowledgeUnit, NoteReadPortAdapter, RdbNoteReadStore } from 'common';
import { ReminderFacadeImpl } from '../kit/ReminderFacadeImpl';
import { CoreVisionOcrRecognizer } from '../services/CoreVisionOcrRecognizer';
import { CoreVisionImageSearchIndex } from '../services/CoreVisionImageSearchIndex';
import { DebugDraftRunner } from '../services/DebugDraftRunner';
import { DebugCaptureRunner } from '../services/DebugCaptureRunner';
import { ImageSearchWorkerProbe } from '../services/ImageSearchWorkerProbe';
import { FormCardFacadeImpl } from '../kit/FormCardFacadeImpl';
import { CardSnapshotService } from '../services/CardSnapshotService';
import { configureEvidenceReadPort } from '../services/NoteReviewService';
import { ArkWebWarmupService } from '../services/ArkWebWarmupService';
import { ChatFilesDirSeam, publishChatFilesDirSeam } from '../services/ChatFilesDirSeam';
import { ChatSessionManager } from '../overlays/AgentFloatWindow/chat/ChatSession';
import { WebKeepAliveExperiment } from '../services/WebKeepAliveExperiment';
import { ChatHistoryClearControl } from '../services/ChatHistoryClearControl';
import { A2AInboxIngestService } from '../services/A2AInboxIngestService';
import { uiProcessEnabled } from '../services/WriteJobConfig';
import { WriteJobEventRecorder } from '../services/WriteJobEventRecorder';
import { WriteJobFlags, WriteJobScheduler } from '../services/WriteJobScheduler';
import { AgentIngestService } from '../services/AgentIngestService';
import {
  AgentIngestRequest,
  buildIngestRequest,
  INGEST_SOURCE_APP_PICKER,
  INGEST_SOURCE_APP_SHARE,
} from '../services/AgentIngestRequest';
import { AgentImagePart } from '../services/AgentImageParts';
import { AlbumPickerLauncher } from '../services/AlbumPickerLauncher';
import { CameraKitLauncher } from '../services/CameraKitLauncher';
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
/** AgentUiCard 回传的两个选图意图（与 pages/AgentUiCard.ets 约定一致） */
const CARD_ACTION_PICK: string = 'pick_from_card';
const CARD_ACTION_CAMERA: string = 'camera_from_card';

export default class EntryAbility extends UIAbility {
  /** 卡片带回、等待页面恢复后消费的意图；空串表示没有 */
  private pendingCardAction: string = '';
  /** 窗口内容是否已加载：Picker 必须在 UI 起来后再拉 */
  private windowReady: boolean = false;
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // e2e 调试入口：冷启动也要保存 launchWant，onWindowStageCreate 里才能读到 --ps e2e。
    this.launchWant = want;
    // 卡片刷新这类 UI 副作用只能在主进程加载：注册一次，共享写路径按注册表取用
    KnowledgeUnitUiEffects.register(new CardUiEffectProvider());
    // S2：UI 进程启用调度器（扩展进程不读此配置，继续走旧路径），并把 job 事件落 run_event。
    if (uiProcessEnabled()) {
      WriteJobFlags.setEnabled(true);
    }
    WriteJobScheduler.shared().setEventSink(WriteJobEventRecorder.create());
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
      .then((): Promise<void> => {
        // ADR-0021 Step 3：DB 就绪后把只读端口注入证据服务组合根（未就绪则保持既有 SQL 路径）
        const readStore: RdbNoteReadStore | null = RdbNoteReadStore.fromDatabase();
        configureEvidenceReadPort(readStore === null ? undefined : new NoteReadPortAdapter(readStore));
        return CardSnapshotService.refresh(this.context);
      })
      .catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'DB/card init failed: %{public}s', e.message);
      });
    // F3 最小闭环 (spec 013 / ADR-0009): ReminderFacade 实现在组合根构造并注入
    AppStorage.setOrCreate<ReminderFacadeImpl>('reminderFacade', new ReminderFacadeImpl(this.context));
    AppStorage.setOrCreate<FormCardFacadeImpl>('formCardFacade', new FormCardFacadeImpl(this.context));
    // ticket-0.3 (#121): 应用级 filesDir 缝 — 组合根解析一次,发布纯字符串 seam(无 UI 上下文)
    const chatFilesDirSeam = ChatFilesDirSeam.fromApplicationContext(this.context.getApplicationContext());
    this.ingestSharedImage(want);
    this.readCardAction(want);
    publishChatFilesDirSeam(chatFilesDirSeam);
    if (chatFilesDirSeam.state === 'resolved') {
      hilog.info(DOMAIN, 'testTag', '%{public}s', chatFilesDirSeam.diagnostic);
    } else {
      hilog.warn(DOMAIN, 'testTag', '%{public}s', chatFilesDirSeam.diagnostic);
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /** 应用已在前台时又被分享 / 卡片拉起 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // e2e 调试入口：aa start --ps e2e <mode> 在已有实例上也要触发（无需重建窗口）。
    if (want.parameters !== undefined && want.parameters['e2e'] !== undefined) {
      this.launchWant = want;
      this.runE2eIfRequested().catch((e: Error) => {
        hilog.error(0xE2E0, 'E2E', '%{public}s', 'e2e(onNewWant) 异常: ' + e.message);
      });
    }
    this.ingestSharedImage(want);
    this.readCardAction(want);
    this.consumeCardAction();
  }

  /**
   * 读 AgentUiCard 回传的 mtAction：只认 pick_from_card / camera_from_card。
   * 真机验收看这一行：CARD_ACTION received action=...
   */
  private readCardAction(want: Want): void {
    const action: Object | undefined = want.parameters?.['mtAction'];
    if (action === undefined) {
      return;
    }
    const value: string = action.toString();
    if (value !== CARD_ACTION_PICK && value !== CARD_ACTION_CAMERA) {
      hilog.warn(DOMAIN, 'testTag', 'CARD_ACTION ignored action=%{public}s', value);
      return;
    }
    this.pendingCardAction = value;
    hilog.info(DOMAIN, 'testTag', 'CARD_ACTION received action=%{public}s', value);
  }

  /**
   * 页面恢复后再消费卡片意图：扩展进程不能拉 Picker，这里用 UIAbilityContext 拉系统 Picker，
   * 选中的图直接复用分享通道的同一条整理链路（AgentIngestService）。
   * pending 在启动前清空，避免回到前台时重复弹 Picker。
   */
  private consumeCardAction(): void {
    const action: string = this.pendingCardAction;
    if (!this.windowReady || action.length === 0) {
      return;
    }
    this.pendingCardAction = '';
    if (action === CARD_ACTION_CAMERA) {
      hilog.info(DOMAIN, 'testTag', 'CARD_ACTION camera start');
      CameraKitLauncher.capture(this.context)
        .then((uri: string): void => {
          this.ingestImage(uri, INGEST_SOURCE_APP_PICKER);
        })
        .catch((e: Error): void => {
          hilog.warn(DOMAIN, 'testTag', 'CARD_ACTION camera cancelled/failed: %{public}s', e.message);
        });
      return;
    }
    hilog.info(DOMAIN, 'testTag', 'CARD_ACTION album start');
    AlbumPickerLauncher.pick(this.context, 1)
      .then((uris: string[]): void => {
        if (uris.length === 0) {
          hilog.info(DOMAIN, 'testTag', 'CARD_ACTION album cancelled');
          return;
        }
        this.ingestImage(uris[0], INGEST_SOURCE_APP_PICKER);
      })
      .catch((e: Error): void => {
        hilog.warn(DOMAIN, 'testTag', 'CARD_ACTION album cancelled/failed: %{public}s', e.message);
      });
  }

  /**
   * 单张图片的统一整理入口：系统分享与卡片选图共用。
   * 与 A2A 图片 part 走同一个 AgentIngestService 端口（OCR → Dispatcher → 写路径）。
   */
  private ingestImage(uri: string, source: string): void {
    if (uri.length === 0) {
      return;
    }
    const image: AgentImagePart = { kind: 'uri', value: uri };
    const request: AgentIngestRequest = buildIngestRequest(source, '', [image]);
    AgentIngestService.ingest(this.context, request)
      .then((unit: KnowledgeUnit): void => {
        hilog.info(DOMAIN, 'testTag', '%{public}s done subject=%{public}s title=%{public}s',
          source, unit.subject, unit.title);
      })
      .catch((e: Error): void => {
        hilog.error(DOMAIN, 'testTag', '%{public}s failed %{public}s', source, e.message);
      });
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
    this.ingestImage(uri, INGEST_SOURCE_APP_SHARE);
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
    if (mode === 'ragSearch') {
      this.runDebugProbe('ragSearch', DebugCaptureRunner.runRagSearch(this.context));
      return;
    }
    if (mode === 'ragProbe') {
      this.runDebugProbe('ragProbe', DebugCaptureRunner.runRagProbe(this.context));
      return;
    }
    if (mode === 'schedulerStress') {
      this.runDebugProbe('schedulerStress', DebugCaptureRunner.runSchedulerStress(this.context));
      return;
    }
    if (mode === 'schedulerIntegration') {
      this.runDebugProbe('schedulerIntegration', DebugCaptureRunner.runSchedulerIntegration(this.context));
      return;
    }
    if (mode === 'schedulerProbe') {
      this.runDebugProbe('schedulerProbe', DebugCaptureRunner.runSchedulerProbe(this.context));
      return;
    }
    if (mode === 'concurrencyProbe') {
      this.runDebugProbe('concurrencyProbe', DebugCaptureRunner.runConcurrencyProbe(this.context));
      return;
    }
    if (mode === 'legacyCleanupAudit') {
      DebugCaptureRunner.runLegacyCleanup(this.context, false).catch((e: Error) => {
        hilog.error(0xE2E0, 'E2E', '%{public}s', '历史数据审计异常: ' + e.message);
      });
      return;
    }
    if (mode === 'legacyCleanupApply') {
      DebugCaptureRunner.runLegacyCleanup(this.context, true).catch((e: Error) => {
        hilog.error(0xE2E0, 'E2E', '%{public}s', '历史数据清理异常: ' + e.message);
      });
      return;
    }
    if (mode === 'appIntentProbe') {
      this.runDebugProbe('appIntentProbe', DebugCaptureRunner.runAppIntentProbe(this.context));
      return;
    }
    if (mode === 'dedupeProbe') {
      this.runDebugProbe('dedupeProbe', DebugCaptureRunner.runDedupeProbe(this.context));
      return;
    }
    if (mode === 'latencyProbe') {
      this.runDebugProbe('latencyProbe', DebugCaptureRunner.runLatencyProbe(this.context));
      return;
    }
    if (mode === 'agentChatContext') {
      this.runDebugProbe('agentChatContext', DebugCaptureRunner.runAgentChatContext(this.context));
      return;
    }
    if (mode === 'noteAudit') {
      this.runDebugProbe('noteAudit', DebugCaptureRunner.runNoteAudit(this.context));
      return;
    }
    if (mode === 'agentImagePlan') {
      this.runDebugProbe('agentImagePlan', DebugCaptureRunner.runAgentImagePlan(this.context));
      return;
    }
    if (mode === 'agentTextPlan') {
      this.runDebugProbe('agentTextPlan', DebugCaptureRunner.runAgentTextPlan(this.context));
      return;
    }
    if (mode === 'agentTextBatch') {
      this.runDebugProbe('agentTextBatch', DebugCaptureRunner.runAgentTextBatch(this.context));
      return;
    }
    if (mode === 'captureSetS3') {
      this.runDebugProbe('captureSetS3', DebugCaptureRunner.runCaptureSetS3(this.context));
      return;
    }
    if (mode === 'captureSetIdem') {
      this.runDebugProbe('captureSetIdem', DebugCaptureRunner.runCaptureSetIdem(this.context));
      return;
    }
    if (mode === 'captureSetPreview') {
      this.runDebugProbe('captureSetPreview', DebugCaptureRunner.runCaptureSetPreview(this.context));
      return;
    }
    if (mode === 'captureSet5') {
      DebugCaptureRunner.runCaptureSet(this.context, true).catch((e: Error) => {
        hilog.error(0xE2E0, 'E2E', '%{public}s', 'captureSet(S5) 自检异常: ' + e.message);
      });
      return;
    }
    if (mode === 'captureSet') {
      this.runDebugProbe('captureSet', DebugCaptureRunner.runCaptureSet(this.context));
      return;
    }
    if (mode === 'draft') {
      DebugDraftRunner.run(this.context).catch((e: Error) => {
        hilog.error(0xE2E0, 'E2E', '%{public}s', 'HITL 自检异常: ' + e.message);
      });
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
      // 页面已就绪：这时候才有前台 UI 上下文去拉系统 Picker
      this.windowReady = true;
      this.consumeCardAction();
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
  /** 调试探针统一异常落日志（避免每个 mode 分支重复 .catch/hilog）。 */
  private runDebugProbe(mode: string, task: Promise<void>): void {
    task.catch((e: Error): void => {
      hilog.error(0xE2E0, 'E2E', '%{public}s', mode + ' 探针异常: ' + e.message);
    });
  }

  private async refreshCardSnapshot(): Promise<void> {
    await CardSnapshotService.refresh(this.context);
  }
}
