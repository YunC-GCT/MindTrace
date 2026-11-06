/**
 * RagSpotCases.ets — 泛化抽查集（纯数据，无 IO）
 *
 * 路径: entry/src/main/ets/debug/RagSpotCases.ets
 * 职责: 与 RagEvalCases 分开的「样本外」查询：这些问法没有参与任何阈值/权重调优，
 *       用来检验检索效果是不是只对调过的那 22 条成立。
 * 依赖: 无。
 *
 * 约束: 标题必须与 TestCorpusSeed 一致；问法避免直接复用笔记标题里的词。
 *       一旦某条被观察到结果，它就「出样本」了——下次泛化再验需要换新的。
 */
export interface RagSpotCase {
  query: string;
  expectTitle: string;
}

export const RAG_SPOT_CASES: RagSpotCase[] = [
  { query: '积分的上下限是无穷大怎么办', expectTitle: '反常积分的敛散性' },
  { query: '波动大小用什么衡量', expectTitle: '期望与方差的性质' },
  { query: '两件事同时发生的概率怎么算', expectTitle: '条件概率与乘法公式' },
  { query: '解方程时那个积分因子是怎么想出来的', expectTitle: '一阶线性微分方程' },
  { query: '一组向量里有没有多余的', expectTitle: '向量组的线性相关性' },
  { query: '一个式子是不是恒大于零', expectTitle: '二次型的正定性' },
  { query: '多元函数能不能用平面来近似', expectTitle: '多元函数偏导数与全微分' },
  { query: '无穷多个点加起来还能算面积吗', expectTitle: 'Riemann 积分的可积条件' },
  { query: '矩阵转置以后秩会变吗', expectTitle: '矩阵的秩与初等变换' },
  { query: '阶数很高的行列式怎么算才快', expectTitle: '行列式按行展开' },
];
