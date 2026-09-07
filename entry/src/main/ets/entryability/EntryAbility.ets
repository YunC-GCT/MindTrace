// ============================================================================
//  entryability/EntryAbility.ets — 应用入口
//  ----------------------------------------------------------------------------
//  职责: 初始化 LLM 配置 + 数据库 + 沉浸式状态栏 + 加载首页。
//  沉浸式状态栏: app 内容延伸到 status bar 下方, status bar 背景透明。
//  视觉效果: 系统时间/电量/信号/wifi 浮在 app 内容上, 与 app 无缝衔接。
//  ============================================================================

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LlmConfig, OcrConfig, DatabaseHelper } from 'common';
import { ReminderFacadeImpl } from '../kit/ReminderFacadeImpl';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 初始化 LLM 配置(持久化 API key/endpoint/model)
    LlmConfig.getInstance().init(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'LlmConfig init failed: %{public}s', e.message);
    });
    // 初始化 OCR 配置(持久化 endpoint/enabled)
    OcrConfig.getInstance().init(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'OcrConfig init failed: %{public}s', e.message);
    });
    // 初始化数据库
    DatabaseHelper.init(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, 'testTag', 'DB init failed: %{public}s', e.message);
    });
    // F3 最小闭环 (spec 013 / ADR-0009): ReminderFacade 实现在组合根构造并注入
    AppStorage.setOrCreate<ReminderFacadeImpl>('reminderFacade', new ReminderFacadeImpl(this.context));
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
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
    });
  }

  onWindowStageDestroy(): void { hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy'); }
  onForeground(): void { hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground'); }
  onBackground(): void { hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground'); }
}
