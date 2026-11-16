# Chord v1.1.0 发布说明

> **Chord** 是一个自托管的实时聊天社区——服务器、频道、消息、表情回应、私信、在线状态一应俱全，
> 中文界面、开箱即用。本版本新增**图片/文件上传**，并把网页首屏加载提速约 3 倍。

**在线体验（无需安装）**：http://129.226.159.168:3000
**演示账号**：`alice` / `bob` / `carol`，密码均为 `123456`；演示服务器邀请码 `demo2024`

---

## 一、下载

| 平台 | 文件 | 大小 | 说明 |
|---|---|---|---|
| **Android（主流手机）** | [`chord-arm64.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-arm64.apk) | 30 MB | 2016 年后的绝大多数机型，**优先选这个** |
| Android（老机型） | [`chord-armv7.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-armv7.apk) | 28 MB | 32 位老款手机 / 低端设备 |
| Android（全架构） | [`chord-universal.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-universal.apk) | 64 MB | 不确定架构时用，或用于模拟器 |
| **Windows 10/11（x64）** | [`chord-windows-x64.zip`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-windows-x64.zip) | 25 MB | 解压即用，免安装 |
| 网页 / PWA | 直接访问 http://129.226.159.168:3000 | — | 可用浏览器「添加到主屏幕」 |
| 服务器端部署包 | [`chord-deploy.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-deploy.tar.gz) | 43 MB | 自建服务器用，普通用户无需下载 |
| 网页端增量更新 | [`chord-web-update.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-web-update.tar.gz) | 27 MB | 已部署服务器的维护者用 |

> 所有客户端**已内置默认服务器地址**，打开即可连接，无需任何配置。

---

## 二、安装

### Android

1. 下载对应 APK（推荐 `chord-arm64.apk`）到手机
2. 点击安装，系统提示「未知来源/外部来源应用」时选择**允许**
   （这是个人分发应用的正常提示，不是病毒）
3. 若被手机管家拦截，选择「继续安装」

### Windows

1. 下载 `chord-windows-x64.zip` 并**完整解压**到任意文件夹
2. 双击 `Chord聊天.exe` 运行
3. ⚠️ **`Chord聊天.exe`、`flutter_windows.dll`、`data` 文件夹必须放在同一目录**，只拷 exe 无法运行
4. 首次运行若出现 SmartScreen 蓝色提示：点「更多信息」→「仍要运行」
   （安装包未购买代码签名证书，属正常现象）

### 网页 / PWA

浏览器打开 http://129.226.159.168:3000 。
首次加载需下载约 4 MB 压缩资源（服务器在新加坡，国内网络可能需要 10~60 秒），
之后走浏览器缓存，基本秒开。可点浏览器菜单「安装应用 / 添加到主屏幕」当作 App 使用。

---

## 三、首次使用

1. 打开客户端 → 选「登录」或「注册」
2. 想立刻体验：点**「使用演示账号 (alice / 123456)」**一键填入
3. 想自己注册：切到「注册」页，用户名 + 密码即可创建账号
4. 加入他人的服务器：让对方提供邀请码，在「添加服务器」里输入
5. 换服务器：登录页展开「服务器地址」，填入形如 `http://你的IP:8081` 后登录
   （Web 端会自动使用当前页面所在主机的 8081 端口）

---

## 四、这个版本带来了什么

### 🖼️ 图片与文件上传（全新）
- 聊天输入框左侧新增 📎 按钮：选文件自动上传并插入消息
- 图片直接在消息内显示（点击可全屏查看、双指/滚轮缩放）
- 其他文件（PDF / zip / 音频 / 视频 / 文档等）以可点击链接形式发送
- 单文件上限 10 MB；支持 jpg / png / gif / webp / svg / txt / pdf / zip / mp3 / mp4 等

### ⚡ 网页加载快 3 倍
- 服务端启用 gzip：主程序 2.9 MB → 0.9 MB，WebAssembly 渲染引擎同步压缩
- 调整缓存策略，升级后不会再出现「还是旧版本」的情况

### 🔐 服务端加固
- 登录/注册按 IP 限流，防止撞库与批量注册
- 发消息按用户限流（20 条 / 10 秒），防止刷屏
- 上传按用户限流（30 次 / 分钟）

### 🧪 质量
- 首次引入自动化测试（8 个用例，覆盖限流精确性、上传白名单、超大文件拒绝、路径穿越防护）

---

## 五、常见问题

**Q：手机安装时提示「未知来源应用，可能有害」？**
A：个人分发的 APK 都会有这个提示。确认是从本页面下载后，选择允许安装即可。

**Q：Windows 提示「Windows 已保护你的电脑」？**
A：未购买代码签名证书导致的 SmartScreen 提示。点「更多信息」→「仍要运行」。

**Q：网页打开很久还白屏？**
A：首次加载需跨境下载约 4 MB 资源。若超过 2 分钟仍白屏，请按 `Ctrl + F5` 强制刷新。

**Q：客户端提示「无法连接服务器，请检查服务地址」？**
A：检查网络能否访问 `129.226.159.168`，以及登录页「服务器地址」是否为
`http://129.226.159.168:8081`（客户端已内置，通常无需修改）。

**Q：图片显示「图片加载失败」？**
A：多为旧缓存所致，`Ctrl + F5` 强制刷新一次即可；若持续失败请反馈。

**Q：发的消息、上传的文件存在哪？**
A：在你的自托管服务器上（MySQL + `uploads/` 目录），不经过第三方。

---

## 六、自建服务器（进阶）

需要一台装了 MySQL 8 的 Linux 服务器（Redis 可选）：

```bash
curl -fLO https://github.com/zhumin2/discord-like/releases/latest/download/chord-deploy.tar.gz
tar xzf chord-deploy.tar.gz && cd package
sudo MYSQL_PASS='你的数据库root密码' bash install.sh
```

安装脚本会自动：部署到 `/opt/chord`、创建系统服务、建库、开防火墙、健康检查。
以后更新一条命令：

```bash
sudo bash /opt/chord/update.sh web     # 只更新网页端
sudo MYSQL_PASS='密码' bash /opt/chord/update.sh full   # 全量更新
```

详细说明见部署包内 `部署说明.md`，或仓库 `deploy/` 目录。

---

## 七、已知限制

- 目前为 **HTTP 明文传输**（HTTPS 反代配置已就绪，等域名上线）
- 尚未支持：语音频道、消息搜索、角色权限体系、推送通知（已在路线图中，见 `docs/ROADMAP.md`）
- APK 为调试签名，Windows 客户端无代码签名 —— 仅适合小范围/自用分发

---

## 八、反馈

问题、建议或 Bug 请提 issue：https://github.com/zhumin2/discord-like/issues
