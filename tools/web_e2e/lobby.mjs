import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const value = (name, fallback) => {
  const i = args.indexOf(name);
  return i < 0 ? fallback : args[i + 1];
};
const baseUrl = value('--url', 'http://127.0.0.1:8790/index.html');
const headed = args.includes('--headed');
const scenario = value('--scenario', 'mid');
if (!['before', 'mid', 'after'].includes(scenario)) throw new Error(`Unknown scenario: ${scenario}`);
const warmDelay = scenario === 'before' ? 5000 : 0;
const output = path.join(here, 'output');
await fs.mkdir(output, { recursive: true });

const browser = await chromium.launch({
  channel: 'chrome',
  headless: !headed,
  args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
});
const consoleLogs = { A: [], B: [] };
const contexts = await Promise.all(['A', 'B'].map(() => browser.newContext({ viewport: { width: 1280, height: 800 } })));
const pages = await Promise.all(contexts.map(c => c.newPage()));
const start = Date.now();
const deadline = start + 45000;
const logFile = path.join(output, `run-${new Date().toISOString().replaceAll(':', '-')}.json`);
let result = 'fail';

function listen(page, id) {
  page.on('console', msg => {
    const line = `[${((Date.now() - start) / 1000).toFixed(3)}s] ${msg.type()} ${msg.text()}`;
    consoleLogs[id].push(line);
    if (line.includes('[NET')) console.log(`${id}: ${line}`);
  });
  page.on('pageerror', err => consoleLogs[id].push(`PAGEERROR ${err.stack || err.message}`));
}
async function click(page, x, y) { await page.mouse.click(x, y); await page.waitForTimeout(400); }
async function screenshot(label) { await Promise.all(pages.map((p, i) => p.screenshot({ path: path.join(output, `${label}-${i ? 'B' : 'A'}.png`) }))); }
async function waitFor(fn, label) {
  while (Date.now() < deadline) {
    if (fn()) return Date.now();
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  throw new Error(`45 second limit exceeded waiting for ${label}`);
}

try {
  pages.forEach((p, i) => listen(p, i ? 'B' : 'A'));
  const query = `netdebug=1&warmdelay=${warmDelay}`;
  await Promise.all(pages.map(p => p.goto(`${baseUrl}${baseUrl.includes('?') ? '&' : '?'}${query}`, { waitUntil: 'domcontentloaded' })));
  await Promise.all(pages.map(p => p.waitForTimeout(scenario === 'before' ? 100 : scenario === 'mid' ? 0 : 1200)));
  if (scenario === 'before') {
    await waitFor(() => consoleLogs.A.some(line => line.includes('menu prewarm delayed')) && consoleLogs.B.some(line => line.includes('menu prewarm delayed')), 'menu ready before delayed prewarm');
  } else if (scenario === 'mid') {
    await waitFor(() => consoleLogs.A.some(line => line.includes('transport start_multiplayer called')) && consoleLogs.B.some(line => line.includes('transport start_multiplayer called')), 'prewarm handshake start');
  }
  await screenshot('loaded');
  // First click unlocks canvas input and audio.
  await click(pages[0], 640, 700);
  if (scenario === 'mid') {
    await click(pages[0], 639, 482);
    await click(pages[0], 541, 315);
    await waitFor(() => consoleLogs.A.some(line => line.includes('Hosting as soon as connected')), 'queued host status');
    if (consoleLogs.A.some(line => line.includes('transport connected signal'))) {
      throw new Error('Mid-handshake host click happened after relay connected');
    }
    await click(pages[1], 640, 700);
  } else {
    await click(pages[1], 640, 700);
  }
  if (scenario === 'after') {
    await waitFor(() => consoleLogs.A.some(line => line.includes('relay connected')), 'prewarm complete before opening Online');
    await waitFor(() => consoleLogs.B.some(line => line.includes('relay connected')), 'joiner prewarm complete before opening Online');
  }
  // Open Online before warm-up starts, during the handshake, or after relay-ready.
  if (scenario !== 'mid') await click(pages[0], 639, 482);
  await click(pages[1], 639, 482);
  await waitFor(() => consoleLogs.A.some(line => line.includes('online_screen ready')), 'host Online screen ready');
  if (scenario === 'before') {
    const readyIndex = consoleLogs.A.findIndex(line => line.includes('online_screen ready'));
    const startedIndex = consoleLogs.A.findIndex(line => line.includes('transport start_multiplayer called'));
    if (startedIndex >= 0 && readyIndex >= startedIndex) throw new Error('Before-prewarm scenario opened Online after prewarm started');
  }
  if (scenario === 'after' && !consoleLogs.A.some(line => line.includes('transport connected signal'))) {
    throw new Error('After-prewarm scenario opened Online before relay connected');
  }
  await screenshot('online');
  const hostConnectTime = await waitFor(() => consoleLogs.A.some(x => x.includes('transport connected signal')), 'host GD-Sync connection');
  const joinConnectTime = await waitFor(() => consoleLogs.B.some(x => x.includes('transport connected signal')), 'joiner GD-Sync connection');
  await pages[0].bringToFront();
  if (scenario !== 'mid') await click(pages[0], 541, 315);
  const codeTime = await waitFor(() => consoleLogs.A.some(line => /lobby_create.*code=([A-Z2-9]{5})/.test(line)), 'host room code');
  const codeLine = consoleLogs.A.find(line => /lobby_create.*code=([A-Z2-9]{5})/.test(line));
  const code = codeLine.match(/lobby_create.*code=([A-Z2-9]{5})/)[1];
  // Freeze the host renderer for the lobby wait, as a fully backgrounded tab can be.
  const hostCdp = await contexts[0].newCDPSession(pages[0]);
  await hostCdp.send('Page.setWebLifecycleState', { state: 'frozen' });
  await pages[1].bringToFront();
  await pages[1].mouse.click(595, 375);
  await pages[1].keyboard.type(code, { delay: 90 });
  await click(pages[1], 917, 375);
  await pages[1].waitForTimeout(1500);
  await hostCdp.send('Page.setWebLifecycleState', { state: 'active' });
  console.log('Host renderer resumed after 1.5s frozen lobby wait');
  const matchTime = await waitFor(() => consoleLogs.A.some(x => x.includes('session match started')) && consoleLogs.B.some(x => x.includes('session match started')), 'both match starts');
  result = 'pass';
  await screenshot('match');
  console.log(JSON.stringify({ result, scenario, code, connectHostMs: hostConnectTime - start, connectJoinMs: joinConnectTime - start, hostCodeMs: codeTime - hostConnectTime, matchMs: matchTime - start }));
} catch (error) {
  await screenshot('failure').catch(() => {});
  console.error(error.stack || error);
} finally {
  await fs.writeFile(logFile, JSON.stringify({ result, url: baseUrl, durationMs: Date.now() - start, consoleLogs }, null, 2));
  await Promise.all(contexts.map(c => c.close()));
  await browser.close();
}
if (result !== 'pass') process.exitCode = 1;
