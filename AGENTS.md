# AGENTS.md — Chord 项目交接文档

> 面向接手本项目的 AI agent / 开发者：项目全貌、**完整历史**、线上运行事实、已知坑、资产与发布流程。
> 最后更新：2026-11-16（对应发布版本 **v1.1.3**，已上线）
>
> 📌 配套文档：[产品规格 docs/PRD.md](docs/PRD.md) ｜ [开发路线图 docs/ROADMAP.md](docs/ROADMAP.md)
> ｜ [面向用户的发布说明 docs/RELEASE-v1.1.0.md](docs/RELEASE-v1.1.0.md)
> ｜ [部署说明 deploy/部署说明.md](deploy/部署说明.md)（发布包内还有一份）

---

## 一、项目是什么

**Chord** —— 模仿 Discord 的实时聊天产品，可自托管，中文优先。当前状态：**v1.1.0 已上线运行**。

| 端 | 形态 | 入口 / 获取方式 |
|---|---|---|
| Web / PWA | Flutter Web（CanvasKit 渲染器） | http://129.226.159.168:3000 |
| Windows 桌面 | 原生窗口 1200×800，托盘最小化 | Release `chord-windows-x64.zip`（exe+dll+data 三件套同目录） |
| Android | APK（arm64 / armv7 / universal） | Release 附件（debug 签名，可直接安装） |
| 服务管理控制台 | Laragon 风格托盘程序 560×640 | 本机构建 `gui/`（仅 Windows，本地部署用） |
| 命令行管理 | Git Bash 脚本 | `chord.sh start/stop/restart/status/logs` |

**已实现功能**：注册登录(JWT)、服务器/邀请码、频道分组、实时消息(WS)、编辑删除、Markdown-lite、
@提及、表情回应、私信 DM、在线状态、typing 提示、未读/提及数、响应式(四栏/单栏+抽屉)、PWA、
**图片/文件上传（v1.1）**、**限流（v1.1）**、**gzip 压缩（v1.1）**。

**演示账号**：alice / bob / carol，密码均 `123456`；演示服务器邀请码 `demo2024`。

---

## 二、技术栈与目录结构

- **后端** Go 1.27.3：Gin + gorilla/websocket + GORM(MySQL) + go-redis
- **前端** Flutter 3.50.0 stable（Web + Windows + Android 同一套代码），Riverpod 3.x
- **存储** MySQL 8（持久化）+ Redis（presence/事件扇出，**可选**，连不上自动降级单机）

```
├── server/                    Go 后端
│   ├── cmd/server/            REST + WS 网关（产物 chord-server）
│   ├── cmd/serveweb/          Flutter Web 静态托管（gzip + SPA 回退 + wasm MIME + 缓存策略）
│   ├── cmd/fakeredis/         Redis 协议兼容开发服务器（miniredis + TCP 透传 6379）
│   ├── cmd/redisprobe/        Redis/presence 状态探针
│   └── internal/
│       ├── config/            .env + 默认值（含 UPLOAD_DIR）
│       ├── models/            GORM 模型（UUIDv7 主键 = 消息分页游标）
│       ├── auth/              JWT + bcrypt
│       ├── handlers/          REST（auth/guild/message/dm/router + **ratelimit.go + upload_h.go**）
│       ├── ws/                WebSocket Hub：连接、事件路由、presence、typing
│       ├── bus/               事件总线：MemoryBus / redisBus
│       └── db/                迁移 + 演示数据 seed
├── client/                    Flutter 聊天应用（web / windows / android 三平台）
│   ├── lib/state/app_state.dart   Riverpod ChatNotifier（REST+WS→统一状态）
│   ├── lib/api_client.dart        REST 客户端（含 upload 多部分上传）
│   ├── lib/gateway.dart           WS 网关（心跳 25s + 指数退避重连）
│   ├── lib/storage.dart           条件导入 KV（桌面 JSON 文件 / Web localStorage / 移动）
│   ├── lib/file_picker*.dart      **v1.1 文件选择（条件导入，零插件）**
│   ├── lib/widgets/               composer（含 📎）/ rich_text（含图片渲染）/ message_tile …
│   ├── lib/screens/               chat_area / home_shell / login_screen
│   ├── android/                   **v1.1 补生成**（MainActivity.kt 含 SAF 文件选择通道 chord/file）
│   └── windows/runner/            flutter_window.cpp **含 GetOpenFileNameW 通道 chord/file**
├── gui/                       服务管理控制台（独立 Flutter Windows 工程）
├── deploy/                    **部署脚本（入库版本）**
│   ├── install.sh             一键安装（幂等；MYSQL_PASS 环境变量传密码；restart 而非 enable --now）
│   ├── update.sh              服务器一键更新（web / full 两模式，从 GitHub Release 拉包）
│   ├── caddy/Caddyfile        TLS 反代模板（等域名启用）
│   └── 部署说明.md
├── docs/                      PRD.md（产品规格）/ ROADMAP.md（路线图）/ RELEASE-v1.1.0.md（用户向说明）
├── scripts/guitest/           GUI 黑盒走查（playwright-core + 无头 Edge）
├── chord.sh / chord.bat       本地服务管理
├── docker-compose.yml         mysql + redis（有 Docker 的环境用）
└── （不进仓库）dist/          本地构建产物：客户端安装包（Release 用）
    （不进仓库）runtimes/      便携工具链 + gh.exe
```

