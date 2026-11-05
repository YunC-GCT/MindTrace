/**
 * RagEvalCases.ets — RAG 召回评测集（纯数据，无 IO）
 *
 * 路径: entry/src/main/ets/debug/RagEvalCases.ets
 * 职责: 044 R5 的固定查询集：每条给出用户问法与期望命中的笔记标题，
 *       expectTitle 为空表示负样本（不应命中任何笔记）。
 * 依赖: 无。
 *
 * 约束: 标题优先使用 galaxy 预置笔记（跨安装稳定）；依赖运行期测试笔记的用例
 *       由探针先查库确认存在，不存在则跳过而不是记为 miss。
 */
export interface RagEvalCase {
  query: string;
  expectTitle: string;
}

export const RAG_EVAL_CASES: RagEvalCase[] = [
  { query: '什么是导数', expectTitle: '导数定义与几何意义' },
  { query: '函数在一点连续是什么意思', expectTitle: '函数在一点连续的定义' },
  { query: '极限的运算法则', expectTitle: '极限四则运算法则' },
  { query: '拉格朗日中值定理', expectTitle: '拉格朗日中值定理' },
  { query: '数列极限的定义', expectTitle: '数列与函数极限定义' },
  { query: '连续性的局部性质', expectTitle: '连续性的局部性质' },
  { query: '泰勒公式余项估计', expectTitle: '泰勒公式余项估计' },
  { query: '矩阵的秩和初等变换', expectTitle: '矩阵秩与初等变换' },
  { query: '行列式按行展开', expectTitle: '行列式按行展开' },
  { query: '可逆矩阵判定', expectTitle: '可逆矩阵判定' },
  { query: '向量组线性相关', expectTitle: '向量组线性相关' },
  { query: '一加一等于几', expectTitle: '一加一等于二' },
  { query: '9+9 的加法计算怎么算', expectTitle: '9+9 的加法计算' },
  { query: '今天天气怎么样', expectTitle: '' },
];
