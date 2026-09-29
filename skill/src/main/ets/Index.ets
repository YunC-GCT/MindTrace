// skill HAP - public API 入口
// W1 块 3 之后实装:共享给 callers 的 helper 函数

export const SKILL_VERSION = 'v0.0.1';
export { IntentRouter } from './workflows/intent/IntentRouter';
export { SkillIntentWorkflow } from './workflows/intent/SkillIntentWorkflow';
export type {
  SkillIntentRequest,
  SkillIntentResult,
  SkillIntentState,
  SkillIntentStep,
  SkillIntentTarget,
} from './workflows/intent/SkillIntentState';