---

## 三、架构要点（为什么这样设计）

1. **消息 ID 用 UUIDv7**（时间有序）——分页直接 `WHERE id < cursor`，无需额外排序列。
2. **WS 事件与 REST 分离**：写操作走 REST（可靠、可校验），结果以 WS 事件广播（含作者本人，客户端按 ID 去重）。
3. **事件总线抽象 `bus.Bus`**：MemoryBus（单进程）/ redisBus（PUBLISH-SUBSCRIBE `chord:events`）同接口，Redis 缺失自动降级。
4. **presence**：键 `presence:<uid>` TTL 60s，心跳续期；成员在线状态 = 本地连接表优先、Redis 兜底。
5. **前端存储抽象**：条件导入——桌面 JSON 文件（`%APPDATA%\Chord\storage.json`）/ Web localStorage。
   **刻意不依赖任何 Flutter 平台插件**（否则 Windows 构建需要开发者模式）。文件选择同理：
   Web `<input type=file>` / Windows 原生 C++ / Android SAF，统一走 `chord/file` 调用约定。
6. **服务管理三件套一致**：GUI / chord.sh / 手动命令都优先用预编译 exe，缺失时自动编译。
7. **默认服务器地址推导**：Web 从 `Uri.base` 推导（同主机:8081）；桌面/移动用构建参数
   `--dart-define=CHORD_DEFAULT_BASE=`；登录页均可手改并持久化。
