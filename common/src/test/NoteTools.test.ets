// NoteTools.test.ets — P1 只读工具行为测试 (spec 014 §4, Hypium, on-device)
// 前提: common 单测环境不 init RDB → DatabaseHelper.getStore() 为 null → 工具走 'store not ready' 分支
import { describe, it, expect } from '@ohos/hypium';
import { ToolRegistry, createReadOnlyNoteTools } from '../main/ets/Index';
import type { AgentTool, ToolResult } from '../main/ets/Index';

function registeredRegistry(): ToolRegistry {
  const registry: ToolRegistry = new ToolRegistry();
  const tools: AgentTool[] = createReadOnlyNoteTools();
  const limit: number = tools.length;
  let i: number = 0;
  while (i < limit) {
    registry.register(tools[i]);
    i++;
  }
  return registry;
}

export default function noteToolsTest(): void {
  describe('NoteTools.spec014_p1_test', () => {
    it('factory_registers_three_readonly_tools_with_wire_names', 0, async () => {
      const registry: ToolRegistry = registeredRegistry();
      const defs = registry.listDefinitions();
      expect(defs.length).assertEqual(3);
      expect(defs[0].function.name).assertEqual('note_query');
      expect(defs[1].function.name).assertEqual('note_get');
      expect(defs[2].function.name).assertEqual('review_due_query');
    });

    it('tools_report_store_not_ready_without_init', 0, async () => {
      const registry: ToolRegistry = registeredRegistry();
      const r1: ToolResult = await registry.execute('note_query', '{}');
      expect(r1.ok).assertFalse();
      expect(r1.content).assertEqual('store not ready');
      const r2: ToolResult = await registry.execute('note_get', '{"id":"x"}');
      expect(r2.ok).assertFalse();
      expect(r2.content).assertEqual('store not ready');
      const r3: ToolResult = await registry.execute('review_due_query', '{}');
      expect(r3.ok).assertFalse();
      expect(r3.content).assertEqual('store not ready');
    });

    it('rejects_invalid_review_status_before_touching_store', 0, async () => {
      const registry: ToolRegistry = registeredRegistry();
      const r: ToolResult = await registry.execute('note_query', '{"review_status":"bogus"}');
      expect(r.ok).assertFalse();
      expect(r.content).assertContain('review_status must be one of');
    });

    it('note_get_requires_id', 0, async () => {
      const registry: ToolRegistry = registeredRegistry();
      const r: ToolResult = await registry.execute('note_get', '{}');
      expect(r.ok).assertFalse();
      expect(r.content).assertEqual('note_get requires id');
    });
  });
}
