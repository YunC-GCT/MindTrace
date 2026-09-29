export type SkillIntentTarget = 'search_note' | 'unsupported';
export type SkillIntentStep = 'START' | 'route_action' | 'execute_search' | 'unsupported' | 'END';

export interface SkillIntentRequest {
  action: string;
  target: SkillIntentTarget;
  argsJson: string;
}

export interface SkillIntentResult {
  ok: boolean;
  content: string;
  errorKind?: 'UNSUPPORTED_INTENT' | 'TOOL_ERROR';
}

export interface SkillIntentState {
  request: SkillIntentRequest;
  currentStep: SkillIntentStep;
  result?: SkillIntentResult;
}
