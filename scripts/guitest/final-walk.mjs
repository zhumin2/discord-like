/**
 * Chord 最终 GUI 走查：坐标交互 + 截图留档
 */
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const APP = 'http://127.0.0.1:3000';
const API = 'http://127.0.0.1:8081/api';
const SHOTS = new URL('./shots/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
mkdirSync(SHOTS, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function tokenOf(username) {
  const r = await fetch(API + '/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password: '123456' }),
  });
  return (await r.json()).token;
}

async function openApp(page, username) {
  const token = await tokenOf(username);
  await page.addInitScript((t) => localStorage.setItem('flutter.token', JSON.stringify(t)), token);
  await page.goto(APP, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 30000 });
  await sleep(6000);
}

async function typeMessage(page, text) {
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) ph.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  });
  await sleep(800);
  // 点击输入框区域（底部输入框中心）
  const vp = page.viewportSize();
  await page.mouse.click(vp.width / 2, vp.height - 46);
  await sleep(500);
  await page.keyboard.type(text, { delay: 25 });
  await page.keyboard.press('Enter');
  await sleep(900);
}

const browser = await chromium.launch({
  executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  headless: true,
});

try {
  // ---- A. alice 桌面 ----
  const ctxA = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const a = await ctxA.newPage();
  await openApp(a, 'alice');
  await a.screenshot({ path: SHOTS + '10-desktop-alice.png' });
  console.log('shot 10 desktop alice');

  // ---- B. bob 发消息 ----
  const ctxB = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const b = await ctxB.newPage();
  await openApp(b, 'bob');
  const msg = `最终验收 ${Date.now() % 100000} 🎉`;
  await typeMessage(b, msg);
  await b.screenshot({ path: SHOTS + '11-desktop-bob-sent.png' });
  console.log('shot 11 bob sent');
  await sleep(1200);
  await a.screenshot({ path: SHOTS + '12-desktop-alice-received.png' });
  console.log('shot 12 alice received');

  // ---- C. alice 切换到 #前端（坐标点击第二栏） ----
  await a.mouse.click(140, 360); // #前端
  await sleep(1500);
  await a.screenshot({ path: SHOTS + '13-desktop-alice-frontend.png' });
  console.log('shot 13 channel switch');

  // ---- D. bob 输入中 → alice 截图（typing 提示） ----
  const vpB = b.viewportSize();
  await b.mouse.click(vpB.width / 2, vpB.height - 46);
  await b.keyboard.type('typing indicator check', { delay: 150 });
  await sleep(500);
  await a.screenshot({ path: SHOTS + '14-desktop-typing.png' });
  await b.keyboard.press('Enter');
  console.log('shot 14 typing');

  // ---- E. carol 移动端 ----
  const ctxM = await browser.newContext({
    viewport: { width: 375, height: 812 },
    isMobile: true, hasTouch: true, deviceScaleFactor: 2,
  });
  const m = await ctxM.newPage();
  await openApp(m, 'carol');
  await m.screenshot({ path: SHOTS + '15-mobile-chat.png' });
  console.log('shot 15 mobile chat');
  await m.mouse.click(64, 47); // ☰ 打开抽屉
  await sleep(1200);
  await m.screenshot({ path: SHOTS + '16-mobile-drawer.png' });
  console.log('shot 16 mobile drawer');
  // 关闭抽屉，点成员按钮
  await m.mouse.click(340, 400);
  await sleep(800);
  await m.mouse.click(550, 47); // 👥 成员
  await sleep(1000);
  await m.screenshot({ path: SHOTS + '17-mobile-members.png' });
  console.log('shot 17 mobile members');

  console.log('ALL SHOTS DONE');
  await browser.close();
} catch (e) {
  console.error('ERROR:', e.message);
  await browser.close();
  process.exitCode = 2;
}
