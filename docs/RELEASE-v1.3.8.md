# Chord v1.3.8 发布说明

> 这一版集中修用户群反馈的 4 个问题：**改头像后聊天记录不刷新**、**服务器不能改名**、
> **@ 弹出框输入失焦 / Tab 无效**、**「无人（归档）」频道仍能发言**。
> 同时给被 @ 的人加了即时提示。

**在线体验（无需安装）**：http://129.226.159.168:3000
**演示账号**：`alice` / `bob` / `carol`，密码均为 `123456`；演示服务器邀请码 `demo2024`

---

## 一、本版更新

### 1. 改头像 / 改名后立即生效
以前改了头像或用户名，聊天记录里的旧头像要**重新登录**才会刷新。
现在无论自己改，还是看到别人改，消息列表、成员列表、私信、底部用户栏都会**即时更新**。

### 2. 服务器可以改名了
服务器所有者点频道栏顶部的 **⋮ → 服务器设置**，修改服务器名称保存即可；
其他成员会实时看到新名字。（频道改名在上一版已支持：频道行右侧齿轮。）

### 3. @ 提及修复
- 以前输入 `@` 之后输入框会**失去焦点**，后面的字打不进去、Tab 也没反应——已修复
- `@` 弹出候选后，**Tab 或 Enter** 选中第一个候选，点候选也可以
- 支持中文输入法的全角 `＠`
- **被 @ 提示**：别人在其它频道 @ 你时，右下角会弹出「xxx 在 #频道 提到了你」，
  左侧频道也会显示红色提及数

### 4. 「无人（归档）」频道彻底静音
把频道发言权限设为「无人（归档）」后，**包括服务器所有者在内任何人都不能发言**，
输入框会替换为「此频道仅特定成员可发言」并提示去其它频道。
（老频道的历史数据会自动修正权限为「所有人」，不会误显示锁标。）

---

## 二、下载

| 平台 | 文件 | 大小 | 说明 |
|---|---|---|---|
| **Android（主流手机）** | [`chord-arm64.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-arm64.apk) | 30 MB | 2016 年后的绝大多数机型，**优先选这个** |
| Android（老机型） | [`chord-armv7.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-armv7.apk) | 29 MB | 32 位老款手机 / 低端设备 |
| Android（全架构） | [`chord-universal.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-universal.apk) | 66 MB | 不确定架构时用，或用于模拟器 |
| **Windows 10/11（x64）** | [`chord-windows-x64.zip`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-windows-x64.zip) | 24 MB | 解压即用，免安装 |
| 网页 / PWA | 直接访问 http://129.226.159.168:3000 | — | 可用浏览器「添加到主屏幕」 |
| 服务器端部署包 | [`chord-deploy.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-deploy.tar.gz) | 33 MB | 自建服务器用，普通用户无需下载 |
| 网页端增量更新 | [`chord-web-update.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-web-update.tar.gz) | 19 MB | 已部署服务器的维护者用 |

> 所有客户端**已内置默认服务器地址**，打开即可连接，无需任何配置。

---

## 三、升级

### 普通用户

| 平台 | 做法 |
|---|---|
| Android | 下载 `chord-arm64.apk` 覆盖安装（登录态保留） |
| Windows | 解压新 zip 覆盖旧目录（`Chord聊天.exe`、`flutter_windows.dll`、`data` 必须在同一目录） |
| Web | 刷新页面即可（入口页强制回源，会自动拿到新版本） |

装好后可以在**登录页底部**或**个人资料对话框底部**核对版本：
`客户端 v1.3.8 ｜ 服务器 v1.3.8`。两边的版本号不一致就说明服务器端还没升级。

### 服务器维护者（本版前后端都改了）

```bash
sudo curl -fLo /opt/chord/update.sh https://github.com/zhumin2/discord-like/releases/latest/download/update.sh
sudo bash /opt/chord/update.sh server   # 新增 PATCH /guilds/:id；修正老频道 speak_mode
sudo bash /opt/chord/update.sh web
```

核对：`curl -s http://129.226.159.168:8081/api/health` 应返回 `"version":"v1.3.8"`。

---

## 四、此前几版已包含的能力（v1.3.x 回顾）

- **图片**：上传前自动压缩（长边 1600、目标 500KB 内）；头像按头像尺寸压缩到 320px；
  Windows/Web 支持 **Ctrl+V 粘贴图片**、图片悬停「复制图片」；聊天图片有本地缓存与占位符
- **频道权限**：所有人 / 仅创建者（公告）/ 创建者+指定成员 / 无人（归档）；创建时默认「公告频道」
- **消息**：引用回复、编辑（带确定按钮）、跨多条消息选择复制、按时间序稳定显示（多端同时发不乱序）
- **个人**：改用户名 / 头像 / 颜色、修改密码
- **体验**：发送中发送键转圈防连发、发言最小间隔 1 秒（防刷屏）、安卓导航栏适配状态栏、
  被 @ 提示、私信与频道未读/提及红色数字徽章

---

## 五、已知限制

- 服务器在新加坡，国内直连带宽有限：Web 首次加载约 4 MB 压缩资源，可能需要 10~60 秒
- APK 为 debug 签名、Windows 无代码签名，安装时出现「未知来源 / SmartScreen」提示属正常现象
- 桌面端点击关闭按钮是**最小化到托盘**，托盘菜单「退出」才真正退出
- 消息搜索、角色权限、语音频道仍在路线图中（见 `docs/ROADMAP.md`）
