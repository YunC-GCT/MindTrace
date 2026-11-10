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
  python a2a_smoke.py --text "整理数学题"    # 全自动：模板匹配桌面小艺图标 → 拉起 → 进智能体 → 发送/取回复
  python a2a_smoke.py --manual --text "整理数学题"   # 手动模式：用户自己进智能体会话，脚本只发送/取回复
  python a2a_smoke.py --xiaoyi-icon 558,205 --text "你好"  # 桌面图标不暴露文本时的坐标兜底

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
from collections import Counter

# Windows 控制台默认 GBK，模型回复里的数学下标（如 x₀）会让 print 直接抛
# UnicodeEncodeError，导致已经拿到回复却被判失败。
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

DEFAULT_HDC = os.environ.get("HDC") or (
    r"C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe")
DEFAULT_AGENT = "MindTrace 数学笔记助手"
YIXIAO_BUNDLE = "com.huawei.hmos.vassistant"
YIXIAO_ABILITY = "VoiceAbility"
# 桌面小艺图标模板（部分设备桌面图标不在 layout 树里，用截图模板匹配定位点击）
ICON_TEMPLATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xiaoyi-icon-template.png")

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


CLOCK_CHROME_PATTERN = re.compile(r"^[\d\s,，:：.]+$")


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


def dismiss_blocking_dialog(hdc):
    """aa start 失败时会弹「暂无可用打开方式」；点掉它再回桌面。"""
    try:
        nodes = walk(dump_layout(hdc))
    except Exception:
        return
    for key in ("知道了", "确定", "取消"):
        _n, b = find_text(nodes, key, exact=True)
        if b:
            tap(hdc, *center(clickable_containing(nodes, center(b)) or b))
            time.sleep(0.5)
            return


def find_launcher_icon(nodes):
    """在桌面布局里找「小艺」图标：精确文本/无障碍描述优先，排除建议/Work 等卡片。"""
    _n, b = find_text(nodes, "小艺", exact=True)
    if b:
        return _n, b
    for node in nodes:
        text = node.get("text") or node.get("desc") or ""
        if "小艺" not in text:
            continue
        if any(bad in text for bad in ("建议", "Work", "翻译", "画图", "文档", "深度")):
            continue
        b = bounds_of(node["bounds"])
        if b:
            return node, b
    return None, None


