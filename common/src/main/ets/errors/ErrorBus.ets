// MindTrace - ErrorBus 全局错误发布订阅 (评审前 1.5 项 / fix/demo-polish-2026-09-06)
//
// 设计: 业务层 new AppError(...) 然后 ErrorBus.publish(err);
//       UI 顶层 (Index.ets 挂 ErrorBanner) 订阅后自动展示;
//       顶层 toast (已有) 与 ErrorBanner 并存, 互相不冲突:
//         - toast: 短消息 (1-2s) 操作反馈 (成功 + 轻错误)
//         - ErrorBanner: 长错误 (网络断开 / API key 失效) 含建议/重试
//
// 生命周期:
//   - 订阅在 aboutToAppear 建立, aboutToDisappear 释放 (无泄漏)
//   - publish 默认不持久化, 进程级 (与 AppStorage notesVersion 同质)
//
// 并发:
//   - subscribe 返回 unsubscribe 函数, 不用手动管理数组
//   - 多订阅者按订阅顺序触发, 不依赖回调先后

export type ErrorListener = (err: import('./AppError').AppError) => void;

export class ErrorBus {
  private static listeners: ErrorListener[] = [];

  static subscribe(listener: ErrorListener): () => void {
    ErrorBus.listeners.push(listener);
    return (): void => {
      const index: number = ErrorBus.listeners.indexOf(listener);
      if (index >= 0) {
        ErrorBus.listeners.splice(index, 1);
      }
    };
  }

  static publish(err: import('./AppError').AppError): void {
    // 不在 publish 里 try/catch — 让订阅者自己处理
    for (const listener of ErrorBus.listeners) {
      listener(err);
    }
  }

  // 测试/调试用: 清空所有订阅
  static clear(): void {
    ErrorBus.listeners = [];
  }
}
