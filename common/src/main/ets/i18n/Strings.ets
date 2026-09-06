// MindTrace - 评审前打磨用 i18n 字符串首例 (fix/demo-polish-2026-09-06)
// 评审 demo 前抽取的最常用 10 条 toast 文案 + 5 条英文重命名。
//
// 约束 (后续扩到多语言时保持):
//   1. 短消息 4-10 字为佳, 最长 14 字 (含标点)
//   2. 失败: [动作]+失败 / 成功: 已[动作] / 进行中: [动作]+中...
//   3. 不带末尾冒号 / 句号 (与中文 Toast 习惯一致)
//   4. 后续加 en/ 目录时, 抽出统一方法 load(key, lang?), 当前硬编码中文即 base
//
// 后续 todo:
//   - 真正多语言: 用 $r('app.string.*') + ResourceManager 替换硬编码
//   - 错误分级: 与 frontend-error-handling-2026-09-06 §6 ErrorBus 配合
//   - 文案风格 guide: 与 frontend-i18n-audit-2026-09-06 §4 对齐

export class Toast {
  // ---- 成功模板 (已[动作]) ----
  static readonly NOTE_DELETED: string = '已删除笔记';
  static readonly PLAN_DELETED: string = '已删除计划';
  static readonly ENQUEUED_REALTIME: string = '已加入实时队列';
  static readonly MOVED_TO_REVIEW: string = '已移回复习队列';
  static readonly MOVED_TO_REALTIME_TOP: string = '已移至实时队列顶部';

  // ---- 失败模板 ([动作]+失败) ----
  static readonly NOTE_LOAD_FAILED: string = '笔记加载失败';
  static readonly NOTE_DELETE_FAILED: string = '笔记删除失败';
  static readonly NOTE_SAVE_FAILED: string = '保存失败';
  static readonly NOTE_CREATE_OK: string = '笔记已新建';
  static readonly NOTE_UPDATE_OK: string = '笔记已保存';
  static readonly PLAN_LOAD_FAILED: string = '复习数据加载失败';
  static readonly PLAN_DELETE_FAILED: string = '计划删除失败';
  static readonly PLAN_RESET_FAILED: string = '重置失败';
  static readonly PLAN_SAVE_FAILED: string = '保存失败';
  static readonly PLAN_SAVE_OK: string = '已保存';
  static readonly GALAXY_LOAD_FAILED: string = '知识星系加载失败';
  static readonly CONFIG_LOAD_FAILED: string = '配置加载失败';

  // ---- 校验模板 ----
  static readonly API_KEY_REQUIRED: string = '请先输入 API Key';
  static readonly PLAN_INPUT_REQUIRED: string = '请输入复习计划';
  static readonly TITLE_REQUIRED: string = '请输入标题';
  static readonly NOTE_STILL_LOADING: string = '笔记仍在加载';
  static readonly SUMMARY_OR_CONTENT_REQUIRED: string = '摘要和正文至少填写一项';

  // ---- 过程模板 ([动作]+中...) ----
  static readonly AI_REPLYING: string = 'AI 正在回复中...';

  // ---- feature flag ----
  static readonly SHARE_NOT_OPEN: string = '分享功能暂未开放';

  // ---- save 失败 (动态拼字段) ----
  static saveFailed(detail: string): string {
    return '保存失败' + (detail.length > 0 ? '：' + detail : '');
  }
}
