// Launch an isolated, headless VS Code (own Xvfb display, profile and extensions dir) with
// the installed Lean extension plus the test-only driver. Nothing touches the user's profile.
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, symlinkSync, readdirSync } from 'node:fs';
import { createServer } from 'node:net';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { connect } from './cdp.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const codeBin = process.env.IRIS_E2E_CODE ?? '/usr/share/code/code';
const userExt = join(process.env.HOME, '.vscode/extensions');
const ensure = id => { const d = readdirSync(userExt).filter(n => n.toLowerCase().startsWith(id + '-')).sort().at(-1);
  if (!d) throw new Error(`extension ${id} is not installed in ${userExt}`); return join(userExt, d); };
const freePort = () => new Promise(res => { const s = createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); });

async function until(what, f, timeoutMs, intervalMs = 500) {
  const end = Date.now() + timeoutMs; let last;
  while (Date.now() < end) { try { const v = await f(); if (v) return v; } catch (e) { last = e; } await sleep(intervalMs); }
  throw new Error(`timed out: ${what}${last ? ` (${last.message})` : ''}`);
}

export async function launch({ workspace, settings = {}, width = 1600, height = 1000, log = console.log } = {}) {
  // Per-run profiles, logs and screenshots stay out of the source tree.
  const runs = process.env.IRIS_E2E_RUNS ?? join(process.env.TMPDIR ?? tmpdir(), 'vscode-e2e-runs');
  const run = join(runs, new Date().toISOString().replace(/[:.]/g, '-'));
  const ext = join(run, 'ext'), user = join(run, 'user');
  mkdirSync(ext, { recursive: true }); mkdirSync(join(user, 'User'), { recursive: true });
  for (const id of ['leanprover.lean4', 'tamasfe.even-better-toml']) { const d = ensure(id); symlinkSync(d, join(ext, d.split('/').at(-1))); }
  symlinkSync(join(here, 'driver'), join(ext, 'iris-e2e.iris-e2e-driver-0.0.1'));
  writeFileSync(join(user, 'User/settings.json'), JSON.stringify({
    'security.workspace.trust.enabled': false, 'telemetry.telemetryLevel': 'off', 'update.mode': 'none',
    'extensions.autoUpdate': false, 'extensions.autoCheckUpdates': false, 'workbench.startupEditor': 'none',
    'workbench.tips.enabled': false, 'chat.disableAIFeatures': true, 'workbench.secondarySideBar.defaultVisibility': 'hidden',
    'window.restoreWindows': 'none', 'git.openRepositoryInParentFolders': 'never', 'git.enabled': false, 'lean4.alwaysAskBeforeInstallingLeanVersions': false, ...settings }, null, 1));

  // Xvfb picks a free display and reports it on fd 3.
  const xvfb = spawn('Xvfb', ['-displayfd', '3', '-screen', '0', `${width}x${height}x24`, '-nolisten', 'tcp'], { stdio: ['ignore', 'ignore', 'pipe', 'pipe'] });
  const display = await new Promise((res, rej) => { let s = ''; xvfb.stdio[3].on('data', d => { s += d; if (s.includes('\n')) res(':' + s.trim()); }); xvfb.once('exit', c => rej(new Error(`Xvfb exited ${c}`))); });
  const driverPort = await freePort(), debugPort = await freePort();
  const codeLog = join(run, 'code.log');
  const code = spawn(codeBin, [`--user-data-dir=${user}`, `--extensions-dir=${ext}`, `--remote-debugging-port=${debugPort}`,
    '--disable-gpu', '--no-sandbox', '--skip-welcome', '--skip-release-notes', '--disable-workspace-trust', '--new-window', workspace], {
    detached: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, DISPLAY: display, IRIS_E2E_DRIVER_PORT: String(driverPort), ELECTRON_ENABLE_LOGGING: '1' } });
  const out = []; code.stdout.on('data', d => out.push(d)); code.stderr.on('data', d => out.push(d));
  let closed = false;
  const close = async () => {
    if (closed) return; closed = true;
    try { process.kill(-code.pid, 'SIGTERM'); } catch {}
    await sleep(2000); try { process.kill(-code.pid, 'SIGKILL'); } catch {}
    xvfb.kill('SIGTERM'); writeFileSync(codeLog, Buffer.concat(out));
  };
  const driver = async op => {
    const r = await (await fetch(`http://127.0.0.1:${driverPort}/`, { method: 'POST', body: JSON.stringify(op) })).json();
    if (!r.ok) throw new Error(`driver ${op.op}: ${r.error}`); return r.value;
  };
  try {
    log(`vscode: display ${display}, profile ${run}`);
    await until('VS Code driver', () => driver({ op: 'ping' }), 60000);
    const pages = await until('workbench page', async () => (await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json())
      .find(t => t.type === 'page' && /workbench\.html/.test(t.url)), 30000);
    const workbench = await connect(pages.webSocketDebuggerUrl);
    await workbench.send('Runtime.enable');
    return { run, display, driver, workbench, debugPort, close, until };
  } catch (e) { await close(); throw e; }
}

// The infoview is a webview: an iframe target with several execution contexts (host shim and
// the inner content frame). Evaluate `expression` in every context of every webview target and
// return the first value that is not undefined. Expressions should return undefined to decline.
export async function webviewEval(vs, expression) {
  const browser = await connect((await (await fetch(`http://127.0.0.1:${vs.debugPort}/json/version`)).json()).webSocketDebuggerUrl);
  try {
    const { targetInfos } = await browser.send('Target.getTargets');
    for (const t of targetInfos.filter(t => t.type === 'iframe' && t.url.startsWith('vscode-webview://'))) {
      const { sessionId } = await browser.send('Target.attachToTarget', { targetId: t.targetId, flatten: true });
      const contexts = [];
      browser.on(m => { if (m.sessionId === sessionId && m.method === 'Runtime.executionContextCreated') contexts.push(m.params.context); });
      try {
        await browser.send('Runtime.enable', {}, sessionId); await sleep(300);
        for (const ctx of contexts) {
          const r = await browser.send('Runtime.evaluate', { expression, contextId: ctx.id, returnByValue: true, awaitPromise: true }, sessionId).catch(() => null);
          if (r?.result && r.result.value !== undefined && !r.exceptionDetails) return r.result.value;
        }
      } finally { await browser.send('Target.detachFromTarget', { sessionId }).catch(() => {}); }
    }
    return undefined;
  } finally { browser.close(); }
}

// Evaluate inside the Lean infoview document only (it contains the "Tactic state"/goal UI).
export const infoviewEval = (vs, expression) => webviewEval(vs,
  `(() => { if (!document.querySelector('.vscode-light, .vscode-dark, body') || !document.body.innerText.match(/Tactic state|No info found|Messages|All Messages/)) return undefined; return (${expression}); })()`);
