import { chromium } from 'playwright-core';

const APP = 'http://127.0.0.1:3000';
const browser = await chromium.launch({
  executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  headless: true,
});
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
await page.goto(APP, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('flt-semantics-placeholder', { timeout: 30000 });
await page.waitForTimeout(5000);

// 登录：坐标点击（无语义树，模拟真实用户）
await page.mouse.click(640, 394);
await page.keyboard.type('alice', { delay: 30 });
await page.mouse.click(640, 484);
await page.keyboard.type('123456', { delay: 30 });
await page.keyboard.press('Enter');
await page.waitForTimeout(9000);
await page.screenshot({ path: new URL('./shots/user-view-1.png', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1') });
console.log('done');
await browser.close();
