import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const APP = 'http://127.0.0.1:3000';
mkdirSync(new URL('./shots/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'), { recursive: true });

const browser = await chromium.launch({
  executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  headless: true,
});
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
page.on('console', (m) => console.log('[console]', m.type(), m.text().slice(0, 120)));
page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));

await page.goto(APP, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('flt-semantics-placeholder', { timeout: 30000 });
await page.waitForTimeout(4000);

await page.screenshot({ path: new URL('./shots/debug-1-initial.png', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1') });

const info1 = await page.evaluate(() => ({
  placeholder: !!document.querySelector('flt-semantics-placeholder'),
  semanticsCount: document.querySelectorAll('flt-semantics').length,
  view: !!document.querySelector('flutter-view'),
}));
console.log('before focus:', JSON.stringify(info1));

await page.evaluate(() => {
  const ph = document.querySelector('flt-semantics-placeholder');
  // 引擎监听的是 click 事件（模拟辅助技术接入）
  ph.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
});
await page.waitForTimeout(2500);

const info2 = await page.evaluate(() => ({
  semanticsCount: document.querySelectorAll('flt-semantics').length,
  sample: [...document.querySelectorAll('flt-semantics')].slice(0, 12).map((s) => ({
    tag: s.tagName.toLowerCase(),
    role: s.getAttribute('role'),
    label: (s.getAttribute('aria-label') || '').slice(0, 24),
    rect: (() => { const r = s.getBoundingClientRect(); return [r.x | 0, r.y | 0, r.width | 0, r.height | 0].join('x'); })(),
  })),
}));
console.log('after focus:', JSON.stringify(info2, null, 1));

await page.screenshot({ path: new URL('./shots/debug-2-after.png', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1') });
await browser.close();
