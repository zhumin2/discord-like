import { chromium } from 'playwright-core';
const APP='http://127.0.0.1:3000', API='http://127.0.0.1:8081/api';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const login=async u=>(await(await fetch(API+'/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:u,password:'123456'})})).json()).token;

const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
const page=await(await browser.newContext({viewport:{width:1280,height:800}})).newPage();
await page.addInitScript(t=>localStorage.setItem('token',t), await login('alice'));
await page.goto(APP,{waitUntil:'domcontentloaded'});
await page.waitForSelector('flt-semantics-placeholder',{timeout:30000});
await sleep(7000);
await page.evaluate(()=>{const ph=document.querySelector('flt-semantics-placeholder'); if(ph) ph.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true}));});
await sleep(1200);

// 1) 用户栏点开设置（语义树找 alice 文本第一次出现在底部用户栏）
const userBar = page.getByText('alice', { exact: true }).last();
const box = await userBar.boundingBox();
console.log('用户栏 alice 位置:', box && JSON.stringify({x:Math.round(box.x),y:Math.round(box.y)}));
if (box) {
  await page.mouse.click(box.x + 30, box.y + 10);
  await sleep(1500);
  await page.screenshot({path:'shots/E3-settings-open.png'});
}

// 2) @ 补全：切到 general 再输入
const gen = page.getByText('general', { exact: true }).first();
await page.keyboard.press('Escape');
if (await gen.count() > 0) { await gen.click({ force: true }); await sleep(2000); }
await page.mouse.click(640, 760);
await page.keyboard.type('在吗 @bo', { delay: 60 });
await sleep(900);
await page.screenshot({path:'shots/E4-mention-popup.png'});
console.log('验证完成');
await browser.close();
