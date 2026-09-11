/**
 * ToolCatalog.ets — 只读工具目录组装
 *
 * 路径: common/src/main/ets/tools/ToolCatalog.ets
 * 职责: 拼装 ToolRegistry 并注册一组只读 AgentTool,作为工具面唯一目录
 * 依赖: ./NoteQueryTools createReadOnlyNoteTools; ./ToolRegistry AgentTool/ToolRegistry
 *
 * 数据流:
 *   NoteGenerationWorkflow → ToolCatalog.createReadOnlyRegistry → ToolRegistry.register
 *
 * ArkTS 1.1 strict 适配:
 *   - 工厂方法而非构造器,便于 ArkTS Hypium seam 测试注入
 *   - 仅提供只读工具,避免写工具在当前迭代中泄漏
 */
import { createReadOnlyNoteTools } from './NoteQueryTools';
import { AgentTool, ToolRegistry } from './ToolRegistry';

export class ToolCatalog {
  static createReadOnlyRegistry(): ToolRegistry {
    const registry: ToolRegistry = new ToolRegistry();
    const tools: AgentTool[] = createReadOnlyNoteTools();
    for (const tool of tools) {
      registry.register(tool);
    }
    return registry;
  }
}
