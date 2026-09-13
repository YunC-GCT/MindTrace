# 推理模型设置交接 — Qwen3.5 / DeepSeek

## 结论

前端只有在 SSE 中收到 `reasoning_content`，并将其转换为 `thinking` 事件时，才会显示思考区。模型名称、推理开关和推理强度必须按供应商协议发送，不能用一套请求字段覆盖所有模型。

## 设置矩阵

| 模型/部署 | 思考开关 | 推理强度 | 请求字段 | 解析字段 | 前端预期 |
|---|---|---|---|---|---|
| Qwen3.5 混合思考 | `enable_thinking: true` | 由模型/服务端决定，当前不额外发送强度字段 | 顶层 `enable_thinking`；不要发送 DeepSeek 的 `thinking`、`reasoning_effort` | `delta.reasoning_content` | 先显示“思考中…”，再显示正文 |
| Qwen3.5 仅思考模型 | 不发送关闭字段；若接口要求则使用 `enable_thinking: true` | 服务端固定 | 以实际 endpoint 文档为准 | `delta.reasoning_content` | 必须先有思考区，再有正文 |
| DeepSeek-v4-pro / DeepSeek-Flash | `thinking.type: enabled` | `reasoning_effort: high`；需要更强推理时用 `max` | `thinking` + `reasoning_effort`；思考模式不发送 `temperature` | `delta.reasoning_content` | 思考区持续追加并自动跟随底部，完成后显示“已深度思考” |
| DeepSeek 非思考模式 | `thinking.type: disabled` 或 `reasoning_effort: none` | `none` | 不显示推理区是正常结果 | `delta.content` | 直接显示正文 |
| GLM / Kimi / Doubao / 自定义 endpoint | 不统一 | 不统一 | 必须先按对应 endpoint 文档配置能力；当前代码不能保证推理供给 | 通常需确认是否为 `reasoning_content` | 未确认前不能承诺思考区出现 |

## 当前代码约束

- `common/src/main/ets/llm/LlmClient.ets`：Qwen 走顶层 `enable_thinking`；非 Qwen 当前走 DeepSeek 兼容字段，因此切换到其他厂商前必须补能力映射。
- `common/src/main/ets/llm/LlmClient.ets`：只将 `reasoning_content` 转换为 `thinking`，只将 `content` 转换为 `text`，不能把思考内容伪装成正文。
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets`：`thinking` 累积到 `ChatMsg.reasoning`，`text` 累积到 `ChatMsg.content`。
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets`：思考区默认折叠；展开后必须自动滚动到最新文本。

## 本次复现判断

- Qwen3.5：之前请求字段不符合百炼 OpenAI 兼容接口，已改为顶层 `enable_thinking`；仍需通过事件计数确认服务端是否实际返回 `reasoning_content`。
- DeepSeek：已经出现思考气泡，说明推理供给和字段解析基本打通；“死的”问题位于思考文本增长后的局部滚动/刷新，不应通过重新打开面板解决。
- 若日志显示 `thinkingChars` 持续增加而界面不动，归因于前端滚动；若 `thinkingChars=0`，归因于模型请求配置或 endpoint 能力。

## 测试顺序

1. 切换 DeepSeek-v4-pro，保持思考开启，提问数学推理题。
2. 思考区展开后观察文本是否持续追加并自动跟随底部；不要手动滑动列表。
3. 记录日志中的 `thinkingEvents`、`thinkingChars`、`textEvents`、`textChars`。
4. 再切换 Qwen3.5，使用同一问题，对比是否出现 `thinkingChars`。
5. 只有 `thinkingChars > 0` 时，才继续判断 UI；否则先修供应商请求参数，不修改前端渲染逻辑。

## 官方依据

- [DeepSeek Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode)
- [DeepSeek Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion)
- [百炼深度思考模型用法](https://help.aliyun.com/zh/model-studio/deep-thinking)
