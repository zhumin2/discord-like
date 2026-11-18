// 验证登录页底部显示「客户端 <版本> ｜ 服务器 <版本>」，且与 /api/health 一致。
import { chromium } from 'playwright-core';
const APP = 'http://127.0.0.1:3000';
const API = 'http://127.0.0.1:8081';
const sleep = ms => new Promise(r => setTimeout(r, ms));

const health = await (await fetch(API + '/api/health')).json();
console.log('API /api/health:', JSON.stringify(health));

const browser = await chromium.launch({
  executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  headless: true,
});
const page = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();
// 干净上下文：不带 token，停在登录页
await page.goto(APP, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('flt-semantics-placeholder', { timeout: 30000 });
await sleep(5000);
await page.evaluate(() => {
  const ph = document.querySelector('flt-semantics-placeholder');
  if (ph) ph.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
});
await sleep(2000);

const labels = await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach(el => {
    const t = (el.getAttribute('aria-label') || '') + ' ' + (el.textContent || '');
    if (t.trim()) out.push(t.trim());
  });
  return out;
});
const joined = labels.join('\n');
const hit = labels.filter(l => l.includes('客户端') && l.includes('服务器'));
console.log('版本行命中:', JSON.stringify(hit));
console.log('期望客户端含:', health.version);
await page.screenshot({ path: 'shots/version-login.png' });
await browser.close();
if (hit.length === 0) {
  console.log('FAIL: 登录页未找到版本行');
  process.exit(1);
}
if (!hit.some(l => l.includes(health.version))) {
  console.log('FAIL: 版本行内容与 /api/health 不一致');
  process.exit(1);
}
console.log('PASS');