8. **v1.1 上传**：`POST /api/upload`（multipart ≤10MB + 扩展名白名单）落盘 `{UPLOAD_DIR}/yyyyMM/<uuid><ext>`；
   `GET /uploads/*` 公开读取（UUID 名不可猜测、拒绝 `..`/`\`、成功长缓存、**错误 no-store**）。
9. **v1.1 限流**：内存固定窗口，双维度——匿名接口按 IP（注册/登录 10 次/分）、登录后按用户
   （发消息 20 条/10s、上传 30 次/分），超限 429。多实例部署时需换 Redis 实现（未做）。

---

## 四、项目历史（完整时间线）

> 均按真实发生顺序记录，含发现的问题与修复提交，便于接手者理解"为什么代码长这样"。

### 阶段 0：MVP（2026-11-15 之前，另一会话完成）
原始需求：做一个像 Discord 的聊天软件。产出 Web(WASM/CanvasKit) + Windows 桌面 + 服务管理控制台 GUI；
建立本地便携运行时 `F:\dev\runtimes\`（Flutter/MySQL），后端 Go + MySQL + 可选 Redis；
写下本文件的前 10 条踩坑；讨论过中文名候选（**尚未定名，见第十节**）。

### 阶段 1：代码托管与首次公网部署（2026-11-15 晚）
1. 仓库 clone 到 `D:\code\chrod\discord-like`；确认本机实际环境与原文不符（无 `F:\dev\runtimes`，
   Go/Flutter 均未安装），遂下载便携工具链：**Go 1.27.3 + Flutter 3.50.0**（走国内镜像），
   放到 `D:\code\chrod\runtimes\`。
2. 用户要求部署到**新加坡腾讯云 129.226.159.168**（MySQL root，密码由项目负责人保管，本机 127.0.0.1:3306，
   Redis 无密码 6379 本机）。本机无 SSH 凭据 → 改为**用户手动上传 + 一键脚本**模式。
3. 交叉编译 Linux 三件套（`chord-server`/`serveweb`/`redisprobe`，CGO_ENABLED=0 静态链接）。
4. 首次 `flutter build web --wasm` 构建——**后来发现这是错的**（见坑 16）。
5. 编写 `install.sh`（密码移除内嵌，改 `MYSQL_PASS` 环境变量）与部署说明，打包 `chord-deploy.tar.gz`。
6. 用户上传安装 → 公网验证：API health 200、alice 登录成功、静态资源 200。
7. **发现 wasm 构建在线上直接白屏**：`crossOriginIsolated=false`，skwasm 引擎永不启动。改回
   `flutter build web --release`（CanvasKit），本地浏览器验证通过后重新打包。

### 阶段 2：GitHub 化与 v1.0.0 发布（2026-11-15 深夜）
1. 生成 SSH 密钥 `~/.ssh/id_ed25519_github`（用户加到 zhumin2 账号），`~/.ssh/config` 指到
   `ssh.github.com:443`（国内 HTTPS 被墙、22 有时被断）；远程地址切 SSH。
2. 提交 `deploy/` 三脚本 + app_state 默认地址改动；打 tag **v1.0.0** 并推送。
3. 用 **OAuth 设备码流程**认证 gh（便携版 `runtimes/bin/gh.exe`），创建 Release v1.0.0，上传
   服务器包；随后发现 **GitHub 附件名不支持中文**（"聊天"被吞），改用 ASCII 名重传。
4. 补 Android 平台（原仓库只有 web/windows）：`flutter create --platforms=android`，
   应用名 `Chord聊天`，并修复根 `.gitignore` 的 `app/` 误伤 `client/android/app/`（改锚定 `/app/`）。
5. 构建 Windows 客户端 + 3 个 APK，全部带 `--dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081`；
   用 `grep -a` 校验 AOT 快照内确实包含该地址。上传 Release。

### 阶段 3：产品文档（2026-11-15）
编写 `docs/PRD.md`（定位/用户/功能规格/非功能/度量/风险）与 `docs/ROADMAP.md`
（v1.1 安全体验 → v1.2 社群成长 → v1.3 语音 → v2.0 生态，含工作量、验收、甘特、DoD），
并在本文件加文档索引。

### 阶段 4：v1.1 开发（2026-11-16 凌晨）
1. **A2 gzip**：重写 `serveweb`——gzip 压缩（bundle 2.9MB→0.9MB）+ 缓存头。
2. **A3 限流**：`internal/handlers/ratelimit.go`，固定窗口、IP/用户双维度，接入注册/登录/发消息/上传。
3. **B 上传**：`upload_h.go`（上传 + 读取 + 白名单 + 10MB 上限）；客户端三端 📎 按钮
   （`file_picker.dart` 条件导入 + `ApiClient.upload` + `RichTextSpan` 图片渲染）。
4. **C1 测试**：`ratelimit_test.go`、`upload_test.go`，8 个用例（含并发精确性、路径穿越攻击）。
5. **A1 TLS**：`deploy/caddy/Caddyfile` 模板（域名就绪即可启用）。
6. 提交 `930b785`、tag **v1.1.0** 并推送；Release v1.1.0 上传 6 个附件。

### 阶段 5：v1.1 上线与 5 个连环 Bug（2026-11-16 上午）
上线后发现并依次修复（每个都记进了第五节）：

| # | 现象 | 根因 | 修复提交 |
|---|---|---|---|
| 1 | 线上页面**永久白屏** | gzip 响应**缺 `Content-Encoding` 头**，浏览器把压缩字节当 JS 执行 | `8350007` |
| 2 | 所有图片 **400** | gin 通配参数自带前导 `/`，Linux 上 `filepath.IsAbs` 为真被防穿越误杀 | `7ba4bce` |
| 3 | 线上仍是 v1.0、无 📎 | **web 构建从未成功**（类型名错+缺导入+构建在错目录、`&&` 掩盖失败） | `4201e83` |
| 4 | 修复"部署成功"却不生效 | `systemctl enable --now` 对已运行服务**不重启** | `71fc49a` |
| 5 | 📎 存在但**图标空白** | 图标字体被 `immutable` 缓存一年（产物名无内容哈希） | `548eaad` |

伴随修复：`bf9bd0b`（install.sh 未安装 update.sh 到 /opt/chord）、`bf9fa95`（/uploads 错误响应 no-store，
避免坏响应被缓存）。最终线上验证全绿：gzip 头+体积、入口 no-cache、字体 1h、限流 429、
上传 200/415、图片消息内联渲染、📎 图标可见。

### 阶段 6：文档收尾（2026-11-16）
回写 ROADMAP 状态（v1.1 已发布+遗留）、踩坑补到 15 条（`ee9b0af`）、
新增面向用户的 `docs/RELEASE-v1.1.0.md` 并同步到 Release 页面（`562b2ab`）。

---

## 五、踩坑记录（重要！避免重蹈）

1. **GORM 只自动填充 `CreatedAt/UpdatedAt`**；其他 time.Time 字段（如 `GuildMember.JoinedAt`）零值
   `0001-01-01` 会被 MySQL 严格模式拒绝 → 事务静默回滚。新增模型必须显式赋值。
2. **Flutter Windows 宽屏布局缺 `Material` 祖先** → Text 红字+黄双下划线、ExpansionTile 灰块（框架调试样式）。
   HomeShell 宽屏分支必须包 `Material`。
3. **中文显示方框**：CanvasKit 默认从 fonts.gstatic.com 拉字体（被墙）→ 必须内置 NotoSansSC（已注册）。
4. **GUI 的 C++ 源文件含中文注释**：必须 UTF-8 BOM + runner CMakeLists 加 `/utf-8`，否则 /WX 下 C4819。
5. **`Process.run` 的 `environment` 是整体替换**：必须 `{...Platform.environment, ...extra}` 合并。
6. **`flutter create` 后同端口僵尸进程**：TaskStop 杀不死 dartvm 子进程，新构建"看似部署实则旧代码在服务"。
7. **Flutter Web + 无头浏览器自动化**：canvas 渲染 DOM 快照为空，需先对 `flt-semantics-placeholder`
   `dispatchEvent(click)`；Playwright `fill()` 对 Flutter 输入框不生效，用界面内按钮或 `cua.type`。
8. **shared_preferences 插件使 Windows 构建需要开发者模式** → 已移除并自研 storage。
   **不要给 client/gui 加任何平台插件**，托盘/窗口/文件选择全走原生 C++ / Kotlin / Web API。
9. **miniredis 只支持随机端口**：fakeredis 用 TCP 字节透传固定 6379（协议纯流，无损）。
10. **Windows 控制台 GBK**：bash/python 输出中文需 `-X utf8`；**用 curl 发中文 JSON 到 API 会被 GBK 污染**
    （本项目曾因此产生乱码测试消息）→ 一律 `python -X utf8` + `json.dumps(ensure_ascii=False).encode('utf-8')`。
11. **后台构建必须在正确目录**：`flutter build web` 在无 pubspec 目录执行会失败，但 `&&` 链可能掩盖退出码，
    产物目录残留旧文件 → 发布包静默带旧代码。**发布前必须校验产物含新代码特征**
    （dart2js 把中文转成 `\uXXXX`，用 python 搜 `\u53d1\u9001\u6587\u4ef6`、`/api/upload`；AOT 里中文是 UTF-16LE）。
12. **serveweb gzip 必须声明 `Content-Encoding`**：只压缩 body 不设头 → 浏览器把 gzip 当明文 JS → 静默白屏。
    验证必须查响应头 + `curl --compressed` 解压 + 浏览器真实加载，只看 `size_download` 会误判。
13. **gin 通配参数自带前导 `/`**：`c.Param("filepath")` 得到 `/202611/x.png`，Linux 上 `filepath.IsAbs` 为 true
    （Windows 为 false）→ 用 IsAbs 校验会"本地过、线上 400"。剥前缀后只拒 `..` 与 `\`。
14. **install.sh 用 restart 而非 `enable --now`**：对已运行服务 `systemctl enable --now` 不重启，新二进制不生效。
15. **缓存必须区分「有无内容哈希」**：加 `--web-content-hash` 前，`main.dart.js`、字体、`canvaskit/*` 都是稳定文件名，
    设 `immutable` 会导致升级后继续用旧 bundle / 旧图标字体（曾致"按钮存在但图标空白"）。
    现策略（serveweb `cacheControl`）：入口/清单 `no-cache`；文件名含 8 位以上十六进制哈希的资源
    `max-age=31536000, immutable`（`--web-content-hash` 产出）；**canvaskit/ 与 icons/ 不参与哈希** → 保持 `max-age=3600`。
    **排查信号：语义树里有控件、但截图空白 → 先怀疑字体缓存**。
16. **`flutter build web --wasm` 部署到无 COOP/COEP 头的服务器会白屏**（`crossOriginIsolated=false`，
    skwasm 卡死、`flutter-view` 永不创建）。本项目必须用普通 `--release`（CanvasKit/dart2js）；
    serveweb 的 wasm MIME 是为 canvaskit.wasm 服务的，与 dart2wasm 无关。
17. **限流测试会吃掉自己 IP 的配额**（登录 10 次/分）：测完需等 65 秒再登录，否则拿到 429。
18. **CanvasKit 默认从 gstatic CDN 加载**（`useLocalCanvasKit:false` → `www.gstatic.com/flutter-canvaskit/<rev>/`），
    国内直接卡死/白屏。**Web 构建必须加 `--no-web-resources-cdn`**（本地优先请求 `canvaskit/chromium/canvaskit.wasm` 5.3MB）。
    仅设 `--dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/` **不够**——那是 Dart 层兜底，JS 加载器仍走 CDN。
19. **中文字体是首屏最大负担**：全量 NotoSansSC 每字重 10MB，两字重 20MB（实测首屏共 28.5MB）。
    已用 `scripts/fonts/subset_fonts.py` 子集化为 GB2312 共 7562 字（每字重 2.3MB，合计 4.6MB，覆盖约 99.7%），
    首屏降到 13MB（gzip 后约 5MB）。**生僻字会显示方框**；需更大覆盖用 `gb2312`/`level1` 参数，
    还原全量用 `--restore`（源文件备份为 `*.full.bak`，已 ignore）。改字体后必须重建并校验产物大小。
    **分平台策略（v1.1.4 起）**：`client/assets/fonts/*.ttf` 是 GB2312 子集（Web 用，省带宽）；`client/assets/fonts/full/*.ttf` 是全量（30k 码位，含 頔玥喆 等生僻字），Windows/Android 构建前用 `cp client/assets/fonts/full/*.ttf client/assets/fonts/` 覆盖（CI 已在 release-clients 里做）。子集只覆盖 7547 字，缺失时界面显示方框，仅 Web 可接受。
20. **Git Bash 会篡改 dart-define 里的绝对路径风格参数**：`--dart-define=X=/canvaskit/` 会被 MSYS 转成
    `C:/Program Files/Git/canvaskit/` 写进构建产物。带 `/` 开头的 define 必须加 `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`，
    并在产物里 `grep` 校验实际注入值。
21. **聊天记录顺序**：服务端 `ListMessages` 已把结果翻成时间正序返回（旧→新）；客户端 `_loadMessages` **不能再 reversed**，否则历史倒序（新消息在上）。UI 用 `ListView(reverse:true)`，列表末尾（最新）渲染在最下方。该 bug 自 MVP 就存在，因新消息走 WS 追加到末尾看似正常而长期未发现（v1.1.6 修复）。

---

## 六、线上运行事实（服务器 129.226.159.168）

- 云厂商：腾讯云，OS opencloudos。**本机没有该服务器 SSH 凭据，所有操作由用户手动执行**（用户复制命令）。
- MySQL 8：用户 `root`（**密码不写入仓库，向负责人索取**），`127.0.0.1:3306`，库 `chord`。Redis：`127.0.0.1:6379` 无密码（可选）。
- 端口：**API 8081、Web 3000**（腾讯云安全组已放行）。无 80/443（TLS 待域名）。
- 安装布局 `/opt/chord/`：
  ```
  server/chord-server      后端二进制
  server/.env              配置（600，含 DB_DSN / UPLOAD_DIR=/opt/chord/data/uploads）
  server/.data/jwt_secret  JWT 密钥（600，唯一需备份的秘密）
  web/serveweb             静态托管二进制
  web/htdocs/              Flutter Web 产物
  data/uploads/            用户上传文件（yyyyMM/uuid.ext）
  update.sh                一键更新脚本（web|full）
  ```
- systemd：`chord-server`、`chord-web`，运行用户 `chord`；日志 `journalctl -u chord-server -f`。
- 运维命令：`sudo bash /opt/chord/update.sh web`（只换前端，最常用）、
  `sudo MYSQL_PASS='...' bash /opt/chord/update.sh full`（全量重装，用于二进制/配置变更）。
- 数据备份：只需 `mysqldump chord` + `/opt/chord/data/uploads/` + `server/.data/jwt_secret`。

---

## 七、本机开发环境（Windows 11，便携化）

| 组件 | 路径 | 说明 |
|---|---|---|
| Go 1.27.3 | `D:\code\chrod\runtimes\go\bin\go.exe` | GOPROXY=`https://mirrors.aliyun.com/goproxy/,direct`（goproxy.cn 常超时） |
| Flutter 3.50.0 | `D:\code\chrod\runtimes\flutter\bin\flutter.bat` | `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` |
| Android SDK | `D:\Apps\android-sdk`（API 36） | JDK 17 Temurin；licenses 已接受 |
| VS Build Tools 2022 | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` | Windows 桌面构建 |
| gh CLI 2.104 | `D:\code\chrod\runtimes\bin\gh.exe` | 发 Release 用（见第八节） |
| 工作区 | `D:\code\chrod\`（仓库 `discord-like/`，产物 `dist/`，脚本 `deploy-scripts/`） | |

> 注意：历史文档中的 `F:\dev\runtimes\` 在本机**不存在**，实际工具链路径以上表为准。

---

## 八、构建与发布手册

### 8.1 构建

```bash
# 后端（Linux 静态二进制，供服务器）
cd server && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o <out>/chord-server ./cmd/server
# 同样产出 serveweb / redisprobe（cmd/serveweb、cmd/redisprobe）
go vet ./... && go test ./internal/handlers/     # 测试

# Web（必须 cd client/；默认地址按需改）
# ⚠️ 必须带 --no-web-resources-cdn：否则 CanvasKit 从 www.gstatic.com 拉（国内被墙 → 白屏/极慢）
# ⚠️ 必须带 --web-content-hash：产物文件名带内容哈希 → serveweb 才能给 immutable 长缓存（二次访问零下载）
cd client && flutter build web --release --no-web-resources-cdn --web-content-hash --dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081
# 校验产物含新代码（关键！）：
python -X utf8 -c "d=open('build/web/main.dart.js',encoding='utf-8',errors='ignore').read(); print(d.count(r'\u53d1\u9001\u6587\u4ef6'), d.count('/api/upload'))"

# Windows 客户端（产物 build/windows/x64/runner/Release → 改名 exe 为 Chord聊天.exe，三件套同目录打 zip）
# 桌面/移动用全量字体（不缺生僻字）；Web 才用子集
cp client/assets/fonts/full/*.ttf client/assets/fonts/
cd client && flutter build windows --release --dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081

# Android（推荐 arm64；另两个 ABI 用 --split-per-abi 自动产出；同样先用全量字体）
cd client && flutter build apk --release --split-per-abi --dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081
```

### 8.2 打包服务器部署包

```bash
# 包目录结构（package/）：chord-server serveweb redisprobe install.sh update.sh 部署说明.md web/
tar czf chord-deploy.tar.gz package/            # 全量
cd package && tar czf chord-web-update.tar.gz web/   # 仅前端
```

### 8.3 发布 Release

**推荐（v1.1.2 起）：推 tag 触发 GitHub Actions 自动构建发布**

```bash
git tag -a v1.1.x -m "说明" && git push origin v1.1.x
# .github/workflows/release-web.yml 会在 CI 里构建 Web + serveweb 并上传到该 Release
# 产物：chord-web-update.tar.gz（含 web/serveweb）、update.sh
```

为什么要走 CI：本机网络向 `uploads.github.com` 上传附件会被 GitHub abuse 检测拦截（403 Unicorn），
而 Actions 由 GitHub 自己的 runner 上传，不受影响；同时产物可复现。
服务器升级：`sudo curl -fLo /opt/chord/update.sh <latest>/update.sh && sudo bash /opt/chord/update.sh web`

### 8.3.1 每个 Release 的完整附件（v1.1.3 起）

`release-web`（Web + 全量部署包 + update.sh）与 `release-clients`（Windows zip + 3 个 APK）两个工作流
在推 tag 时并行执行，因此每个版本的 Release 都自带 7 个附件：

```
chord-web-update.tar.gz  chord-deploy.tar.gz  update.sh
chord-windows-x64.zip    chord-arm64.apk  chord-armv7.apk  chord-universal.apk
```

⚠️ **不要让某个版本缺少附件**：README 里的下载链接用 `releases/latest/download/<文件名>`，
一旦最新版本缺客户端，链接立即 404（v1.1.2/v1.1.3 初期就踩过）。
历史版本补附件：Actions → release-clients → Run workflow，填已存在的 tag。
注意 Windows runner 控制台是 cp1252，打包脚本里不要 print 中文（会 UnicodeEncodeError）。


（v1.1.3 起 update.sh web 具备：更新前备份 serveweb+htdocs、二进制原子替换、启动后 curl 探活、失败自动回滚并以非零码退出；
自定义端口用 `WEB_PORT=xxxx` 传入，否则默认 3000 探活）
（v1.1.2 起 update.sh web 会在包内含 serveweb 时一并升级静态服务器二进制）。

**旧流程（手动/设备码认证，仅在没有 CI 时使用）**

1. 远端必须是 SSH：`git@github.com:zhumin2/discord-like.git`（本机 `~/.ssh/config` 已指 ssh.github.com:443）。
2. 认证：`gh.exe` 存储校验要求 `read:org`，故**不要 `gh auth login`**；改用 OAuth 设备流拿 token：
   ```bash
   curl -s -X POST https://github.com/login/device/code -H "Accept: application/json" \
        -d "client_id=178c6fc778ccc68e1d6a&scope=repo"      # → user_code，请用户在 15 分钟内输入
   # 轮询：
   POST https://github.com/login/oauth/access_token  grant_type=urn:ietf:params:oauth:grant-type:device_code
   ```
   把 token 写到文件后 `export GH_TOKEN=$(cat token.txt)` 使用；**用完立即删除 token 文件**。
3. 上传附件：`gh release upload <tag> <files> --clobber`。
   **附件名必须 ASCII**（中文会被吞）；上传后核对 `size`，并用 API 的 `digest` 与本地 `sha256sum` 比对。
4. 发布说明用 `--notes-file`（用户向文案见 `docs/RELEASE-*.md`）。

### 8.4 发布后验证清单（每次必做）

```bash
curl -s http://129.226.159.168:8081/api/health                       # {"status":"ok"}
curl -s -D - -o /dev/null -H "Accept-Encoding: gzip" <web>/flutter_bootstrap.js | grep -i content-encoding
curl -s --compressed -H "Accept-Encoding: gzip" <web>/main.dart.js | wc -c   # 与新构建解压尺寸一致
curl -sI <web>/main.dart.js | grep -i cache-control                  # no-cache
curl -sI <web>/assets/fonts/MaterialIcons-Regular.otf | grep -i cache-control  # max-age=3600
# 限流（会耗掉本 IP 登录配额，测完等 65s）
for i in $(seq 1 11); do curl -s -o /dev/null -w "%{http_code} " -X POST <api>/api/auth/login -H "Content-Type: application/json" -d '{"username":"x","password":"y"}'; done
# 上传：合法 png 200 且返回 /uploads/...；.exe 415；/uploads/不存在 404 + no-store
# 浏览器（无头/自动化）：登录 → 语义树出现 button "发送文件" → 图片消息内联渲染
```

---

## 九、验证方式

- **后端冒烟**：`cmd/redisprobe`（presence 键）、`curl /api/health`、`go test ./internal/handlers/`
- **GUI 黑盒**：`scripts/guitest/walk.mjs` / `final-walk.mjs`（双账号实时消息、双视口、截图）
- **全链路**：浏览器登录不同演示账号互发消息；移动端 375×812 视口 + 抽屉
- **无头浏览器**：先 `dispatchEvent(click)` 激活 `flt-semantics-placeholder`；`fill()` 对 Flutter 输入框无效
- 跑 GUI 测试前 `cd scripts/guitest && npm i`（playwright-core + 系统 Edge）

---

## 十、已知限制 / 待办

**v1.1 遗留**：TLS 待域名（`deploy/caddy/Caddyfile` 已就绪）；CDN 未接入；每日备份 cron 未配置；
APK 为 debug 签名；Windows 无代码签名（图片已在客户端上传前压缩，见 8.5）。

**路线图**（详见 `docs/ROADMAP.md`）：
1. **v1.2 社群成长**：角色权限体系（role 表 + 权限点 + UI）、消息搜索（MySQL ngram 全文索引）、
   桌面/Web 通知、好友系统（可选）、Android 正式签名
2. **v1.3 语音**：WebRTC mesh（先限 3 人，新加坡带宽有限），信令复用现有 WS Hub，TURN 用 coturn
3. **v2.0**：Bot API、SFU、多实例（redisBus 已具备但未实测）、移动推送、应用市场分发

**中文名候选（仍未拍板）**：共鸣 / 同频 / 合鸣 / 声部 / 弦外 / 开弦 / 声浪 / 共鸣腔 / 卡农 / 泛音 /
上弦 / 音叉。落地位置：`client/windows/runner/main.cpp` 窗口标题、`gui/windows/runner/tray_manager.cpp`、
`client/web/index.html` + `manifest.json`、登录页、README。

---

## 十一、接手建议（新 agent 从这里开始）

1. 先读本文件第四节（历史）→ 再读 `docs/PRD.md` 与 `docs/ROADMAP.md` 了解规范与计划。
2. 本地起服务自测（服务器上的东西别乱动，用户手动操作）：
   `cd server && go run ./cmd/server`（需本地 MySQL；或连服务器 MySQL 改 DB_DSN），
   `cd client && flutter run -d windows` 或 `flutter run -d chrome`。
3. 改完代码先跑 `go vet ./... && go test ./...`；UI 改动用 `scripts/guitest` 走查。
4. **发布前务必执行第 8.4 节清单**——v1.1 的 5 个 bug 全部是"部署了但没生效/没生效却以为生效"。
5. 涉及部署变更时同步更新 `deploy/部署说明.md` 与本文件第五节。

### 8.5 图片上传前压缩（v1.1.8）

跨境带宽很窄（实测 10-50KB/s），原图直传会长时间卡住。客户端 `client/lib/image_compress.dart`
在选择文件后、上传前压缩（纯 Dart `image` 包，无平台插件，跨三端一致）：

- 仅处理 JPEG/PNG；GIF/WebP/其他文件原样上传
- <200KB 的小图直接放行
- 最长边 >1600 等比缩放（平均插值）
- JPEG q82 起，若结果 >500KB 自动逐级降质量（最低 55）
- PNG 带透明通道时重新编码为 PNG（保留透明），否则转 JPEG
- 任何异常 / 压缩后更大 ⇒ 回退原图，绝不阻断发送
- 压缩在后台 isolate（`compute`）执行，不卡界面

实测：3000×2000 噪声图 11.7MB → 476KB；真实照片通常 150-250KB。
**注意**：服务端 `/api/upload` 仍只做 10MB + 扩展名白名单校验，压缩完全在客户端；
若将来有第三方客户端，考虑加服务端兜底压缩。
