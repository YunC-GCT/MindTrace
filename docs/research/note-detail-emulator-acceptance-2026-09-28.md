# NoteDetail 模拟器性能与 WebKeepAlive A/B 证据

> 本文记录 #189 与 #188 在无真机条件下的最大可执行验收。它是模拟器证据，不是目标设备性能达标证明。

## 结论

- **WebKeepAlive 保持默认关闭。** 同一模拟器、同一 fixture 的开/关 A/B 没有显示稳定的首屏、公式可见或稳定时间收益；AI 助手显示时，KeepAlive 开启组的 warm run 反而在 4 秒窗口内没有公式可见事件。
- **#188 未通过，且仍受 #187 阻塞。** C 公式密集场景多次未在 4 秒窗口内达到公式可见或 500ms 稳定；C′ 连续公式场景出现裸 `$$...$$` 文本。该结果与 #187 尚未完成公式 Web 预算和缓存迁移一致。
- 普通无公式 NoteDetail 的 warm reopen 首屏较快，但不能外推到公式路径或真机。

## 环境与方法

| 项 | 值 |
|---|---|
| 设备 | DevEco 模拟器 `emulator` |
| 系统 | OpenHarmony 6.1.1.125，API 24，x86_64 |
| 分辨率 | 2880 × 1920 |
| 应用 | `com.example.mathmind` debug HAP |
| 启动 | `EntryAbility` 显式 `mindtrace://note-detail-benchmark/...` URI；普通启动默认关闭 benchmark 与 KeepAlive |
| 单次进程内序列 | cold open 4s → close 1s → warm reopen 4s → close |
| 指标来源 | `NoteDetailRenderMetrics` hilog；进程 PSS 来自 `hidumper --mem <pid> --prune` |

fixture、AI 助手和 KeepAlive 标签由启动 URI 固定。KeepAlive 只在 `Index` 根部挂载，cold 与 warm 两次 NoteDetail 的关闭/重开不会重建根部 KeepAlive。

模拟器 shell 无权终止应用 renderer 子进程，强杀尝试未改变 PID，也未产生 `onRenderExited`；因此有限恢复只有纯逻辑和构建证据，没有设备行为结论。外部帧采样器未接入本轮模拟器命令行，`longFrameCount` 与 `maxWebCreatesPerFrame` 的零值不得解读为无长帧或满足单帧预算。应用内 heap 字段同样未注入，内存比较只采用外部 PSS。

## WebKeepAlive A/B

以下是稳定探测修复后的代表性运行；同一进程内 cold/warm 各一次。`—` 表示运行窗口内未观察到该事件。模拟器抖动明显，样本只用于否决默认启用，数量不足以计算 p50/p95。PSS 来自相同矩阵中独立的 2 秒 active / 两轮关闭后采样。

| Fixture | AI | KeepAlive | Cold first / formula / stable (ms) | Warm first / formula / stable (ms) | Active PSS (kB) | Closed PSS (kB) |
|---|---:|---:|---:|---:|---:|---:|
| C long | off | off | 121 / 2653 / — | 510 / 2733 / — | 182135 | 224686 |
| C long | off | on | 205 / 2711 / 4519 | 222 / 2646 / — | 191190 | 212560 |
| C long | on | off | 553 / — / — | 104 / — / — | 192466 | 224914 |
| C long | on | on | 324 / — / — | 304 / — / 4295 | 183061 | 217010 |
| C′ long | off | off | 116 / 2326 / 4095 | 33 / 579 / 4063 | 194525 | 219245 |
| C′ long | off | on | 253 / 3213 / 4051 | 32 / 538 / 4011 | 191183 | 205636 |

每次 NoteDetail 打开仍创建相同数量的业务 Web：C 为 6，C′ 的证明题 surface 为 1。关闭后进程列表中，KeepAlive off 观察到 1 个 `com.example.mathmind:render`，KeepAlive on 观察到 2 个；PSS 波动没有形成可重复的可接受成本结论。由于收益不明确，实验不进入默认产品路径。

## 公式密集与 renderer smoke

| 场景 | Cold first / formula / stable (ms) | Warm first / formula / stable (ms) | Web creates |
|---|---:|---:|---:|
| A short · 概念 | 75 / N/A / 未重采 | 29 / N/A / 未重采 | 0 |
| A long · 定理 | 85 / N/A / 未重采 | 29 / N/A / 未重采 | 0 |
| A long · 计算题 | 76 / N/A / 未重采 | 7 / N/A / 未重采 | 0 |
| A short · 兜底 | 108 / N/A / 未重采 | 28 / N/A / 未重采 | 0 |
| B long · 公式 | 89 / 2434 / 未重采 | 24 / 494 / 未重采 | 2 |
| C short · 公式 | cold 日志被 Web 日志覆盖 | 29 / 1296 / — | 6 |
| C′ long · 证明题 | 126 / 1927 / 4081 | 30 / 313 / 4042 | 1 |

六类 renderer 均通过真实 NoteDetailOverlay 启动 smoke（概念、定理、公式、证明题、计算题、兜底），但公式正确性没有通过：C′ 冷开约 3 秒的截图中，首个公式已渲染，后续连续公式仍显示原始分隔符。

早期 harness 只在 overlay 卸载时调用稳定判定，导致约 4 秒的关闭时间被误记成 stable。该观测缺口已修为运行期间每 100ms 探测；上表没有保留 A/B/普通 renderer 的旧 stable 数值，C/C′ 行使用修复后的日志。

![C′ 连续公式模拟器截图](./note-detail-c-prime-emulator-2026-09-28.jpeg)

## 验收边界与后续门禁

- #189 的当前决策是“否决默认启用”，不是“真机证明无收益”。未来只有在目标设备重复 A/B 显示明确收益且驻留内存可接受时，才能重新讨论开启。
- #188 不能关闭：#187 仍为 OPEN，旧 defer/visible-stage/queue 收口不属于 A 组所有权；模拟器也不能替代真机的 20 次矩阵、p50/p95、长帧和内存门禁。
- 本轮证据允许审查基础设施、默认关闭行为和模拟器失败事实，不允许声明用户可见性能已经达标。
