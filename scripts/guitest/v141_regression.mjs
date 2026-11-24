// v1.4.1 回归验证：12 项反馈的 Web 端到端走查（无头 Edge）。
// 覆盖：默认频道/被@高亮/搜索范围与右对齐/齿轮与删除/禁言图标/编辑回车/
//       跨作者选择/粘贴与拖放文件/取消选择文件无报错。
import { chromium } from 'playwright-core';

const APP = 'http://127.0.0.1:3000';
const API = 'http://127.0.0.1:8081/api';
const SHOTS = new URL('./shots/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let failures = 0;
function check(cond, msg) {
  if (cond) {
    console.log('PASS  ' + msg);
  } else {
    failures++;
    console.log('FAIL  ' + msg);
  }
}

async function api(method, path, token, body) {
  const r = await fetch(API + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await r.text();
  if (r.status >= 400) throw new Error(`${method} ${path} -> ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

async function register(username) {
  const r = await api('POST', '/auth/register', null, { username, password: '123456' });
  return { token: r.token, id: r.user.id };
}

// 语义节点文本（aria-label / 直接文本子节点 / 整棵子树的 textContent）
async function labels(page) {
  return page.evaluate(() => {
    const out = [];
    document.querySelectorAll('flt-semantics').forEach((el) => {
      const a = (el.getAttribute('aria-label') || '').trim();
      let own = '';
      el.childNodes.forEach((n) => {
        if (n.nodeType === 3) own += n.textContent;
      });
      own = own.trim();
      if (a || own) out.push(a + '|' + own);
    });
    return out;
  });
}
async function hasText(page, s) {
  if ((await labels(page)).some((x) => x.includes(s))) return true;
  return page.evaluate((s) => (document.body.textContent || '').includes(s), s);
}
// 任意节点的 textContent 是否包含（消息列表这类没有 aria-label 的容器）
async function hasContent(page, s) {
  return page.evaluate((s) => document.body.textContent.includes(s), s);
}
// 按 aria-label / 直接文本匹配，取面积最小的节点（避免命中 0,0,1280,800 的根容器）
async function rectOf(page, s, { xMax = null, xMin = null, exact = false } = {}) {
  return page.evaluate(
    ({ s, xMax, xMin, exact }) => {
      let best = null;
      document.querySelectorAll('flt-semantics').forEach((el) => {
        const a = (el.getAttribute('aria-label') || '').trim();
        let own = '';
        el.childNodes.forEach((n) => {
          if (n.nodeType === 3) own += n.textContent;
        });
        own = own.trim();
        const hit = exact
          ? a === s || own === s
          : a.includes(s) || own.includes(s);
        if (!hit) return;
        const r = el.getBoundingClientRect();
        if (r.width < 3 || r.height < 3) return;
        if (xMax != null && r.x > xMax) return;
        if (xMin != null && r.x < xMin) return;
        if (!best || r.width * r.height < best.w * best.h) {
          best = { x: r.x, y: r.y, w: r.width, h: r.height };
        }
      });
      return best;
    },
    { s, xMax, xMin, exact },
  );
}
// 消息行：textContent 含指定文字、高度像一行消息、位于聊天区
async function messageRect(page, s) {
  return page.evaluate((s) => {
    let best = null;
    document.querySelectorAll('flt-semantics').forEach((el) => {
      if (!(el.textContent || '').includes(s)) return;
      const r = el.getBoundingClientRect();
      if (r.height < 20 || r.height > 140 || r.x < 300 || r.width < 200) return;
      if (!best || r.width * r.height < best.w * best.h) {
        best = { x: r.x, y: r.y, w: r.width, h: r.height };
      }
    });
    return best;
  }, s);
}
async function clickLabel(page, s, opts = {}) {
  const r = await rectOf(page, s, opts);
  if (!r) return false;
  await page.mouse.click(r.x + r.w / 2, r.y + r.h / 2);
  return true;
}
async function clickRect(page, r) {
  await page.mouse.click(r.x + r.w / 2, r.y + r.h / 2);
}

// 点击输入框并确认它成为当前编辑元素（SnackBar 等浮层可能挡住点击）。
async function focusComposer(page) {
  for (let i = 0; i < 6; i++) {
    await page.mouse.click(560, 762);
    await sleep(500);
    const active = await page.evaluate(
      () => (document.activeElement ? document.activeElement.tagName : ''));
    if (active === 'TEXTAREA') return true;
    await sleep(400);
  }
  return false;
}

async function openApp(page, token) {
  await page.addInitScript((t) => localStorage.setItem('token', t), token);
  await page.goto(APP, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 30000 });
  await sleep(5000);
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) ph.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  });
  await sleep(1500);
}

// ---------------- 测试数据准备 ----------------
const tag = Date.now().toString(36).slice(-5);
const taName = 'ta' + tag;
const tbName = 'tb' + tag;
const ta = await register(taName);
const tb = await register(tbName);
console.log(`测试用户: ${taName} / ${tbName}`);

const g = await api('POST', '/guilds', ta.token, { name: '回归' + tag });
const guild = g.guild;
const chans = g.channels;
const general = chans.find((c) => c.speakMode === 'all');
const announce = chans.find((c) => c.speakMode === 'owner');
console.log('默认频道:', chans.map((c) => `${c.name}:${c.speakMode}`).join(', '));
check(!!general, '5 新服务器默认包含「所有人可发言」频道（general）');
check(!!announce && announce.speakMode === 'owner', '5 公告频道默认仅创建者可发言');

const inv = await api('POST', `/guilds/${guild.id}/invites`, ta.token, {});
await api('POST', `/invites/${inv.inviteCode}/join`, tb.token, {});

async function send(token, channelId, content) {
  await api('POST', `/channels/${channelId}/messages`, token, { content });
  await sleep(1150);
}
await send(tb.token, general.id, `${tbName} 第一条 hello`);
await send(ta.token, general.id, `${taName} 第一条 hello`);
await send(tb.token, general.id, `@${taName} 这条应该高亮`);
await send(ta.token, general.id, `${taName} 可编辑的消息`);
await send(ta.token, announce.id, '公告关键词UNIQV141');

const muteCh = await api('POST', `/guilds/${guild.id}/channels`, ta.token,
  { name: '禁言演示', category: '测试', ownerOnly: true });
const delCh = await api('POST', `/guilds/${guild.id}/channels`, ta.token,
  { name: '待删除频道', category: '测试' });
console.log('测试频道:', muteCh.name, delCh.name);

// ---------------- GUI ----------------
const browser = await chromium.launch({
  executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  headless: true,
});
const ctx = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  permissions: ['clipboard-read', 'clipboard-write'],
});
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));

try {
  await openApp(page, ta.token);
  await page.screenshot({ path: SHOTS + 'v141-0-landing.png' });

  // 5) 默认落在 general（可发言），不是公告
  check(await hasText(page, '#general'), '5 新建服务器默认落在 #general');
  check(!(await hasText(page, '此频道仅特定成员可发言')), '5 落地页不是受限频道');

  // 6) 搜索按钮右对齐
  const searchRect = await rectOf(page, '搜索消息');
  console.log('搜索按钮 rect:', JSON.stringify(searchRect));
  check(!!searchRect && searchRect.x > 800, '6 顶部搜索按钮位于右侧（x > 800）');

  // 7) 搜索范围：默认本频道；切全服务器能搜到公告频道
  check(await clickLabel(page, '搜索消息'), '7 打开搜索弹窗');
  await sleep(1000);
  await page.screenshot({ path: SHOTS + 'v141-1-search.png' });
  check(await hasText(page, '本频道'), '7 搜索弹窗有「本频道/全服务器」范围切换');
  await page.keyboard.type('公告关键词', { delay: 30 });
  await sleep(1600);
  check(await hasText(page, '没有找到'), '7 本频道范围搜不到公告频道里的消息');
  await page.screenshot({ path: SHOTS + 'v141-2-search-channel.png' });
  check(await clickLabel(page, '全服务器'), '7 切换到全服务器');
  await sleep(1600);
  check(await hasText(page, '#公告'), '7 全服务器范围能搜到 #公告 的消息');
  check(await hasText(page, 'UNIQV141'), '7 搜索结果包含关键词摘要');
  await page.screenshot({ path: SHOTS + 'v141-3-search-all.png' });
  await clickLabel(page, '关闭');
  await sleep(1400);

  // 1) 被 @ 的消息整行高亮（截图 + 文本存在）
  check(await hasContent(page, '这条应该高亮'), '1 被 @ 的消息存在');
  await page.screenshot({ path: SHOTS + 'v141-4-mention.png' });

  // 4) 跨作者选择：从较早消息向下拖到较新消息（浏览器里向上拖有时只选中一行）
  const older = await messageRect(page, `${taName} 第一条 hello`);
  const newer = await messageRect(page, '这条应该高亮');
  console.log('selection rects:', JSON.stringify({ older, newer }));
  if (older && newer) {
    await page.mouse.move(older.x + 60, older.y + 34);
    await sleep(300);
    await page.mouse.down();
    await sleep(150);
    // 先向下进入目标消息，再在同一行内水平移动——纯垂直拖动时 Flutter
    // 的选区终点不会跨到下一个 RichText（真实用户斜向拖动不受影响）
    await page.mouse.move(older.x + 80, newer.y + 20);
    await sleep(60);
    await page.mouse.move(400, newer.y + 34);
    await sleep(60);
    await page.mouse.move(500, newer.y + 34);
    await sleep(60);
    await page.mouse.move(600, newer.y + 34);
    await sleep(60);
    await page.mouse.up();
    await sleep(900);
    const copyLabel = (await labels(page)).find((l) => l.includes('复制所选'));
    console.log('复制按钮:', copyLabel);
    check(!!copyLabel, '4 跨作者拖选后出现「复制所选」按钮');
    await page.screenshot({ path: SHOTS + 'v141-5-selection.png' });
    if (copyLabel) {
      await clickLabel(page, '复制所选');
      await sleep(1000);
      const clip = await page.evaluate(() => navigator.clipboard.readText());
      console.log('剪贴板内容:\n' + clip);
      check(clip.includes(`${taName} 第一条 hello`), '4 复制内容包含较早作者的消息');
      check(clip.includes('这条应该高亮'), '4 复制内容包含较新作者的消息');
      check(clip.includes("\n"), '4 跨消息之间用换行分隔');
      // 「已复制选中内容」的 SnackBar 会覆盖输入框区域，等它消失再继续
      for (let i = 0; i < 12; i++) {
        if (!(await hasText(page, '已复制选中内容'))) break;
        await sleep(500);
      }
    }
  } else {
    check(false, '4 找不到用于拖选的消息文本位置');
  }

  // 3/8) 编辑：回车保存；编辑中移动鼠标不丢焦点
  await page.mouse.move(700, 300);
  await sleep(600);
  const target = await messageRect(page, `${taName} 可编辑的消息`);
  check(!!target, '3/8 找到自己的消息');
  if (target) {
    await page.mouse.move(target.x + 40, target.y + target.h / 2);
    await sleep(600);
    const editBtn = await rectOf(page, '编辑', { exact: true });
    console.log('编辑按钮 rect:', JSON.stringify(editBtn));
    if (editBtn) {
      await clickRect(page, editBtn);
      await sleep(800);
      // 编辑器已打开：TEXTAREA 的当前值应为原消息内容（提示语在 canvas 上，语义树取不到）
      let editorVal = '';
      for (let i = 0; i < 10; i++) {
        editorVal = await page.evaluate(() => {
          const t = [...document.querySelectorAll('textarea')]
              .find((x) => x.value.includes('可编辑的消息'));
          return t ? t.value : '';
        });
        if (editorVal) break;
        await sleep(300);
      }
      check(!!editorVal, '3 编辑器打开并预填原消息内容');
      const editorActive = await page.evaluate(
        () => document.activeElement && document.activeElement.tagName);
      console.log('编辑时 activeElement:', editorActive);
      await page.screenshot({ path: SHOTS + 'v141-6-editor.png' });
      // 鼠标移开再回来（验证 hover 不会重建输入框/丢焦点）
      await page.mouse.move(700, 300);
      await sleep(300);
      await page.mouse.move(target.x + 40, target.y + target.h / 2);
      await sleep(300);
      const stillActive = await page.evaluate(
        () => document.activeElement && document.activeElement.tagName);
      check(stillActive === 'TEXTAREA', '8 鼠标移动后编辑框仍保持焦点');
      await page.keyboard.type(' EDITED', { delay: 30 });
      await page.keyboard.press('Enter');
      // 回车保存：轮询消息（WS 广播 + 历史接口）
      let edited = false;
      for (let i = 0; i < 12; i++) {
        await sleep(500);
        const list = await api('GET', `/channels/${general.id}/messages`, ta.token);
        edited = list.some((m) => m.content.includes('EDITED'));
        if (edited) break;
      }
      check(edited, '3 回车保存了编辑内容（无换行提交）');
      await page.screenshot({ path: SHOTS + 'v141-7-edited.png' });
    } else {
      check(false, '3/8 未找到悬浮「编辑」按钮');
    }
  }

  // 2) 拖放文件 + 粘贴文件：各自触发上传，回车发送后可在历史消息里看到附件
  let uploads = 0;
  page.on('request', (r) => {
    if (r.url().includes('/api/upload')) uploads++;
  });
  page.on('response', (r) => {
    if (r.url().includes('/api/upload')) console.log('[upload resp]', r.status());
  });
  check(await focusComposer(page), '2 输入框获得焦点');
  await page.evaluate(() => {
    const dt = new DataTransfer();
    dt.items.add(new File(['drop file body'], 'drop141.txt', { type: 'text/plain' }));
    document.body.dispatchEvent(
      new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt }));
  });
  await sleep(2500);
  check(uploads >= 1, '2 拖放文件触发 /api/upload');
  await page.screenshot({ path: SHOTS + 'v141-8-drop.png' });
  let composerVal = '';
  for (let i = 0; i < 20; i++) {
    composerVal = await page.evaluate(() => {
      const t = document.querySelector('textarea');
      return t ? t.value : '';
    });
    if (composerVal.includes('drop141.txt')) break;
    await sleep(400);
  }
  console.log('拖放后输入框:', JSON.stringify(composerVal));
  check(composerVal.includes('drop141.txt'), '2 拖放后在输入框插入附件 Markdown');
  await page.keyboard.press('Enter');
  await sleep(1600);
  let msgs = await api('GET', `/channels/${general.id}/messages`, ta.token);
  check(msgs.some((m) => m.content.includes('drop141.txt')),
    '2 拖放的文件已作为附件消息发送');

  const beforePaste = uploads;
  await page.evaluate(() => {
    const dt = new DataTransfer();
    dt.items.add(new File(['paste file body'], 'paste141.txt', { type: 'text/plain' }));
    document.dispatchEvent(
      new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: dt }));
  });
  await sleep(2500);
  console.log('粘贴上传次数:', uploads, '(之前', beforePaste, ')');
  check(uploads > beforePaste, '2 粘贴文件触发 /api/upload');
  composerVal = '';
  for (let i = 0; i < 20; i++) {
    composerVal = await page.evaluate(() => {
      const t = document.querySelector('textarea');
      return t ? t.value : '';
    });
    if (composerVal.includes('paste141.txt')) break;
    await sleep(400);
  }
  console.log('粘贴后输入框:', JSON.stringify(composerVal));
  check(composerVal.includes('paste141.txt'), '2 粘贴后在输入框插入附件 Markdown');
  await page.keyboard.press('Enter');
  await sleep(1600);
  msgs = await api('GET', `/channels/${general.id}/messages`, ta.token);
  check(msgs.some((m) => m.content.includes('paste141.txt')),
    '2 粘贴的文件已作为附件消息发送');

  // 重新载入
  await page.reload({ waitUntil: 'domcontentloaded' });
  await sleep(5500);
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) ph.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  });
  await sleep(1200);

  // 9/11) 选中频道行上的齿轮 + 删除频道
  check(await clickLabel(page, '待删除频道', { exact: true }), '11 选中「待删除频道」');
  await sleep(800);
  const rowRect = await rectOf(page, '待删除频道', { exact: true });
  console.log('频道行 rect:', JSON.stringify(rowRect));
  const rowGear = await page.evaluate((row) => {
    let best = null;
    document.querySelectorAll('flt-semantics[role="button"]').forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.width < 8 || r.width > 60 || r.height < 8 || r.height > 60) return;
      if (r.x < 240 || r.x > 310) return;
      if (!row) return;
      if (r.y + r.height / 2 < row.y - 4 || r.y + r.height / 2 > row.y + row.h + 4) return;
      best = { x: r.x, y: r.y, w: r.width, h: r.height };
    });
    return best;
  }, rowRect);
  console.log('频道行齿轮 rect:', JSON.stringify(rowGear));
  check(!!rowGear, '9 选中的频道行显示设置齿轮');
  if (rowGear) {
    await clickRect(page, rowGear);
    await sleep(800);
    check(await hasText(page, '频道设置 · #待删除频道'), '9 点击频道行齿轮打开该频道设置');
    await page.screenshot({ path: SHOTS + 'v141-9-settings.png' });
    check(await clickLabel(page, '删除频道'), '11 设置弹窗有「删除频道」按钮');
    await sleep(1000);
    check((await rectOf(page, '删除', { exact: true })) !== null, '11 出现删除确认（有「删除」按钮）');
    check(await clickLabel(page, '删除', { exact: true }), '11 确认删除');
    await sleep(2000);
    check((await rectOf(page, '待删除频道', { exact: true })) === null, '11 频道已从列表移除');
    await page.screenshot({ path: SHOTS + 'v141-10-deleted.png' });
  }

  // 10) 禁言频道：成员列表出现静音提示（截图 + 语义 tooltip 文案）
  check(await clickLabel(page, '禁言演示'), '10 打开「禁言演示」频道');
  await sleep(1500);
  check(await hasText(page, '不能发言'), '10 被禁言成员出现静音提示（语义层）');
  await page.screenshot({ path: SHOTS + 'v141-11-muted.png' });

  // 12) 取消选择文件：不报错
  check(await clickLabel(page, 'general', { exact: true }), '12 回到 general');
  await sleep(1200);
  const chooserPromise = page.waitForEvent('filechooser', { timeout: 8000 }).catch(() => null);
  check(await clickLabel(page, '发送文件'), '12 点击「发送文件」');
  const chooser = await chooserPromise;
  console.log('filechooser:', !!chooser);
  if (chooser) {
    await chooser.setFiles([]); // 空数组 = 模拟用户取消
    await sleep(1800);
    const bad = (await labels(page)).filter((l) => l.includes('失败') || l.includes('错误'));
    console.log('取消后出现的错误提示:', bad);
    check(bad.length === 0, '12 取消选择文件后没有报错提示');
    await page.screenshot({ path: SHOTS + 'v141-12-cancel.png' });
    // 取消后仍可继续操作（按钮不会卡在转圈状态）
    const still = await clickLabel(page, '发送文件');
    check(still, '12 取消后附件按钮仍可再次点击');
  } else {
    check(false, '12 未弹出文件选择器（无法验证取消）');
  }
} catch (e) {
  failures++;
  console.log('EXCEPTION', e);
} finally {
  await browser.close();
}
console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