def find_icon_by_template(hdc, template_path=ICON_TEMPLATE_PATH, threshold=0.7):
    """截图 + 模板匹配找桌面小艺图标，返回点击坐标；cv2/模板缺失时返回 None。"""
    try:
        import cv2
    except Exception:
        return None
    if not template_path or not os.path.exists(template_path):
        return None
    with tempfile.TemporaryDirectory() as td:
        hdc.shell("snapshot_display -f /data/local/tmp/a2a_home.jpeg")
        hdc.run(["file", "recv", "/data/local/tmp/a2a_home.jpeg", "home.jpeg"], cwd=td)
        path = os.path.join(td, "home.jpeg")
        if not os.path.exists(path):
            return None
        screen = cv2.imread(path)
        template = cv2.imread(template_path)
        if screen is None or template is None:
            return None
        result = cv2.matchTemplate(screen, template, cv2.TM_CCOEFF_NORMED)
        _min_v, max_v, _min_loc, max_loc = cv2.minMaxLoc(result)
        if max_v < threshold:
            return None
        return (max_loc[0] + template.shape[1] // 2, max_loc[1] + template.shape[0] // 2)


def is_xiaoyi_foreground(hdc, nodes=None):
    """小艺是否在前台。

    旧版小艺是独立窗口（bundle=com.huawei.hmos.vassistant）；新版由桌面
    （com.ohos.sceneboard）承载，包名不会变成小艺，只能看布局特征：
    出现精确的「小艺」标题或会话输入框。
    """
    if foreground_bundle(hdc) == YIXIAO_BUNDLE:
        return True
    if foreground_bundle(hdc) != "com.ohos.sceneboard":
        return False
    try:
        items = nodes if nodes is not None else walk(dump_layout(hdc))
    except Exception:
        return False
    texts = [n["text"] for n in items if n["text"]]
    return "小艺" in texts or any(n["type"] == "TextArea" for n in items)


def has_conversation_input(hdc):
    try:
        return any(n["type"] == "TextArea" for n in walk(dump_layout(hdc)))
    except Exception:
        return False


def wait_conversation_input(hdc, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if has_conversation_input(hdc):
            return True
        time.sleep(0.5)
    return False


def wait_foreground(hdc, bundle, seconds):
    """冷启动/加载可能超过固定 5s：轮询前台直到超时。"""
    deadline = time.time() + seconds
    while time.time() < deadline:
        if bundle == YIXIAO_BUNDLE:
            if is_xiaoyi_foreground(hdc):
                return True
        elif foreground_bundle(hdc) == bundle:
            return True
        time.sleep(0.5)
    return False


def launch(hdc, restart=True, icon_point=None, wait_seconds=10.0, icon_template=None, match_threshold=0.7):
    """拉起小艺：aa start → 关启动失败弹窗 → 回桌面点「小艺」图标（桌面不暴露文本时用坐标兜底）。"""
    if restart:
        hdc.shell(f"aa force-stop {YIXIAO_BUNDLE}")
        hdc.shell(f"aa force-stop {YIXIAO_BUNDLE}.launcher")
        time.sleep(1)
    # 1) aa start（部分设备有效；无效时会弹「暂无可用打开方式」）
    hdc.shell(f"aa start -b {YIXIAO_BUNDLE} -a {YIXIAO_ABILITY}")
    if wait_foreground(hdc, YIXIAO_BUNDLE, wait_seconds):
        return True
    # 2) 关掉启动失败弹窗，避免挡住桌面点击
    dismiss_blocking_dialog(hdc)
    hdc.shell("uitest uiInput keyEvent Home")
    time.sleep(1.5)
    # 3) 点桌面「小艺」图标：优先 layout；桌面图标不暴露时用 --xiaoyi-icon 坐标兜底
    nodes = []
    try:
        nodes = walk(dump_layout(hdc))
    except Exception:
        nodes = []
    icon_bounds = None
    if nodes:
        _n, icon_bounds = find_launcher_icon(nodes)
    points = []
    # 桌面图标不在 layout 树时：截图模板匹配（优先级最高，避免点到其他图标）
    template_point = find_icon_by_template(hdc, icon_template or ICON_TEMPLATE_PATH, match_threshold)
    if template_point:
        points.append(template_point)
    if icon_bounds:
        points.append(center(clickable_containing(nodes, center(icon_bounds)) or icon_bounds))
    if icon_point:
        points.append((icon_point[0], icon_point[1]))
    for point in points:
        tap(hdc, point[0], point[1])
        if wait_foreground(hdc, YIXIAO_BUNDLE, wait_seconds):
            return True
        dismiss_blocking_dialog(hdc)
    # 4) 最后一次兜底：再等一轮（冷启动加载可能较慢）
    return wait_foreground(hdc, YIXIAO_BUNDLE, wait_seconds)



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


def screen_size(hdc):
    """屏幕物理分辨率；拿不到时回落到常见手机尺寸。"""
    try:
        _rc, out = hdc.shell("wm size")
        m = re.search(r"(\d+)\s*x\s*(\d+)", out)
        if m:
            return int(m.group(1)), int(m.group(2))
    except Exception:
        pass
    return (1080, 2340)


def open_drawer(hdc):
    """小艺的侧栏靠左上角菜单按钮打开，滑动手势在多数场景不生效。"""
    width, height = screen_size(hdc)
    nodes = walk(dump_layout(hdc))
    for n in nodes:
        if not n["clickable"]:
            continue
        b = bounds_of(n["bounds"])
        # 左上角、窄于屏宽四分之一的按钮才是菜单；用比例而不是像素，
        # 避免竖屏/横屏或不同分辨率下点错位置。
        if b and b[0] < width * 0.2 and b[1] < height * 0.12 and (b[2] - b[0]) < width * 0.25:
            tap(hdc, *center(b))
            time.sleep(1.8)
            return True
    # 退化为从左边滑
    hdc.shell(f"uitest uiInput swipe 2 {height // 2} {int(width * 0.75)} {height // 2} 300")
    time.sleep(1.8)
    return False


def open_agent(hdc, name, tries=6):
    """进入智能体会话：点卡片/侧栏条目，等输入框真正出现；找不到时翻页。"""
    for i in range(tries):
        try:
            nodes = walk(dump_layout(hdc))
        except Exception:
            nodes = []
        if any(n["type"] == "TextArea" for n in nodes):
            return True
        _n, b = find_text(nodes, name)
        if b:
            target = clickable_containing(nodes, center(b)) or b
            tap(hdc, *center(target))
            if wait_conversation_input(hdc, 5.0):
                return True
        # 旧版是左上角菜单抽屉；新版是智能体卡片网格，直接翻页找。
        has_grid = any(n["type"] in ("Grid", "GridItem") for n in nodes)
        if not has_grid:
            open_drawer(hdc)
        hdc.shell("uitest uiInput swipe 1500 1400 300 1400 300")
        time.sleep(1.0)
    return has_conversation_input(hdc)


def send_message(hdc, text):
    nodes = walk(dump_layout(hdc))
    ta = next((n for n in nodes if n["type"] == "TextArea"), None)
    if ta is None:
        raise RuntimeError("找不到输入框")
    tb = bounds_of(ta["bounds"])
    tap(hdc, *center(tb))
    time.sleep(0.8)
    # 必须整体加引号：文本里有空格时，uitest 会把后面的部分当成额外参数丢掉
    quoted = text.replace("\\", "\\\\").replace('"', '\\"')
    hdc.shell(f'uitest uiInput text "{quoted}"')
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


NON_AGENT_REPLY_PATTERN = re.compile(
    r"尊敬的客户|中国移动|中国联通|中国电信|余额|流量|话费|套餐|积分|验证码|停机|欠费|退订"
)


def wait_reply(hdc, before, sent="", timeout=45.0):
    """轮询等待小艺回复：只认小艺窗口里、且不像运营商/系统通知的新文本。

    before 是基准快照的文本计数。同一句话重复发送时，历史里已经有相同气泡，
    按集合去重会把新气泡一起滤掉，所以这里按「出现次数增加」判定新增。
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(2)
        nodes = walk(dump_layout(hdc))
        seen = Counter()
        fresh = []
        for node in nodes:
            text = node["text"]
            if not text:
                continue
            seen[text] += 1
            if seen[text] <= before.get(text, 0):
                continue
            if len(text) <= 2 or text.strip() == sent.strip():
                continue
            if CLOCK_CHROME_PATTERN.match(text.strip()):
                continue
            if len(clean_reply_text(text)) < 4:
                continue
            if NON_AGENT_REPLY_PATTERN.search(text):
                continue
            bundle = node.get("bundle") or ""
            if bundle and bundle != YIXIAO_BUNDLE:
                continue
            fresh.append(text)
        if fresh:
            return fresh
    return []


def clean_reply_text(text):
    """去掉时间戳 / 「内容由 AI 生成」等界面噪声，返回用于判截断的正文。"""
    cleaned = text or ""
    for pattern in REPLY_NOISE_PATTERNS:
        cleaned = pattern.sub("", cleaned)
    return cleaned.strip()


SENTENCE_END = ("。", "！", "？", "!", "?", "…")


def reply_looks_complete(text, min_chars):
    """确认/取消/保存回执本来就短，有句末标点时不算截断。"""
    if len(text) >= min_chars:
        return True
    return len(text) >= 6 and text.rstrip().endswith(SENTENCE_END)


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
    ap.add_argument(
        "--xiaoyi-icon",
        default=os.environ.get("A2A_XIAOYI_ICON", ""),
        help="桌面小艺图标坐标兜底，格式 x,y（部分设备桌面不暴露图标文本时使用，如 558,205）",
    )
    ap.add_argument(
        "--no-launch",
        action="store_true",
        help="不自动拉起小艺：假定用户已手动打开小艺（配合 --no-open-agent 可直接在当前会话发消息）",
    )
    ap.add_argument(
        "--no-open-agent",
        action="store_true",
        help="不自动点侧栏进入智能体：假定用户已手动进入目标智能体会话",
    )
    ap.add_argument(
        "--manual",
        action="store_true",
        help="手动模式 = --no-launch --no-open-agent（用户自己从小艺入口进入智能体会话后，脚本只负责发送/取回复）",
    )
    ap.add_argument(
        "--icon-template",
        default=ICON_TEMPLATE_PATH,
        help="桌面小艺图标模板 PNG 路径（默认 scripts/a2a-smoke/xiaoyi-icon-template.png）",
    )
    ap.add_argument(
        "--match-threshold",
        type=float,
        default=0.7,
        help="图标模板匹配阈值（默认 0.7）",
    )
    ap.add_argument(
        "--launch-wait",
        type=float,
        default=10.0,
        help="拉起小艺后每轮等待前台 bundle 的秒数（默认 10s，冷启动慢时调大）",
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

        icon_point = None
        if args.xiaoyi_icon:
            try:
                icon_point = tuple(int(v.strip()) for v in args.xiaoyi_icon.split(",")[:2])
            except Exception:
                icon_point = None
        manual = args.manual or (args.no_launch and args.no_open_agent)
        if manual:
            # 手动模式：不拉起、不点击；用户已从小艺入口进入智能体会话
            fg = foreground_bundle(hdc)
            result["foreground"] = fg
            if not fg:
                raise RuntimeError("手动模式：当前前台 bundle 为空，请确认小艺/智能体会话在前台，或加 --no-launch 前先打开")
        elif not args.no_launch:
            if not launch(hdc, restart=not args.no_restart, icon_point=icon_point, wait_seconds=args.launch_wait, icon_template=args.icon_template, match_threshold=args.match_threshold):
                raise RuntimeError("拉起小艺失败")
        else:
            fg = foreground_bundle(hdc)
            result["foreground"] = fg
            if not is_xiaoyi_foreground(hdc):
                raise RuntimeError(f"--no-launch 需要小艺在前台（当前: {fg or '未知'}）；请先手动打开小艺或进入智能体会话")
        fg = foreground_bundle(hdc)
        result["foreground"] = fg
        # 手动模式下小艺可能由桌面（com.ohos.sceneboard）承载，不能再要求 bundle 名严格相等。
        if not args.manual and not is_xiaoyi_foreground(hdc):
            raise RuntimeError(f"小艺没有到前台（当前前台: {fg or '未知'}），多半是锁屏或启动被拦")
        if not (args.no_open_agent or args.manual):
            if not open_agent(hdc, args.agent):
                raise RuntimeError(f"界面里找不到智能体「{args.agent}」，确认已发真机测试并重启小艺")

        # 基准快照要在进入智能体会话之后取，否则侧栏/历史都会被当成新回复
        before = Counter(n["text"] for n in walk(dump_layout(hdc)))
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
        reply_complete = bool(reply) and reply_looks_complete(cleaned_reply, args.min_reply_chars)
        if reply and not reply_complete:
            errors.append(f"回复疑似被截断：{result['reply_chars']} 字")
        if errors:
            result["errors"] = errors
        result["reply_complete"] = reply_complete
        result["ok"] = reply_complete
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
