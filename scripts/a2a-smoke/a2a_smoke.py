#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
小艺端A2A 冒烟测试脚本（真机）

自动完成：解锁检查 -> 拉起小艺 -> 从侧栏点进目标智能体 -> 输入消息 -> 发送
         -> 轮询界面拿回复 -> 抓 hilog 生命周期

用法:
  python a2a_smoke.py --text "整理相册里的数学题"
  python a2a_smoke.py --agent "MindTrace 数学笔记助手" --text "你好" --tag MindTraceA2A
  python a2a_smoke.py --no-restart           # 不清小艺，直接在当前界面操作

依赖: 仅标准库；需要 hdc（默认取 DevEco SDK 路径，可用 --hdc 或 HDC 环境变量覆盖）
退出码: 0 成功拿到回复；1 失败（信息在 stderr 与 JSON 里）
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

DEFAULT_HDC = os.environ.get("HDC") or (
    r"C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe")
DEFAULT_AGENT = "MindTrace 数学笔记助手"
YIXIAO_BUNDLE = "com.huawei.hmos.vassistant"
YIXIAO_ABILITY = "VoiceAbility"

# 气泡里混入的界面噪声：时间戳、「内容由 AI 生成」等，不算回复正文字数
REPLY_NOISE_PATTERNS = (
    re.compile(r"\[\d{4}[-/]\d{1,2}[-/]\d{1,2}[ T]\d{1,2}:\d{2}(?::\d{2})?\]"),
    re.compile(r"\d{4}[-/]\d{1,2}[-/]\d{1,2}[ T]\d{1,2}:\d{2}(?::\d{2})?"),
    re.compile(r"内容\s*由\s*AI\s*生成[，,。.!！]?", re.IGNORECASE),
    re.compile(r"AI\s*生成[，,。.!！]?", re.IGNORECASE),
    re.compile(r"^\s*\d{1,2}:\d{2}\s*$", re.MULTILINE),
    # 相对时间标签（「刚刚」「3分钟前」「12秒前」）同样不是回复正文
    re.compile(r"^\s*(刚刚|\d+\s*(秒|分钟|小时|天)前)\s*$", re.MULTILINE),
)


class Hdc:
    def __init__(self, path: str):
        self.path = path

    def run(self, args, timeout=60, cwd=None):
        p = subprocess.run([self.path] + args, capture_output=True, timeout=timeout, cwd=cwd)
        out = (p.stdout or b"").decode("utf-8", "replace") + (p.stderr or b"").decode("utf-8", "replace")
        return p.returncode, out

    def shell(self, cmd, timeout=60):
        return self.run(["shell", cmd], timeout=timeout)


# ---------- layout ----------
def dump_layout(hdc: Hdc):
    rc, out = hdc.shell("uitest dumpLayout -p /data/local/tmp/a2a_layout.json")
    if "DumpLayout saved" not in out:
        raise RuntimeError("dumpLayout 失败: " + out.strip()[:200])
    with tempfile.TemporaryDirectory() as td:
        rc, out2 = hdc.run(["file", "recv", "/data/local/tmp/a2a_layout.json", "a2a_layout.json"], cwd=td)
        path = os.path.join(td, "a2a_layout.json")
        if not os.path.exists(path):
            raise RuntimeError("拉取布局失败: " + out2.strip()[:200])
        with open(path, encoding="utf-8") as f:
            return json.load(f)


def walk(node, depth=0, out=None):
    if out is None:
        out = []
    a = node.get("attributes", {}) or {}
    out.append({
        "depth": depth,
        "type": a.get("type") or "",
        "text": (a.get("text") or "").strip(),
        "desc": (a.get("description") or "").strip(),
        "bounds": a.get("bounds") or "",
        "clickable": a.get("clickable") == "true",
        "bundle": a.get("bundleName") or "",
    })
    for c in node.get("children") or []:
        walk(c, depth + 1, out)
    return out


def bounds_of(s):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", s or "")
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def center(b):
    x1, y1, x2, y2 = b
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap(hdc, x, y):
    hdc.shell(f"uitest uiInput click {x} {y}")


def find_text(nodes, needle, exact=False):
    for n in nodes:
        t = n["text"]
        if not t:
            continue
        if (t == needle) if exact else (needle in t):
            b = bounds_of(n["bounds"])
            if b:
                return n, b
    return None, None


# ---------- device ----------
def ensure_device(hdc):
    rc, out = hdc.run(["list", "targets"], timeout=20)
    if rc != 0 or not out.strip() or "Empty" in out:
        raise RuntimeError("没有连接设备: " + out.strip()[:200])
    return out.strip().splitlines()[0].strip()


