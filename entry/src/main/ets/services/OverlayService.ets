/**
 * OverlayService.ets — 浮层统一调度器
 *
 * 路径: entry/src/main/ets/services/OverlayService.ets
 * 职责: 管理 AgentFloatWindow 等全局浮层的互斥开关
 *       通过 AppStorage 桥接 ArkUI 渲染
 *
 * 参考: v2-ui 的 OM (OverlayManager) — 多通道浮层统一调度
 *
 * 使用:
 *   const overlays = new OverlayService();
 *   overlays.open('float');    // 开 AI 浮窗
 *   overlays.close();          // 关当前浮层
 */

const KEY: string = 'activeOverlay';

export class OverlayService {
  // 打开指定浮层(自动关闭互斥浮层)
  open(id: string): void {
    AppStorage.setOrCreate(KEY, id);
  }

  // 关闭当前浮层
  close(): void {
    AppStorage.setOrCreate(KEY, '');
  }

  // 当前打开的是否为指定浮层
  isActive(id: string): boolean {
    const cur: string = AppStorage.get<string>(KEY) ?? '';
    return cur === id;
  }
}
