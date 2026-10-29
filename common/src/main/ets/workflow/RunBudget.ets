/**
 * RunBudget.ets — 一次 run 内父图与子图共享的节点执行预算。
 *
 * 路径: common/src/main/ets/workflow/RunBudget.ets
 * 职责: 只回答「还有没有余额」并消耗一次；不抛错、不读时钟、不 import 任何 Kit。
 * 依赖: 无（纯数值契约，Node 侧 loader 可直接装载做契约测试）。
 *
 * 数据流:
 *   StateGraph.run（步骤 2 接线）→ RunBudget.take() → 返回值决定是否抛 MAX_NODE_RUNS
 *   RunContext（父）→ createChildRunContext → 同一个 RunBudget 实例（父子累计）
 *
 * 与 issue #243 的偏差（本切片唯一的形状偏差）及原因:
 *   issue §1 写的是 `export interface RunBudget { readonly limit; readonly used; ... }`，
 *   但 `used` 必须在 `take()` 里自增；interface 无法表达「对外只读、对内可变」。
 *   这里落地为 class：内部 `usedCount` 私有自增，对外只暴露 getter `used`（只读视图）。
 *
 * 语义边界:
 *   - limit < 0 归一为 0；limit 不是有限数（NaN / ±Infinity）同样按 0 处理。
 *   - take() 从不抛异常：预算对象只回答「还有没有」，抛不抛由调用方（StateGraph）决定。
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式字段 + 构造器赋值，不用构造器参数属性简写。
 *   - getter 只做只读视图；项目的 no-get-accessor 规则只约束 @Component struct。
 */

// 归一化预算上限：负值与 NaN / Infinity 都不能让 hasRemaining() 永远为 true。
function normalizeLimit(limit: number): number {
  if (!Number.isFinite(limit)) {
    return 0;
  }
  if (limit < 0) {
    return 0;
  }
  return limit;
}

export class RunBudget {
  readonly limit: number;
  // 唯一的计数源；自增只发生在 take() 里。
  private usedCount: number = 0;

  constructor(limit: number) {
    this.limit = normalizeLimit(limit);
  }

  // 对外只读视图：外部只能读，不能写。
  get used(): number {
    return this.usedCount;
  }

  hasRemaining(): boolean {
    return this.usedCount < this.limit;
  }

  take(): boolean {
    if (!this.hasRemaining()) {
      return false;
    }
    this.usedCount += 1;
    return true;
  }
}

export function createRunBudget(limit: number): RunBudget {
  return new RunBudget(limit);
}