def foreground_bundle(hdc):
    try:
        nodes = walk(dump_layout(hdc))
    except Exception:
        return ""
    for n in nodes:
        if n["depth"] == 1 and n["bundle"]:
            return n["bundle"]
    return ""


def is_locked(hdc):
    # SCBScreenLock 窗口常驻，不能作为锁屏依据；锁屏时前台不是普通应用
    b = foreground_bundle(hdc)
    return b in ("", "com.ohos.systemui")


def launch(hdc, restart=True):
    """aa start 常常只起进程不起界面，兜底回桌面点「小艺」图标。"""
    if restart:
        hdc.shell(f"aa force-stop {YIXIAO_BUNDLE}")
        time.sleep(1)
    hdc.shell(f"aa start -b {YIXIAO_BUNDLE} -a {YIXIAO_ABILITY}")
    time.sleep(5)
    if foreground_bundle(hdc) == YIXIAO_BUNDLE:
        return True

    # 兜底 1：直接点桌面上的小艺图标
    nodes = walk(dump_layout(hdc))
    n, b = find_text(nodes, "小艺", exact=True)
    if b:
        target = clickable_containing(nodes, center(b)) or b
        tap(hdc, *center(target))
        time.sleep(4.5)
        if foreground_bundle(hdc) == YIXIAO_BUNDLE:
            return True

    # 兜底 2：再等一轮（冷启动有时较慢）
    time.sleep(4)
    return foreground_bundle(hdc) == YIXIAO_BUNDLE


def clickable_containing(nodes, pt):
    """返回包含该点的可点节点中最小的那个；整屏容器会吞掉点击。"""
    best, best_area = None, None
    for n in nodes:
        if not n["clickable"]:
            continue
        b = bounds_of(n["bounds"])
        if not (b and b[0] <= pt[0] <= b[2] and b[1] <= pt[1] <= b[3]):
            continue
        area = (b[2] - b[0]) * (b[3] - b[1])
        if best is None or area < best_area:
            best, best_area = b, area
    return best


def open_drawer(hdc):
    """小艺的侧栏靠左上角菜单按钮打开，滑动手势在多数场景不生效。"""
    nodes = walk(dump_layout(hdc))
    for n in nodes:
        if not n["clickable"]:
            continue
        b = bounds_of(n["bounds"])
        if b and b[0] < 200 and b[1] < 260 and b[2] < 400 and (b[2] - b[0]) < 200:
            tap(hdc, *center(b))
            time.sleep(1.8)
            return True
    # 退化为从左边滑
    hdc.shell("uitest uiInput swipe 5 1400 800 1400 300")
    time.sleep(1.8)
    return False


def open_agent(hdc, name, tries=4):
    """侧栏没展开时先从左边缘滑出抽屉，再点智能体。"""
    for i in range(tries):
        nodes = walk(dump_layout(hdc))
        n, b = find_text(nodes, name)
        if b:
            tap(hdc, *center(b))
            time.sleep(2.5)
            return True
        open_drawer(hdc)
        nodes = walk(dump_layout(hdc))
        n, b = find_text(nodes, name)
        if b:
            tap(hdc, *center(b))
            time.sleep(2.5)
            return True
    return False


def send_message(hdc, text):
    nodes = walk(dump_layout(hdc))
    ta = next((n for n in nodes if n["type"] == "TextArea"), None)
    if ta is None:
        raise RuntimeError("找不到输入框")
    tb = bounds_of(ta["bounds"])
    tap(hdc, *center(tb))
    time.sleep(0.8)
    hdc.shell("uitest uiInput text " + text)
    time.sleep(0.8)

    # 输入后重新取布局：发送键在输入框右侧同一行
    nodes = walk(dump_layout(hdc))
    ta = next((n for n in nodes if n["type"] == "TextArea"), None)
    tb = bounds_of(ta["bounds"]) if ta else tb
    best = None
    for n in nodes:
        if not n["clickable"]:
            continue
        b = bounds_of(n["bounds"])
        if not b:
            continue
        cx, cy = center(b)
        if b[0] >= tb[2] - 40 and tb[1] - 20 <= cy <= tb[3] + 20:
            if best is None or b[0] > best[0]:
                best = b
    if best:
        tap(hdc, *center(best))
    else:
        hdc.shell("uitest uiInput keyEvent 2054")  # 退化为回车
    return True


