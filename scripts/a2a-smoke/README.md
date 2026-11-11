# a2a-smoke — 端A2A 真机冒烟

一条命令验证「小艺 → `AgentExtensionAbility` → 回复」整条链路，不需要人手点手机。

## 用法

```bash
python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"
python scripts/a2a-smoke/a2a_smoke.py --agent "其它智能体名" --tag 其它TAG --no-restart
# 草稿确认：先发内容看预览，再回「确认」保存（两条命令在同一会话里）
python scripts/a2a-smoke/a2a_smoke.py --manual --text "存笔记：柯西中值定理的证明思路"
python scripts/a2a-smoke/a2a_smoke.py --manual --text "确认"
# 连发 N 条采延迟样本（定默认模型前攒 20 条）
python scripts/a2a-smoke/latency_series.py --n 20 --text "整理数学题" --out samples.jsonl
```

## 端A2A 流式探针

验证小艺客户端是否渲染 `artifactUpdate` 多帧（固定 5 段、每段 700ms）：

1. 安装含 `capabilities.streaming=true` 的 HAP
2. 在小艺开放平台重新导入 AgentCard，重启小艺
3. 发送：

```bash
python scripts/a2a-smoke/a2a_smoke.py --manual --text "流式探针"
```

4. 观察小艺气泡是否逐段更新；同时看日志：

```bash
hdc shell "hilog -x | grep -E 'A2A_STREAM_PROBE|A2A_STREAM_FRAME'"
```

预期帧序列：`start` → 5 个 `chunk`（最后一个 `last`）→ `end`。如果只显示第一段/最后一段或什么都不显示，说明客户端不支持增量渲染。

输出 JSON：

| 字段 | 含义 |
|---|---|
| `ok` | 是否拿到回复（退出码 0 / 1 / 2 同义：成功 / 发了没回 / 环境问题） |
| `reply_text` | 智能体气泡正文（最长的新增文本） |
| `foreground` | 操作时前台包名。旧版小艺是 `com.huawei.hmos.vassistant`；新版由桌面承载，可能是 `com.ohos.sceneboard`（脚本会按布局里的「小艺」标题 / 输入框判定就绪） |
| `hilog` | `MindTraceA2A` 生命周期（`onCreate` / `onConnect` / `onData` / `sendData`） |

## 前置条件

1. 手机已连接（`hdc list targets` 有设备）
2. **手机已解锁**——`uitest` 的点击在锁屏上无效，脚本无法越过（脚本会把息屏时间临时调到 30 分钟）
3. 应用已安装最新 HAP；**每次重装后脚本会自动重启小艺**（旧连接不释放会导致日志里连 `onCreate` 都没有）
4. 平台已为该账号发过真机测试

## 它会做什么

```
亮屏 → 延长息屏 → force-stop 小艺 → aa start（失败则点桌面图标）
→ 布局判定小艺就绪（bundle 或「小艺」标题 / TextArea）
→ 找智能体卡片/侧栏条目 → 等输入框出现 → 输入 → 点发送
→ 轮询 dumpLayout 做文本差集 → 抓 hilog
```

## 已知坑（脚本已处理）

| 坑 | 处理 |
|---|---|
| `SCBScreenLock` 窗口常驻，误判锁屏 | 改看 `dumpLayout` 根节点 bundleName |
| `aa start` 只起进程不起界面 | 兜底点桌面图标，取**面积最小**的可点祖先 |
| 侧栏滑动手势不稳定 | 改点左上角菜单按钮 |
| 回复里混入侧栏/历史文本 | 基准快照在进入会话之后取，`reply_text` 取最长新增项 |
| `aa start` 报 success 但小艺没到前台，且 `dumpLayout` 根节点常常取不到 bundleName → `launch()` 误判失败 | `latency_series.py` 不判断前台包名，直接看「智能体名是否出现在文本里」，取不到就回桌面点图标（`ICON_XY`，换设备要重取） |
| 新版小艺由桌面（`com.ohos.sceneboard`）承载，包名永远不是小艺 | `is_xiaoyi_foreground()` 改看布局特征：精确的「小艺」标题或会话 `TextArea` |
| 新版入口是卡片网格，旧脚本点「左上角菜单」可能误点第一张卡片 | 检测到 `Grid` / `GridItem` 时只翻页，不点抽屉；`open_agent()` 等到 `TextArea` 出现才返回 |
| 反复发同一句会撞到 `chat answer validation failed ... JSON object extraction failed` | 该条 `llm_ms` 为 `null`，采样脚本单独计数（算失败样本，不进延迟统计），失败率本身就是要看的指标 |

## 协议事实（改代码前先看）

- 小艺发 `method: "SendStreamingMessage"`，`params.message.parts[]` 只有 `{ mediaType, text }`，**没有** `kind` / `type`
- 响应走 proto-JSON：`role: "ROLE_AGENT"`、`state: "TASK_STATE_COMPLETED"`
- **能渲染的最小响应是单条 `task` 快照**（`result.task` + `artifacts[].parts[]`）；`statusUpdate → artifactUpdate → statusUpdate` 三帧序列在真机上不渲染
- 平台「服务名称」就是 `abilityName`，填错报 `extension ability not exist`
