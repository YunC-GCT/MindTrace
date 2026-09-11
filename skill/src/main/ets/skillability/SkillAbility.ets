import { AbilityConstant, common, UIAbility, Want } from '@kit.AbilityKit';
import { DatabaseHelper, ToolCatalog, ToolRegistry } from 'common';
import { IntentRouter } from '../workflows/intent/IntentRouter';
import { SkillIntentWorkflow } from '../workflows/intent/SkillIntentWorkflow';
import { SkillIntentRequest, SkillIntentResult } from '../workflows/intent/SkillIntentState';

export default class SkillAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.handleWant(want).catch((e: Error): void => {
      console.warn('[SkillAbility.onCreate] ' + e.message);
    });
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.handleWant(want).catch((e: Error): void => {
      console.warn('[SkillAbility.onNewWant] ' + e.message);
    });
  }

  private async handleWant(want: Want): Promise<void> {
    const request: SkillIntentRequest = new IntentRouter().fromWant(want);
    let result: SkillIntentResult;
    try {
      if (request.target === 'search_note') {
        await DatabaseHelper.init(this.context);
      }
      const registry: ToolRegistry = ToolCatalog.createReadOnlyRegistry();
      result = await new SkillIntentWorkflow(registry).run(request);
    } catch (e) {
      result = {
        ok: false,
        content: e instanceof Error ? e.message : String(e),
        errorKind: 'TOOL_ERROR',
      };
    }
    const parameters: Record<string, Object> = {};
    parameters['ok'] = result.ok;
    parameters['content'] = result.content;
    parameters['errorKind'] = result.errorKind ?? '';
    const resultWant: Want = new Want();
    resultWant.parameters = parameters;
    const abilityResult: common.AbilityResult = {
      resultCode: result.ok ? 0 : -1,
      want: resultWant,
    };
    await this.context.terminateSelfWithResult(abilityResult);
  }
}
