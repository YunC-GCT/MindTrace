# -*- coding: utf-8 -*-
"""
A2A 延迟采样: 在小艺的智能体会话里连发 N 条, 逐条解析 hilog 时间戳算端到端耗时。

用途: 定默认模型前先攒够样本 (见 docs/plans/xiaoyi-latency-tuning-plan.md)。
单条耗时 = AgentExtAbility 收到 onData → 回 task 快照发出, 期间几乎全是 LLM 往返。
冷启动第一条会明显偏大 (扩展进程拉起 + 模型加载), 统计时单独看。

    python scripts/a2a-smoke/latency_series.py --n 20 --text 整理数学题 --out samples.jsonl

前置: 设备已连、小艺已装好本 app 的 AgentCard、桌面有「MindTrace 数学笔记助手」图标
(脚本靠点这个图标进会话, 因为 `aa start` 起不来小艺前台)。
"""
import argparse
import importlib.util
import json
import os
import re
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
_smoke_path = os.path.join(HERE, "a2a_smoke.py")
_spec = importlib.util.spec_from_file_location("a2a_smoke", _smoke_path)
if _spec is None or _spec.loader is None:
    raise RuntimeError("找不到 a2a_smoke.py: " + _smoke_path)
M = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(M)

TS = re.compile(r"(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})")
# 桌面上的智能体图标坐标 (1840x2800 屏), 换了设备要重取
ICON_XY = (327, 448)


def ms_of(line):
    m = TS.search(line)
    if not m:
        return None
    hh, mm, ss = m.group(1).split(" ")[1].split(":")
    return (int(hh) * 3600 + int(mm) * 60 + float(ss)) * 1000.0


def ensure_agent_chat(hdc):
    """已经在小艺的智能体会话里就什么都不做; 否则从桌面点图标进去。"""
    nodes = M.walk(M.dump_layout(hdc))
    if M.find_text(nodes, M.DEFAULT_AGENT)[1]:
        return True
    hdc.shell("uitest uiInput keyEvent Home")
    time.sleep(2.5)
    M.tap(hdc, *ICON_XY)
    time.sleep(6)
    nodes = M.walk(M.dump_layout(hdc))
    return bool(M.find_text(nodes, M.DEFAULT_AGENT)[1])


def sample_once(hdc, text, n, timeout=60.0):
    if not ensure_agent_chat(hdc):
        return {"n": n, "ok": False, "error": "进不到智能体会话"}
    hdc.shell("hilog -r")
    before = {x["text"] for x in M.walk(M.dump_layout(hdc))}
    t0 = time.time()
    M.send_message(hdc, text)
    reply = M.wait_reply(hdc, before, sent=text, timeout=timeout)
    wall = int((time.time() - t0) * 1000)
    log = hdc.shell('hilog -x | grep -i "MindTraceA2A" | tail -60')[1]
    lines = [l for l in log.splitlines() if "MindTraceA2A" in l]
    req = next((l for l in lines if "onData 收到" in l), None)
    done = next((l for l in reversed(lines) if "task snapshot sent" in l), None)
    llm = next((l for l in reversed(lines) if "耗时" in l), None)
    span = None
    if req and done:
        a, b = ms_of(req), ms_of(done)
        if a is not None and b is not None:
            span = int(b - a)
    llm_ms = None
    if llm:
        m = re.search(r"耗时\s*(\d+)\s*ms", llm)
        if m:
            llm_ms = int(m.group(1))
    body = M.clean_reply_text(max(reply, key=len)) if reply else ""
    return {
        "n": n,
        "ok": bool(reply) and bool(span) and span > 0,
        "a2a_ms": span,
        "llm_ms": llm_ms,
        "wall_ms": wall,
        "reply_chars": len(body),
        "reply": body[:80],
        # llm_ms 缺失 = 模型侧没走通 (例如 JSON 提取失败), 不能算进干净样本
        "model_failed": llm_ms is None,
    }


def summarize(rows):
    clean = [r for r in rows if r.get("llm_ms")]
    failed = [r for r in rows if r.get("ok") and not r.get("llm_ms")]
    spans = sorted(r["a2a_ms"] for r in clean)
    print("")
    print("样本 %d 条 | 正常回复 %d | 模型失败回复 %d | 未测到 %d"
          % (len(rows), len(clean), len(failed), len(rows) - len(clean) - len(failed)))
    if not spans:
        return
    warm = spans[1:] if len(spans) > 1 else spans
    print("  含冷启动: min %d  p50 %d  max %d" % (spans[0], int(statistics.median(spans)), spans[-1]))
    print("  去冷启动: min %d  p50 %d  p95 %d  max %d  (n=%d)"
          % (warm[0], int(statistics.median(warm)), warm[min(len(warm) - 1, int(len(warm) * 0.95))],
             warm[-1], len(warm)))
    ratio = statistics.mean([r["llm_ms"] / r["a2a_ms"] for r in clean])
    print("  LLM 占端到端 %.1f%%" % (100 * ratio))
    if failed:
        print("  模型失败样本: " + ", ".join("第%d条 %dms" % (r["n"], r["a2a_ms"]) for r in failed))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hdc", default=os.environ.get("HDC", M.DEFAULT_HDC))
    ap.add_argument("--text", default="整理数学题")
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--out", default="samples.jsonl")
    ap.add_argument("--timeout", type=float, default=60.0)
    args = ap.parse_args()

    hdc = M.Hdc(args.hdc)
    M.ensure_device(hdc)
    rows = []
    for i in range(args.n):
        row = sample_once(hdc, args.text, i + 1, args.timeout)
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        with open(args.out, "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
        if row.get("error"):
            break
        time.sleep(2)
    summarize(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
