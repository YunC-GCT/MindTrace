/**
 * AgentExtAbility.ets - 端 A2A Agent 扩展入口（API 26 / AgentFrameworkKit）
 *
 * 路径: entry/src/main/ets/agentextability/AgentExtAbility.ets
 * 职责: 用 @kit.AgentFrameworkKit 的 createA2AServer 承载端A2A 协议：
 *       小艺消息 -> Server.onMessage -> onData 回调 -> addArtifact(文本 + uiExtensionCard)
 *       -> updateStatus(COMPLETED)
 * 依赖: @kit.AbilityKit、@kit.AgentFrameworkKit、@kit.PerformanceAnalysisKit
 *
 * 数据流:
 *   onData(proxy, data) -> server.onMessage(data, sender=proxy.sendData)
 *     -> onDataCallback(method, ctx) -> getUserInput() -> 组装 Part[]
 *     -> server.addArtifact(taskId, { parts, lastChunk: true })
 *     -> server.updateStatus(taskId, { state: COMPLETED })
 */
import { AgentExtensionAbility, common, Want } from '@kit.AbilityKit';
import {
  createA2AServer,
  Part,
  RequestContext,
  Server,
  TaskArtifactParam,
  TaskState,
  TaskStatus,
} from '@kit.AgentFrameworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'MindTraceA2A';
const DOMAIN: number = 0xA2A0;

interface CardPayload {
  title: string;
  description: string;
  query: string;
  action: string;
}

interface UiCardBody {
  bundleName: string;
  moduleName: string;
  abilityName: string;
  payload: CardPayload;
}

interface UiCardDirective {
  uiExtensionCard: UiCardBody;
}

export default class AgentExtAbility extends AgentExtensionAbility {
  private server: Server | null = null;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate: 扩展被拉起，初始化 A2A Server');
    try {
      this.server = createA2AServer(this.context.agentCard, (method: string, ctx: RequestContext): void => {
        this.handleRequest(method, ctx);
      }, want);
      this.server.start();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'createA2AServer 失败: %{public}s', (error as Error).message);
    }
  }

  onData(proxy: common.AgentHostProxy, data: string): void {
    hilog.info(DOMAIN, TAG, 'onData 收到 %{public}d 字节', data.length);
    if (this.server === null) {
      hilog.error(DOMAIN, TAG, 'server 未初始化，忽略本次请求');
      return;
    }
    try {
      this.server.onMessage(data, (payload: string): void => {
        hilog.info(DOMAIN, TAG, 'sendData %{public}d 字节', payload.length);
        proxy.sendData(payload);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'onMessage 失败: %{public}s', (error as Error).message);
    }
  }

  onDestroy(): void {
    if (this.server !== null) {
      this.server.stop();
      this.server = null;
    }
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  private handleRequest(method: string, ctx: RequestContext): void {
    const query: string = ctx.getUserInput();
    const taskId: string | undefined = ctx.getTaskId();
    hilog.info(DOMAIN, TAG, 'method=%{public}s taskId=%{public}s query=%{public}s',
      method, taskId ?? 'none', query);

    const textPart: Part = {
      text: '已打开整理入口：请在浮窗里选图，最多 20 张。',
      mediaType: 'text/plain',
    };

    const payload: CardPayload = {
      title: '整理数学题',
      description: '从相册选择题目图片，自动生成笔记',
      query: query,
      action: 'batch_capture',
    };
    // A2A v1 用字段名做判别器：data.uiExtensionCard.payload
    const directive: UiCardDirective = {
      uiExtensionCard: {
        bundleName: 'com.example.mindtrace',
        moduleName: 'entry',
        abilityName: 'AgentUIExtAbility',
        payload: payload,
      },
    };
    const cardPart: Part = {
      mediaType: 'application/json',
      data: directive,
    };

    // 卡片 part 暂不发送：小艺会为它死循环重试 start_ability_fail，导致对话一直转圈
    const artifact: TaskArtifactParam = {
      parts: [textPart],
      lastChunk: true,
    };

    try {
      if (taskId !== undefined) {
        this.server?.addArtifact(taskId, artifact);
        const status: TaskStatus = { state: TaskState.COMPLETED };
        this.server?.updateStatus(taskId, status);
        hilog.info(DOMAIN, TAG, 'artifact sent, task completed');
      } else {
        hilog.warn(DOMAIN, TAG, 'taskId 为空，跳过 artifact');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, '发送 artifact 失败: %{public}s', (error as Error).message);
    }
  }
}
