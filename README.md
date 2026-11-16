# Chord — 模仿 Discord 的实时聊天产品

可自托管的中文实时聊天社区：**服务器 → 频道 → 消息**，支持 Web/PWA、Windows 桌面与 Android 客户端。

**在线体验**：http://129.226.159.168:3000 ｜ **演示账号**：`alice` / `bob` / `carol`（密码 `123456`），邀请码 `demo2024`

**下载客户端**（[最新 Release](https://github.com/zhumin2/discord-like/releases/latest)）：
[Android arm64](https://github.com/zhumin2/discord-like/releases/latest/download/chord-arm64.apk) ·
[Android 老机型](https://github.com/zhumin2/discord-like/releases/latest/download/chord-armv7.apk) ·
[Windows x64](https://github.com/zhumin2/discord-like/releases/latest/download/chord-windows-x64.zip) ·
网页版直接访问上面的在线地址

> 文档：[产品规格](docs/PRD.md) ｜ [开发路线图](docs/ROADMAP.md) ｜ [v1.1 发布说明](docs/RELEASE-v1.1.0.md) ｜ [项目交接/历史](AGENTS.md) ｜ [部署说明](deploy/部署说明.md)

- **前端**: Flutter 3.50（Web + Windows + Android 一套代码）— 宽屏四栏 / 窄屏单栏+抽屉
- **后端**: Go 1.27 (Gin + gorilla/websocket)
- **存储**: MySQL 8 (消息持久化) + Redis (在线状态/事件总线，**可选**，无 Redis 自动降级为进程内实现)

## 功能

| 模块 | 说明 |
|---|---|
| 账号 | 注册 / 登录（JWT，用户名+4位编号，如 alice#1001） |
| 服务器 | 创建、邀请码加入、退出、邀请码重置 |
| 频道 | 文字频道 + 分组，创建/删除（所有者） |
| 消息 | 实时收发、历史分页、编辑/删除、`**粗**` `*斜*` \`代码\` 链接渲染 |
| **图片/文件** | **v1.1**：输入框 📎 上传（≤10MB，图片内联渲染可点击放大，其他文件给下载链接） |
| 提及 | @用户名 高亮 + 提及数红点 |
| 回应 | 表情 reaction，消息悬浮栏或底部面板 |
| 私信 | 搜索用户发起 DM，会话列表 |
| 在线状态 | 在线/离开/离线，成员列表分组，心跳保活 |
| 输入中 | 「xx 正在输入…」实时提示 |
| 未读 | 频道未读数、@提及数、服务器角标 |
| 移动端 | <1000px 自动切换单栏 + 抽屉导航 + 底部安全区适配 |
| PWA | manifest + service worker，可添加到主屏幕 |
| **限流** | **v1.1**：登录/注册按 IP、发消息/上传按用户，超限 429 |

## 目录结构

```
├── server/               Go 后端
│   ├── cmd/server/       主服务 (REST + WS 网关)
│   ├── cmd/serveweb/     静态站点托管（gzip + SPA 回退 + 缓存策略）
│   ├── cmd/fakeredis/    开发用 Redis 协议兼容服务器
│   ├── cmd/redisprobe/   presence 状态探针
│   ├── internal/         config / models / auth / handlers / ws / bus / db
│   └── docker-compose.yml  mysql + redis（有 Docker 的环境用）
├── client/               Flutter 应用（web / windows / android）
│   └── lib/              api / gateway / state(riverpod) / screens / widgets / file_picker*
├── gui/                  服务管理控制台（Windows 托盘程序）
├── deploy/               服务器部署脚本（install.sh / update.sh / caddy）
├── docs/                 PRD / ROADMAP / 发布说明
├── start-dev.sh          一键启动（Git Bash）
├── AGENTS.md             项目交接文档（历史、坑、发布手册）
└── README.md
```

## 服务器部署

```bash
curl -fLO https://github.com/zhumin2/discord-like/releases/latest/download/chord-deploy.tar.gz
tar xzf chord-deploy.tar.gz && cd package
sudo MYSQL_PASS='<数据库root密码>' bash install.sh     # 需 MySQL 8；Redis 可选
# 之后更新：
sudo bash /opt/chord/update.sh web                    # 仅前端
sudo MYSQL_PASS='<密码>' bash /opt/chord/update.sh full   # 全量
```

详见 [deploy/部署说明.md](deploy/部署说明.md)。

## 快速开始

### 方式 A：一键脚本（本机已装好运行时）

```bash
bash start-dev.sh
# 打开 http://127.0.0.1:3000
# 演示账号: alice / bob / carol，密码均为 123456
# 演示服务器邀请码: demo2024
```

脚本会：启动 MySQL(3306) → 建库 → 启动 Go API(8081) → 构建/托管 Flutter Web(3000)。

### 服务管理（chord.sh）

所有服务的启动/停止/状态/日志由 `chord.sh` 统一管理，Windows 下也可双击 `chord.bat`：

```bash
bash chord.sh start            # 启动全部（= start-dev.sh）
bash chord.sh stop             # 停止全部（含清理遗留 8080 进程）
bash chord.sh restart api      # 只重启某个服务（api|web|mysql）
bash chord.sh status           # 查看各服务运行状态与 PID
bash chord.sh logs api         # 跟踪日志（api|web|mysql|all，Ctrl+C 退出）
```

对应快捷方式：`start-dev.sh` / `stop-dev.sh`。日志位于 `/tmp/chord-{api,web,mysql}.log`。

> 注意：从 ZCode 沙箱等受限环境里启动的进程可能无法被脚本结束（拒绝访问），
> 用自己的 Git Bash / chord.bat 启动的服务则完全可控；实在杀不掉的进程重启电脑后释放。

### 图形控制台（GUI，Laragon 风格）

双击项目根目录的 **`启动控制台.bat`**（或直接运行 `console\Chord控制台.exe`）：

- 三个服务卡片（MySQL / API / Web）：状态灯、端口、PID、单独 启动/停止/重启
- 「全部启动」「全部停止」一键操作；「打开网页」「日志目录」快捷入口
- 底部日志面板（MySQL/API/Web 分页，自动滚动），API/Web 缺少 exe 时会自动 `go build`
- 每 3 秒自动刷新状态
- **关闭窗口 = 缩小到系统托盘**（首次有气泡提示）：托盘图标左键单击恢复窗口，右键菜单提供「打开控制台 / 打开网页 / 退出」；只有托盘菜单「退出」才会真正关闭程序，且已启动的服务继续运行
- 托盘/关闭行为在 `gui/windows/runner/tray_manager.cpp` 中以原生 Win32 实现，无第三方依赖

GUI 启动的服务与 chord.sh 完全等价（优先使用 `server\chord-server.exe` / `serveweb.exe`，缺失时自动编译）。

### PC 桌面客户端（Windows）

除浏览器/PWA 外，聊天应用本体也有 Windows 桌面版（同一套 Flutter 代码编译为原生窗口）：

- 双击 **`启动聊天客户端.bat`**（或直接运行 `app\Chord聊天.exe`）
- 窗口 1200×800（最小 900×600），登录态保存在 `%APPDATA%\Chord\storage.json`
- 默认服务器地址由构建参数决定：`--dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081`
  （未指定时为本机 `127.0.0.1:8081`），登录页可随时改
- 也可以从控制台 GUI 的「聊天客户端」按钮一键启动
- 源码同 `client/`（`flutter build windows --release` 产物部署于 `app/`）

### Android 客户端

源码位于 `client/android/`（SAF 文件选择在 `MainActivity.kt`），构建：

```bash
cd client && flutter build apk --release --split-per-abi \
  --dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081
# 产物 build/app/outputs/flutter-apk/app-{arm64-v8a,armeabi-v7a,x86_64}-release.apk
```

> 客户端无任何平台插件依赖（KV 存储自行实现；文件选择走 Web `<input>` / Windows C++ / Android SAF 原生通道），
> 无需开发者模式即可构建。

### 方式 B：手动分步

```bash
# 1. 数据库（本机 MySQL 或 docker compose up -d）
mysql -u root -e "CREATE DATABASE chord CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# 2. 后端
cd server && go run ./cmd/server
# 可选 Redis: REDIS_ADDR=127.0.0.1:6379

# 3. 前端（开发热重载）
cd client && flutter run -d web-server --web-port 3000
# 或（生产构建 + 静态托管）
flutter build web --release
cd ../server && go run ./cmd/serveweb -dir ../client/build/web -port 3000
```

### 手机端体验

同一局域网下，手机浏览器访问 `http://<电脑局域网IP>:3000`。
首次进入会看到登录页 → 展开「服务器地址」→ 填 `http://<电脑IP>:8081` → 登录。
（浏览器地址栏菜单 →「添加到主屏幕」可安装为 PWA。）

## 配置（server/.env，参考 .env.example）

| 变量 | 默认 | 说明 |
|---|---|---|
| PORT | 8081 | API 端口 |
| DB_DSN | root@tcp(127.0.0.1:3306)/chord | MySQL DSN |
| REDIS_ADDR | 127.0.0.1:6379 | 连不上自动降级为进程内单实例模式 |
| JWT_SECRET | 自动生成 | 存于 `server/.data/jwt_secret`（**唯一需备份的秘密**） |
| SEED_DEMO | true | 空库时写入演示数据（alice/bob/carol + 演示服务器） |
| CLIENT_ORIGIN | 空 | 额外允许的 CORS 来源（如 `https://你的域名`） |
| UPLOAD_DIR | ./data/uploads | **v1.1** 上传文件根目录（生产建议 `/opt/chord/data/uploads`） |

### Redis 说明

- **开发环境**：`server/cmd/fakeredis` 是内置的 Redis 协议兼容服务器（miniredis），`bash chord.sh start all` 会自动拉起；API 检测到 6379 可用即走 Redis（在线状态键 `presence:*` + 事件频道 `chord:events` 的 pub/sub）。验证：`cd server && go run ./cmd/redisprobe`
- **生产/多实例**：把 REDIS_ADDR 指向真 Redis（Docker: `docker compose up -d`、WSL、或 Memurai），多实例部署时事件经 Redis pub/sub 扇出、在线状态跨实例共享；单实例直连也完全可用

## 验证过的链路

- 注册/登录（JWT，bcrypt）、限流（IP/用户维度 429）
- 服务器/频道 CRUD + 邀请码加入
- 消息发送/编辑/删除/表情回应（REST 写入 + WS 广播，双端实时）
- **图片/文件上传 + 消息内联渲染（三端）**、白名单与 10MB 上限、路径穿越防护
- @提及高亮与提及未读、DM 私信、在线状态心跳、typing 提示
- 中文/emoji 全链路 UTF-8（utf8mb4）
- 响应式布局（1280px 四栏 / 375px 单栏+抽屉）
- 自动化测试：`cd server && go test ./...`（限流精确性、上传白名单/超限/穿越攻击）

## 后续扩展点（未做，见 docs/ROADMAP.md）

角色权限体系、消息搜索、桌面/移动推送通知、好友系统、语音频道（WebRTC mesh）、Bot API。
代码已按模块分层（handlers/ws/bus/ratelimit），可平滑加域。

