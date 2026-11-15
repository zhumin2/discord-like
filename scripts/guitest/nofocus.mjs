import { chromium } from 'playwright-core';

const APP = 'http://127.0.0.1:3000';
const API = 'http://127.0.0.1:8081/api';

// 通过 API 拿 alice 的 token，预注入 localStorage，避免触碰任何输入框
const loginResp = await fetch(API + '/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'alice', password: '123456' }),
});
const { token } = await loginResp.json();
console.log('token ok:', token.slice(0, 15));

const browser = await chromium.launch({
  executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  headless: true,
});
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
await page.addInitScript((t) => localStorage.setItem('flutter.token', JSON.stringify(t)), token);
await page.goto(APP, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('flt-semantics-placeholder', { timeout: 30000 });
await page.waitForTimeout(10000);
await page.screenshot({ path: new URL('./shots/no-focus-view.png', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1') });
console.log('done');
await browser.close();
