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

// 1) 设置对话框：点左下角用户名文本（alice 在 y≈790）
await page.mouse.click(150, 790);
await sleep(1500);
await page.screenshot({path:'shots/E5-settings.png'});

// 关闭（若开着）
await page.mouse.click(1150, 520);
await sleep(600);

// 2) @ 补全
await page.mouse.click(640, 745);
await page.keyboard.type('在吗 @bo', { delay: 60 });
await sleep(900);
await page.screenshot({path:'shots/E6-mention.png'});
console.log('OK');
await browser.close();
