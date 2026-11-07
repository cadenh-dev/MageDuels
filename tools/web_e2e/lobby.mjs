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
  await Promise.all(pages.map(p => p.goto(`${baseUrl}${baseUrl.includes('?') ? '&' : '?'}netdebug=1`, { waitUntil: 'domcontentloaded' })));
  await Promise.all(pages.map(p => p.waitForTimeout(1200)));
  await screenshot('loaded');
  // First click unlocks the game canvas and audio, then open Online.
  await click(pages[0], 640, 700);
  await click(pages[1], 640, 700);
  await click(pages[0], 639, 482);
  await click(pages[1], 639, 482);
  await screenshot('online');
  const hostConnectTime = await waitFor(() => consoleLogs.A.some(x => x.includes('transport connected signal')), 'host GD-Sync connection');
  const joinConnectTime = await waitFor(() => consoleLogs.B.some(x => x.includes('transport connected signal')), 'joiner GD-Sync connection');
  await pages[0].bringToFront();
  await click(pages[0], 541, 315);
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
  console.log(JSON.stringify({ result, code, connectHostMs: hostConnectTime - start, connectJoinMs: joinConnectTime - start, hostCodeMs: codeTime - hostConnectTime, matchMs: matchTime - start }));
} catch (error) {
  await screenshot('failure').catch(() => {});
  console.error(error.stack || error);
} finally {
  await fs.writeFile(logFile, JSON.stringify({ result, url: baseUrl, durationMs: Date.now() - start, consoleLogs }, null, 2));
  await Promise.all(contexts.map(c => c.close()));
  await browser.close();
}
if (result !== 'pass') process.exitCode = 1;
