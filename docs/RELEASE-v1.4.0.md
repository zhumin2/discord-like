# Chord v1.4.0 发布说明

> 这一版换上**全新品牌图标**，并带来两个等了很久的功能：**全服务器消息搜索**，
> 以及**点击跳转定位**（搜索结果、引用回复都能直接跳回原消息）。
> 另含上一版 v1.3.9 的**用户名唯一**修复（同名注册问题）。

**在线体验（无需安装）**：http://129.226.159.168:3000
**演示账号**：`alice` / `bob` / `carol`，密码均为 `123456`；演示服务器邀请码 `demo2024`

---

## 一、本版更新

### 1. 新 App 图标
白底 + 黑色椭圆 + 两个蓝色圆环的标志，已替换所有入口：

- Windows 任务栏 / exe 图标 / 托盘图标
- Android 桌面图标
- 网页 favicon、PWA 图标（主题色同步为标志蓝 `#75CDFD`）
- 应用内：登录页顶部、左侧服务器栏顶部

### 2. 消息搜索
- 入口：聊天区右上角 🔍（手机端在顶部导航栏）
- 搜索范围：**当前服务器的所有频道**
- 结果按时间倒序，显示 `#频道 · 作者 · 时间 · 内容摘要`，最多 50 条
- 输入即搜（350ms 防抖），中英文、`@提及`、表情都能搜

### 3. 点击跳转定位
- 点搜索结果 → 自动切到对应频道、加载上下文、滚动到该消息并**琥珀色高亮 2.5 秒**
- 点消息里的**引用块** → 同样跳回被引用的原消息（跨页也能定位）

### 4. 用户名的重名问题（v1.3.9）
- 注册/改名不能再占用已存在的用户名（大小写也算重复），返回「用户名已被占用，请换一个」
- 数据库唯一索引兜底，绕过客户端直接调接口也注册不出重名
- 历史遗留的重名会在服务启动时自动改名（保留最早注册者），改名记录见
  `journalctl -u chord-server | grep 重复用户名`

### 5. 其他
- Windows 任务栏/文件属性里的程序名从 `chord_client` 改为 **Chord**

---

## 二、下载

| 平台 | 文件 | 大小 | 说明 |
|---|---|---|---|
| **Android（主流手机）** | [`chord-arm64.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-arm64.apk) | 30.8 MB | 2016 年后的绝大多数机型，**优先选这个** |
| Android（老机型） | [`chord-armv7.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-armv7.apk) | 29.0 MB | 32 位老款手机 / 低端设备 |
| Android（全架构） | [`chord-universal.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-universal.apk) | 66.8 MB | 不确定架构时用，或用于模拟器 |
| **Windows 10/11（x64）** | [`chord-windows-x64.zip`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-windows-x64.zip) | 24.4 MB | 解压即用，免安装 |
| 网页 / PWA | 直接访问 http://129.226.159.168:3000 | — | 可用浏览器「添加到主屏幕」 |
| 服务器端部署包 | [`chord-deploy.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-deploy.tar.gz) | 32.5 MB | 自建服务器用，普通用户无需下载 |
| 网页端增量更新 | [`chord-web-update.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-web-update.tar.gz) | 19.3 MB | 已部署服务器的维护者用 |

> 所有客户端**已内置默认服务器地址**，打开即可连接，无需任何配置。

---

## 三、升级

### 普通用户

| 平台 | 做法 |
|---|---|
| Android | 下载 `chord-arm64.apk` 覆盖安装（登录态保留，桌面图标会变成新标志） |
| Windows | 解压新 zip 覆盖旧目录（`Chord聊天.exe`、`flutter_windows.dll`、`data` 必须同目录） |
| Web | 刷新页面即可；若图标还是旧的，强制刷新一次（Ctrl+F5）清掉 favicon 缓存 |

装好后在登录页底部核对：`客户端 v1.4.0 ｜ 服务器 v1.4.0`。

### 服务器维护者（本版前后端都改了）

```bash
sudo curl -fLo /opt/chord/update.sh https://github.com/zhumin2/discord-like/releases/latest/download/update.sh
sudo bash /opt/chord/update.sh server   # 搜索接口 + around 上下文 + 用户名唯一
sudo bash /opt/chord/update.sh web      # 新图标 + 搜索 UI
```

核对：`curl -s http://129.226.159.168:8081/api/health` 应返回 `"version":"v1.4.0"`。

---

## 四、版本链（v1.3.8 → v1.4.0）

| 版本 | 内容 |
|---|---|
| v1.3.8 | 头像/改名即时刷新、服务器改名、@ 输入失焦与 Tab 修复、归档频道禁止发言、被 @ 提示 |
| v1.3.9 | 用户名全局唯一（修复同名注册导致的数据混乱） |
| **v1.4.0** | **品牌图标、全服务器消息搜索、搜索结果/引用回复跳转定位、Windows 程序名** |

---

## 五、已知限制

- 搜索为 `LIKE` 级扫描（`INSTR`），万条以内很快；数据量再大需要上 MySQL ngram 全文索引
- 搜索结果固定最多 50 条，暂不支持分页
- 服务器在新加坡，国内直连带宽有限：Web 首次加载约 4 MB 压缩资源，可能需 10~60 秒
- APK 为 debug 签名、Windows 无代码签名，安装时出现「未知来源 / SmartScreen」提示属正常现象
- 桌面端点击关闭按钮是最小化到托盘，托盘菜单「退出」才真正退出

---

## 六、反馈

测试中发现问题请附：客户端版本（登录页底部）、服务器版本（同处或 `/api/health`）、
复现步骤、截图。版本号两边不一致时，先确认服务器端是否已升级。
