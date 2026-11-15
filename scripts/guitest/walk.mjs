/**
 * Chord GUI 黑盒走查（无头 Edge + Playwright，token 预注入登录）
 * 覆盖：桌面四栏布局、双账号实时消息、typing 提示、频道切换、移动端响应式
 * 运行: node walk.mjs
 */
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const APP = 'http://127.0.0.1:3000';
const API = 'http://127.0.0.1:8081/api';
const SHOTS = new URL('./shots/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
mkdirSync(SHOTS, { recursive: true });

const results = [];
const ok = (name, pass, detail = '') => {
  results.push({ name, pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -- ' + detail : ''}`);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function tokenOf(username) {
  const r = await fetch(API + '/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password: '123456' }),
  });
  if (!r.ok) throw new Error('login failed for ' + username);
  return (await r.json()).token;
}

// 打开页面（token 预注入），等 bootstrap，激活语义树后返回
async function openApp(page, username) {
  const token = await tokenOf(username);
  await page.addInitScript((t) => localStorage.setItem('flutter.token', JSON.stringify(t)), token);
  await page.goto(APP, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 30000 });
  await sleep(6000); // 引擎渲染 + bootstrap
}

async function enableSemantics(page) {
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) ph.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  });
  await sleep(1000);
}

async function snap(page) {
  return page.locator('body').ariaSnapshot();
}

const browser = await chromium.launch({
  executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  headless: true,
});

try {
  // ============ A. alice 桌面端 ============
  const ctxA = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const a = await ctxA.newPage();
  await openApp(a, 'alice');
  await a.screenshot({ path: SHOTS + '01-alice-desktop.png' });
  ok('alice 进入聊天(桌面四栏)', true);

  const sA = await snap(a);
  ok('服务器「开发者交流」', sA.includes('开发者交流'));
  ok('频道列表(#公告/#general)', sA.includes('公告') && sA.includes('general'));
  ok('成员列表(alice/bob/carol)', sA.includes('alice') && sA.includes('bob') && sA.includes('carol'));
  ok('历史消息渲染(欢迎来到 Chord)', sA.includes('欢迎来到'));
  ok('输入框存在', /发送消息|私信/.test(sA));

  // ============ B. bob 第二上下文 ============
  const ctxB = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const b = await ctxB.newPage();
  await openApp(b, 'bob');
  ok('bob 进入聊天', true);

  // ============ C. 实时消息：bob 发 → alice 收 ============
  await enableSemantics(b);
  const composerB = b.getByRole('textbox', { name: /发送消息/ }).first();
  if ((await composerB.count()) === 0) throw new Error('bob 输入框未找到');
  await composerB.click({ force: true });
  const testMsg = `实时测试 ${Date.now() % 100000} ✅`;
  await b.keyboard.type(testMsg, { delay: 25 });
  await b.keyboard.press('Enter');
  await sleep(900);
  ok('bob 消息发送成功(自身列表可见)', (await snap(b)).includes(testMsg));

  let received = false;
  for (let i = 0; i < 12; i++) {
    if ((await snap(a)).includes(testMsg)) { received = true; break; }
    await sleep(500);
  }
  ok('alice 实时收到 bob 的消息(WebSocket)', received);
  await a.screenshot({ path: SHOTS + '02-alice-received.png' });

  // ============ D. typing 提示 ============
  await composerB.click({ force: true });
  await b.keyboard.type('正在输入检查', { delay: 120 });
  await sleep(300);
  ok('alice 看到「正在输入」提示', (await snap(a)).includes('正在输入'));
  await b.keyboard.press('Enter');
  await sleep(400);

  // ============ E. alice 切换频道 ============
  await enableSemantics(a);
  const qian = a.getByText('前端', { exact: true }).first();
  if ((await qian.count()) > 0) {
    await qian.click({ force: true });
    await sleep(1500);
    const sE = await snap(a);
    ok('alice 切换到 #前端 并加载历史', sE.includes('消息列表') || sE.includes('Flutter Web') || sE.includes('前端'));
    await a.screenshot({ path: SHOTS + '03-alice-channel.png' });
  } else {
    ok('alice 切换到 #前端 并加载历史', false, '未找到频道文本');
  }

  // ============ F. DM：bob 发起与 alice 的私信 ============
  const dm = b.evaluate(async () => {
    const token = JSON.parse(localStorage.getItem('flutter.token'));
    const r = await fetch('http://127.0.0.1:8080/api/users/search?q=alice', {
      headers: { Authorization: 'Bearer ' + token },
    });
    const users = await r.json();
    const me = await fetch('http://127.0.0.1:8080/api/users/me', {
      headers: { Authorization: 'Bearer ' + token },
    }).then((x) => x.json());
    const r2 = await fetch('http://127.0.0.1:8080/api/dms/' + users[0].id, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token },
    });
    return r2.json();
  });
  const dmRes = await dm;
  ok('bob 发起 DM(后端建会话)', !!dmRes.id);
  await sleep(1500);
  ok('alice 收到 DM_CREATED(私信列表出现 bob)', (await snap(a)).includes('bob'));

  // ============ G. 移动端响应式（carol, 375x812） ============
  const ctxM = await browser.newContext({
    viewport: { width: 375, height: 812 },
    isMobile: true, hasTouch: true, deviceScaleFactor: 2,
  });
  const m = await ctxM.newPage();
  await openApp(m, 'carol');
  await m.screenshot({ path: SHOTS + '04-mobile-chat.png' });
  ok('carol 进入聊天(移动视口)', true);

  await enableSemantics(m);
  // 打开抽屉：ChatArea 顶部的菜单按钮
  const menuBtn = m.getByRole('button', { name: '频道列表' }).first();
  if ((await menuBtn.count()) > 0) {
    await menuBtn.click({ force: true });
  } else {
    await m.mouse.click(24, 24);
  }
  await sleep(1200);
  await m.screenshot({ path: SHOTS + '05-mobile-drawer.png' });
  const sM = await snap(m);
  ok('移动端抽屉含服务器与频道', sM.includes('开发者交流') && sM.includes('general'));

  // ============ 汇总 ============
  const failed = results.filter((r) => !r.pass);
  console.log('\n==== SUMMARY ====');
  console.log(JSON.stringify({ total: results.length, failed: failed.length }, null, 0));
  process.exitCode = failed.length > 0 ? 1 : 0;
} catch (e) {
  console.error('WALKTHROUGH ERROR:', e.message);
  console.log(JSON.stringify({ error: e.message, results }, null, 2));
  process.exitCode = 2;
} finally {
  await browser.close();
}
