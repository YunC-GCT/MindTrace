#!/usr/bin/env node
/**
 * device-runner.mjs — 真机验证一键工具（hilog 流式捕获 + 锁屏预检 + 结果判定）
 *
 * 背景：真机调试反复踩三个坑——① 锁屏后 `aa start` 直接失败；② `hilog -x` 快照会被
 * chromium 日志瞬间刷掉，e2e 阶段日志抓不到；③ 每次验证要手敲 hdc 组装命令。
 *
 * 用法:
 *   node scripts/device-runner.mjs install                     # 重装 common HSP → agents HSP → entry HAP
 *   node scripts/device-runner.mjs e2e draft [--cold] [--wait 300] [--debug]
 *                                                              # 跑 --ps e2e <mode> 自检并等待 stage=done/fail
 *   node scripts/device-runner.mjs capture                     # 跑 scripts/e2e-capture/run.mjs 并判定 PASS
 *   node scripts/device-runner.mjs smoke [文本]                 # 跑 a2a_smoke 并判定 ok:true
 *   node scripts/device-runner.mjs status                      # 设备/进程/锁屏预检
 *
 * 环境变量:
 *   HDC  hdc 可执行文件路径（缺省用 DevEco SDK 默认路径）
 *
 * 输出:
 *   阶段日志实时打印（仅 E2E 相关行）；完整流式日志写入 .device-logs/<name>-<ts>.log
 *   退出码 0 = 判定成功；1 = 失败/超时；2 = 设备锁屏/未连接
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HDC = process.env.HDC ?? 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe';
const BUNDLE = 'com.example.mindtrace';
const ABILITY = 'EntryAbility';
const LOG_DIR = join(REPO_ROOT, '.device-logs');
const E2E_TAG = 'A0E2E0';

function log(msg) {
  process.stdout.write(msg + '\n');
}

function ensureLogDir() {
  if (!existsSync(LOG_DIR)) mkdirSync(LOG_DIR, { recursive: true });
}

function hdc(args, { timeout = 60000, okCodes = [0] } = {}) {
  return new Promise((resolvePromise) => {
    const child = spawn(HDC, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    const timer = setTimeout(() => child.kill(), timeout);
    child.stdout.on('data', (d) => { out += d.toString(); });
    child.stderr.on('data', (d) => { out += d.toString(); });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolvePromise({ code, out, locked: out.includes('10106102') || out.includes('screen is locked') });
    });
  });
}

async function targets() {
  const { out } = await hdc(['list', 'targets']);
  const list = out.split('\n').map((s) => s.trim()).filter(Boolean).filter((s) => !s.includes('[Empty]'));
  return list;
}

async function requireDevice() {
  const list = await targets();
  if (list.length === 0) {
    log('✗ 未发现设备：hdc list targets 为空（检查 USB/无线调试）');
    return null;
  }
  return list[0];
}

async function startE2e(mode, { cold, debug, waitMs, markers }) {
  ensureLogDir();
  if (cold) {
    log('→ force-stop ' + BUNDLE);
    await hdc(['shell', 'aa force-stop ' + BUNDLE]);
  }
  const stream = spawn(HDC, ['shell', 'hilog'], { stdio: ['ignore', 'pipe', 'pipe'] });
  const collected = [];
  const matched = [];
  stream.stdout.on('data', (buf) => {
    for (const line of buf.toString().split('\n')) {
      if (!line.trim()) continue;
      collected.push(line);
      if (line.includes(E2E_TAG)) {
        matched.push(line);
        log('  ' + line.trim());
      }
    }
  });
  await new Promise((r) => setTimeout(r, 1200));
  const launch = `aa start -a ${ABILITY} -b ${BUNDLE}${debug ? ' -D' : ''} --ps e2e ${mode}`;
  log('→ ' + launch);
  const startRes = await hdc(['shell', launch], { timeout: 30000 });
  if (startRes.locked) {
    stream.kill();
    log('✗ 设备锁屏（aa start 被拒），请解锁并关闭自动锁屏后重试');
    return { code: 2 };
  }
  if (startRes.code !== 0) {
    log(startRes.out.trim());
    stream.kill();
    return { code: 1 };
  }
  const wanted = markers ?? ['stage=done', 'stage=fail'];
  const deadline = Date.now() + waitMs;
  let hit = null;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 300));
    hit = matched.find((line) => wanted.some((m) => line.includes(m)));
    if (hit) break;
  }
  stream.kill();
  const logFile = join(LOG_DIR, `e2e-${mode}-${Date.now()}.log`);
  writeFileSync(logFile, collected.join('\n') + '\n', 'utf8');
  log('→ 完整日志: ' + logFile);
  if (!hit) {
    log(`✗ ${waitMs}ms 内未等到 ${wanted.join(' / ')}（日志已保存，可查 A0E2E0 行）`);
    return { code: 1 };
  }
  log('→ 命中: ' + hit.trim());
  const failed = hit.includes('stage=fail') || hit.includes('stage=done ok=0');
  return { code: failed ? 1 : 0 };
}

async function runNode(script, extraArgs = []) {
  return await new Promise((res) => {
    const child = spawn(process.execPath, [join(REPO_ROOT, script), ...extraArgs], {
      cwd: REPO_ROOT,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, HDC },
    });
    let out = '';
    child.stdout.on('data', (d) => { out += d.toString(); process.stdout.write(d); });
    child.stderr.on('data', (d) => { out += d.toString(); });
    child.on('close', (code) => res({ code, out }));
  });
}

async function runPython(script, extraArgs = []) {
  return await new Promise((res) => {
    const child = spawn('python', [join(REPO_ROOT, script), ...extraArgs], {
      cwd: REPO_ROOT,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, HDC },
    });
    let out = '';
    child.stdout.on('data', (d) => { out += d.toString(); });
    child.stderr.on('data', (d) => { out += d.toString(); });
    child.on('close', (code) => res({ code, out }));
  });
}

async function cmdInstall() {
  const device = await requireDevice();
  if (!device) return 2;
  log('→ 设备: ' + device);
  const artifacts = [
    'common/build/default/outputs/default/common-default-signed.hsp',
    'agents/build/default/outputs/default/agents-default-signed.hsp',
    'entry/build/default/outputs/default/entry-default-signed.hap',
  ];
  for (const rel of artifacts) {
    const abs = join(REPO_ROOT, rel);
    if (!existsSync(abs)) {
      log('✗ 缺少产物: ' + rel + '（先跑 node scripts/build-hsp-hap.mjs）');
      return 1;
    }
    const { code, out } = await hdc(['install', '-r', abs], { timeout: 120000 });
    log('  ' + rel.split('/').slice(-1)[0] + ': ' + (code === 0 ? 'ok' : out.trim().split('\n').slice(-1)[0]));
    if (code !== 0) return 1;
  }
  await hdc(['shell', 'aa force-stop ' + BUNDLE]);
  return 0;
}

async function cmdStatus() {
  const list = await targets();
  log('设备: ' + (list.length > 0 ? list.join(', ') : '(无)'));
  if (list.length === 0) return 2;
  const ps = await hdc(['shell', `ps -ef | grep '${BUNDLE}' | grep -v render | grep -v grep`]);
  log('应用进程: ' + (ps.out.trim() ? ps.out.trim().split('\n').length + ' 个' : '未运行'));
  return 0;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  switch (cmd) {
    case 'install':
      return await cmdInstall();
    case 'status':
      return await cmdStatus();
    case 'e2e': {
      const mode = rest.find((x) => !x.startsWith('--')) ?? 'true';
      const cold = rest.includes('--cold');
      const debug = rest.includes('--debug');
      const waitIdx = rest.indexOf('--wait');
      const waitMs = waitIdx >= 0 ? Number(rest[waitIdx + 1]) * 1000 : 300000;
      if (!(await requireDevice())) return 2;
      return (await startE2e(mode, { cold, debug, waitMs })).code;
    }
    case 'capture': {
      if (!(await requireDevice())) return 2;
      const { code, out } = await runNode('scripts/e2e-capture/run.mjs');
      const pass = out.includes('判定') && out.includes('PASS');
      if (!pass) log('✗ e2e-capture 未判定 PASS');
      return pass && code === 0 ? 0 : 1;
    }
    case 'smoke': {
      if (!(await requireDevice())) return 2;
      const text = rest.join(' ') || '存笔记：柯西中值定理';
      const { code, out } = await runPython('scripts/a2a-smoke/a2a_smoke.py',
        ['--no-restart', '--text', text, '--wait-seconds', '120', '--min-reply-chars', '10']);
      const ok = out.includes('"ok": true');
      log(ok ? '✓ a2a_smoke ok:true' : '✗ a2a_smoke 未返回 ok:true');
      if (ok) {
        const m = out.match(/"reply_text":\s*"([^"]*)"/);
        if (m) log('  reply_text: ' + m[1]);
      }
      return ok && code === 0 ? 0 : 1;
    }
    default:
      log('用法: node scripts/device-runner.mjs <install|status|capture|smoke|e2e <mode> [--cold] [--debug] [--wait 秒]>');
      return 1;
  }
}

main().then((code) => process.exit(code)).catch((e) => { console.error(e); process.exit(1); });
