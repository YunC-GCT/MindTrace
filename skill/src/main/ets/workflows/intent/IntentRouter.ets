import { Want } from '@kit.AbilityKit';
import { SkillIntentRequest } from './SkillIntentState';

const SEARCH_NOTE_ACTION: string = 'ohos.intent.action.SearchNote';

export class IntentRouter {
  fromWant(want: Want): SkillIntentRequest {
    const action: string = want.action ?? '';
    if (action !== SEARCH_NOTE_ACTION) {
      const unsupported: SkillIntentRequest = {
        action: action,
        target: 'unsupported',
        argsJson: '{}',
      };
      return unsupported;
    }
    const args: Record<string, Object> = {};
    const params: Record<string, Object> | undefined = want.parameters;
    if (params !== undefined) {
      const keyword: Object | undefined = params['keyword'];
      const subject: Object | undefined = params['subject'];
      const reviewStatus: Object | undefined = params['reviewStatus'];
      if (typeof keyword === 'string' && keyword.trim().length > 0) {
        args['keyword'] = keyword.trim();
      }
      if (typeof subject === 'string' && subject.trim().length > 0) {
        args['subject'] = subject.trim();
      }
      if (typeof reviewStatus === 'string' && reviewStatus.trim().length > 0) {
        args['review_status'] = reviewStatus.trim();
      }
    }
    const request: SkillIntentRequest = {
      action: action,
      target: 'search_note',
      argsJson: JSON.stringify(args),
    };
    return request;
  }
}
