import { chromium } from 'playwright-core';
const APP='http://127.0.0.1:3000', API='http://127.0.0.1:8081/api';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const login=async u=>(await(await fetch(API+'/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:u,password:'123456'})})).json()).token;
const j=async(p,t)=>await(await fetch(API+p,{headers:{Authorization:'Bearer '+t}})).json();

const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
const page=await(await browser.newContext({viewport:{width:1280,height:800}})).newPage();
await page.addInitScript(t=>localStorage.setItem('token',t), await login('alice'));
await page.goto(APP,{waitUntil:'domcontentloaded'});
await page.waitForSelector('flt-semantics-placeholder',{timeout:30000});
await sleep(7000);
await page.evaluate(()=>{const ph=document.querySelector('flt-semantics-placeholder'); if(ph) ph.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true}));});
await sleep(1200);

// 1) 打开个人设置（点左下角用户栏）
await page.mouse.click(180, 912 < 800 ? 750 : 750);  // 用户栏区域（视口 800 高）
await page.mouse.click(180, 755);
await sleep(1500);
await page.screenshot({path:'shots/E0-settings.png'});

// 2) 切到 general 频道，输入 @ 触发补全
const gen = page.getByText('general', { exact: true }).first();
if (await gen.count() > 0) { await gen.click({ force: true }); await sleep(2000); }
await page.mouse.click(640, 745);
await page.keyboard.type('hello @bo', { delay: 60 });
await sleep(900);
await page.screenshot({path:'shots/E1-mention-complete.png'});
// Enter 选中第一个候选并发送
await page.keyboard.press('Enter');   // 选中 bob
await sleep(300);
await page.keyboard.press('Enter');   // 发送
await sleep(2500);
await page.screenshot({path:'shots/E2-mention-sent.png'});
console.log('OK');
await browser.close();