def wait_reply(hdc, before, sent="", timeout=45.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(2)
        nodes = walk(dump_layout(hdc))
        fresh = [n["text"] for n in nodes if n["text"] and n["text"] not in before]
        # 去掉自己发出去的那条和过短噪声
        fresh = [t for t in fresh if len(t) > 2 and t.strip() != sent.strip()]
        if fresh:
            return fresh
    return []


def clean_reply_text(text):
    """去掉时间戳 / 「内容由 AI 生成」等界面噪声，返回用于判截断的正文。"""
    cleaned = text or ""
    for pattern in REPLY_NOISE_PATTERNS:
        cleaned = pattern.sub("", cleaned)
    return cleaned.strip()


# 小艺吞公式时会留下零宽占位（U+200B）；其余零宽格式符也一起计数
ZERO_WIDTH_PATTERN = re.compile("[\u200b\u200c\u200d\ufeff]")


def reply_text_metrics(text):
    """对 reply_text 计算可观测字段：区分「快照里有什么」与「小艺显示了什么」。"""
    raw = text or ""
    return {
        "reply_code_points": len(raw),
        "reply_utf8_bytes": len(raw.encode("utf-8")),
        "dollar_count": raw.count("$"),
        "backslash_count": raw.count("\\"),
        "zero_width_count": len(ZERO_WIDTH_PATTERN.findall(raw)),
        "has_sqrt": "√" in raw,
        "has_ge": "≥" in raw,
    }


def hilog_tail(hdc, tag, lines=6):
    rc, out = hdc.shell(f'hilog -x | grep -i "{tag}" | tail -{lines}', timeout=90)
    return out.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hdc", default=os.environ.get("HDC", DEFAULT_HDC))
    ap.add_argument("--agent", default=DEFAULT_AGENT)
    ap.add_argument("--text", default="把相册里的数学题整理成笔记")
    ap.add_argument("--tag", default="MindTraceA2A", help="hilog 关键字")
    ap.add_argument("--no-restart", action="store_true", help="不重启小艺")
    ap.add_argument(
        "--case",
        default="",
        help="本次冒烟用例标签（如 A/B/C），原样写进输出 JSON",
    )
    ap.add_argument(
        "--wait-seconds",
        "--timeout",
        dest="wait_seconds",
        type=float,
        default=45.0,
        help="轮询等待回复的秒数（默认 45；--timeout 为向后兼容别名）",
    )
    ap.add_argument(
        "--min-reply-chars",
        type=int,
        default=20,
        help="回复清洗后的最少字数，低于该值判定疑似截断（默认 20）",
    )
    args = ap.parse_args()

    hdc = Hdc(args.hdc)
    result = {"ok": False, "device": None, "agent": args.agent, "text": args.text, "case": args.case}
    try:
        result["device"] = ensure_device(hdc)
        # 亮屏 + 临时把息屏时间拉到 30 分钟，避免跑到一半又锁上
        hdc.shell("power-shell wakeup")
        hdc.shell("power-shell timeout -o 1800000")
        if is_locked(hdc):
            raise RuntimeError("设备可能已锁屏（前台包名为空或 systemui）：请解锁一次后重试（脚本已把息屏时间临时调到 30 分钟）")

        if not launch(hdc, restart=not args.no_restart):
            raise RuntimeError("拉起小艺失败")
        fg = foreground_bundle(hdc)
        result["foreground"] = fg
        if fg != YIXIAO_BUNDLE:
            raise RuntimeError(f"小艺没有到前台（当前前台: {fg or '未知'}），多半是锁屏或启动被拦")
        if not open_agent(hdc, args.agent):
            raise RuntimeError(f"界面里找不到智能体「{args.agent}」，确认已发真机测试并重启小艺")

        # 基准快照要在进入智能体会话之后取，否则侧栏/历史都会被当成新回复
        before = {n["text"] for n in walk(dump_layout(hdc))}
        send_message(hdc, args.text)
        time.sleep(2)
        reply = wait_reply(hdc, before, sent=args.text, timeout=args.wait_seconds)
        result["reply"] = reply
        # 最长的那条通常是 agent 气泡正文
        result["reply_text"] = max(reply, key=len) if reply else ""
        result.update(reply_text_metrics(result["reply_text"]))
        cleaned_reply = clean_reply_text(result["reply_text"])
        result["reply_chars"] = len(cleaned_reply)
        errors = []
        if not reply:
            errors.append("没有拿到回复")
        if result["reply_chars"] < args.min_reply_chars:
            errors.append(f"回复疑似被截断：{result['reply_chars']} 字")
        if errors:
            result["errors"] = errors
        result["ok"] = bool(reply) and result["reply_chars"] >= args.min_reply_chars
        result["hilog"] = hilog_tail(hdc, args.tag)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["ok"] else 1
    except Exception as e:
        result["error"] = str(e)
        try:
            result["hilog"] = hilog_tail(hdc, args.tag)
        except Exception:
            pass
        print(json.dumps(result, ensure_ascii=False, indent=2))
        print("[FAIL] " + str(e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
