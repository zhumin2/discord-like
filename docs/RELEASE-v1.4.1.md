# Chord v1.4.1 发布说明

> 这一版换上**新品牌图标**（圆角矩形、橙色底板、线条加粗），并集中修复了上一版
> 用户反馈的 **12 项体验问题**：@ 提示、文件粘贴/拖放、编辑回车、跨消息复制、
> 搜索范围、频道权限与删除、禁言提示、选择文件取消报错等。

**在线体验（无需安装）**：http://129.226.159.168:3000
**演示账号**：`alice` / `bob` / `carol`，密码均为 `123456`；演示服务器邀请码 `demo2024`

---

## 一、新图标

- **圆角矩形底板**、橙色 `#FF8A3D`、浅橙描边；图形（黑椭圆 + 蓝环）描边加粗、整体放大
- 已替换所有入口：Windows 任务栏 / exe / 托盘、Android 桌面图标、网页 favicon 与
  PWA 图标（主题色同步为 `#FF8A3D`）、应用内登录页与服务器栏顶部
- PWA 的 maskable 图标使用满版橙底，避免被系统遮罩再切一次圆角

## 二、聊天与操作体验

### 1. @ 提醒更明显
- 被 @ 的消息**整行淡黄底 + 左侧橙色竖条**，常驻显示
- 当你在同一频道往上翻历史（不在最底部）时，右上角会弹一条「xx 提到了你」提示
- 中文输入法下的全角 `＠` 也能正确识别

### 2. 粘贴 / 拖放文件
- 在**资源管理器里 Ctrl+C 一个文件**，回到 Chord 按 **Ctrl+V** 即可上传
- 直接把文件**拖进窗口**也能上传（网页端与 Windows 客户端均支持）
- 图片仍会自动压缩；其他文件按附件发送，输入框插入 `[文件名](下载链接)`

### 3. 编辑消息
- 编辑框里**回车 = 保存**、**Shift+回车 = 换行**、**Esc = 取消**（输入法选词时不会误触）
- 鼠标在消息列表里移动不再导致输入框失焦（之前编辑到一半会丢输入点）

### 4. 跨消息选择复制
- 用鼠标从一条消息拖到另一条，即使作者不同也能连续选中
- 右下角固定「复制所选 N 字」按钮；复制结果按消息分行，不再混入昵称/时间
- 修复了「按钮显示 N 字，实际复制到剪贴板是空的」问题

### 5. 搜索
- 顶部🔍按钮**靠右对齐**（之前挤在中间）
- 搜索弹窗可切换 **本频道 / 全服务器**，默认只搜当前频道
- 点结果仍会跳转到原消息并高亮

### 6. 频道
- 新建服务器默认进入 **#general**（所有人可发言），公告频道默认**仅创建者可发言**
- 频道行的⚙️齿轮在**选中状态也显示**（不用先切到别的频道才能改）
- 频道设置里新增**「删除频道」**（频道创建者 / 服务器所有者可用）
- 成员列表对在当前频道**不能发言的成员**显示 🔇 静音图标（悬停可看原因）
- 修复「发言太快」提示出现后原文没有回到输入框的问题

### 7. 选择文件
- 点「发送文件」后按**取消**不再弹出报错，也不会卡在转圈状态

---

## 三、下载

| 平台 | 文件 |
|---|---|
| **Android（主流手机）** | [`chord-arm64.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-arm64.apk) |
| Android（老机型） | [`chord-armv7.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-armv7.apk) |
| Android（全架构） | [`chord-universal.apk`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-universal.apk) |
| **Windows 10/11（x64）** | [`chord-windows-x64.zip`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-windows-x64.zip) |
| 网页 / PWA | 直接访问 http://129.226.159.168:3000 |
| 服务器端部署包 | [`chord-deploy.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-deploy.tar.gz) |
| 网页端增量更新 | [`chord-web-update.tar.gz`](https://github.com/zhumin2/discord-like/releases/latest/download/chord-web-update.tar.gz) |

> 所有客户端**已内置默认服务器地址**，打开即可连接，无需任何配置。

---

## 四、升级

### 普通用户

| 平台 | 做法 |
|---|---|
| Android | 下载 `chord-arm64.apk` 覆盖安装（登录态保留） |
| Windows | 解压新 zip 覆盖旧目录（exe、dll、data 必须同目录） |
| Web | 刷新页面；图标或界面没变时强制刷新一次（Ctrl+F5） |

装好后在登录页底部核对：`客户端 v1.4.1 ｜ 服务器 v1.4.1`。

### 服务器维护者（本版前后端都改了）

```bash
sudo curl -fLo /opt/chord/update.sh https://github.com/zhumin2/discord-like/releases/latest/download/update.sh
sudo bash /opt/chord/update.sh server   # 建服默认频道权限 / 删除频道 / 搜索按频道 / 发言冷却
sudo bash /opt/chord/update.sh web      # 新图标 + 12 项界面修复
```

核对：`curl -s http://129.226.159.168:8081/api/health` 应返回 `"version":"v1.4.1"`。

> 说明：新的「公告仅创建者可发言」只影响**新建**服务器；已有服务器的公告频道可在
> 「频道设置」里把「谁可以发言」改成「仅频道创建者」。
