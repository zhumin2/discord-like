# AGENTS.md — Chord 项目交接文档

> 面向接手本项目的 AI agent / 开发者：项目全貌、**完整历史**、线上运行事实、已知坑、资产与发布流程。
> 最后更新：2026-11-23（对应发布版本 **v1.4.0**，已上线）
>
> 📌 配套文档：[产品规格 docs/PRD.md](docs/PRD.md) ｜ [开发路线图 docs/ROADMAP.md](docs/ROADMAP.md)
> ｜ [面向用户的发布说明 docs/RELEASE-v1.4.0.md](docs/RELEASE-v1.4.0.md)（历史：v1.3.8、v1.1.0）
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

### 阶段 7：v1.1.2 → v1.2.3（2026-11-16，本机会话）

用户在反馈线上 Web「好难打开」后，从定位到修复再到功能补齐的一整轮迭代。**每个版本都已打 tag 并由 CI 出包**。

| 版本 | 内容 | 关键提交 |
|---|---|---|
| v1.1.2 | 首屏 28.5MB→13MB：CanvasKit 本地化（`--no-web-resources-cdn`）、中文字体子集化（GB2312，2×10MB→2×2.3MB） | `11ae802` |
| v1.1.2 | 内容哈希 + immutable 长缓存（二次访问零下载） | `f7b21bc` |
| v1.1.3 | 发布流水线：打 tag → CI 构建 Web/三端客户端/全量包并上传 Release | `806fbb1` `a8b6247` `2dfa6c0` |
| v1.1.3 | `update.sh` 加固：备份回滚、原子替换、启动探活（隔离环境实测成功+回滚两条路径） | `39a541c` |
| v1.1.4 | 字体分平台：Web 用子集，Windows/Android 用全量（修复人名生僻字变方框） | `9a7317f` |
| v1.1.5 | 在线状态卡住修复：WS 重连后重同步 + 心跳看门狗（75s 无入站判半开重连） | `f4dcac4` |
| v1.1.6 | 聊天记录倒序修复：服务端已正序，客户端又 `reversed`（自 MVP 就存在） | `a3885cf` |
| v1.1.7 | 未读改红色数字徽章（>99 显示 99+），@提及用亮红+发光+粗体 | `2be2091` |
| v1.1.8 | 图片上传前压缩：最长边 1600、q82 起自适应降到 500KB 以内（11.7MB→476KB 实测） | `090be11` |
| v1.1.9 | 左上角私信图标显示未读总数 | `45be727` |
| v1.2.0 | **消息引用回复**（`reply_to_id` 列 + 同频道校验 + 引用块渲染） | `c1758e7` |
| v1.2.1 | `update.sh server` 模式：只换二进制、不需要 MYSQL_PASS | `c57986e` |
| v1.2.2 | 聊天客户端点 X 最小化到托盘（复用控制台原生实现） | `10bd747` |
| v1.2.3 | 桌面单实例（互斥量 + 唤起已有窗口）、托盘未读角标（提示文字 + 图标红圈数字） | `6789f75` |

**这一轮的教训（已并入第五节）**：
- 线上故障的根因往往不在"代码逻辑"而在"资源来源"：CanvasKit 走 gstatic、字体 20MB、无 gzip —— 全部靠实测网络请求定位（gstatic 请求挂起 90s+）。
- 跨境带宽是最硬的约束：即使压到 5MB，单连接 10KB/s 仍要 6 分钟；后续要靠 BBR / CDN / 升带宽解决。
- "部署了但没生效"是反复出现的模式：必须校验产物哈希（`main.dart.<hash>.js` 与本地一致）而不是看脚本打印成功。
- 发布附件不全会让 README 的 `releases/latest/download/...` 立刻 404（v1.1.3 初期），故每个 tag 必须产出 7 个附件。

### 阶段 8：v1.3.0（2026-11-18）

用户四项反馈后的一轮迭代（Android APK 断网修复见 v1.2.4/坑 22）：

| 项 | 内容 |
|---|---|
| 个人资料 | `PATCH /users/me`（用户名/颜色/头像，`avatar_url` 列 AutoMigrate）；USER_UPDATE 广播到所在服务器+私信+自己；客户端设置对话框（头像上传相机角标、10 色调色板、用户名） |
| 图片缓存+占位符 | `cached_image.dart`：内存→磁盘→网络两级；Windows `%LOCALAPPDATA%\Chord\cache\images`、Android `filesDir/cache/images`（走 chord/file.storagePath）、Web 交浏览器缓存；加载中 spinner、失败断链图标 |
| @自动补全 | Composer 输入 `@` 弹成员候选（过滤+最多5条），Enter/Tab/点击补全；服务器=全体成员，DM=对端+自己 |
| 桌面托盘 | 核实 v1.2.2 已实现——"看不到"是 Windows 把新图标收进了托盘溢出区（^），非缺陷 |

**注意**：改动 users 表（avatar_url）与消息引用（reply_to_id）都依赖后端二进制更新；
线上后端若仍是 v1.1.3，需 `update.sh server`（见第十节线上状态）。

### 阶段 9：v1.3.1 → v1.3.3（版本互查 + 转圈修复）

**版本号互查**：三端客户端都能看到「客户端版本 ｜ 服务器版本」，测试时可直接判断前后端是否配套。

| 位置 | 实现 |
|---|---|
| 后端 | `handlers.Version`（默认 `dev`）+ `/api/health` 返回 `{"status":"ok","version":"v1.3.1"}`；CI 用 `-ldflags "-X chord/server/internal/handlers.Version=$CHORD_VERSION"` 注入 |
| 客户端 | `client/lib/version.dart`：`appVersion = String.fromEnvironment('CHORD_VERSION', defaultValue:'dev')`；CI 构建全部加 `--dart-define=CHORD_VERSION=<tag>` |
| 展示 | `client/lib/server_version.dart` 的 `VersionText`：登录页底部 + 个人资料对话框底部（Web/Windows/Android 一致），服务器版本来自 `/api/health`（5s 超时，失败显示「无法获取」） |
| 验证 | `scripts/guitest/version_check.mjs`：无头 Edge 打开登录页，断言界面出现与 `/api/health` 相同的版本串 |

**本地构建默认是 `dev`**，只有 CI（release-web / release-clients）注入 tag；排查线上版本时以页面显示 + `/api/health` 为准。

**v1.3.2**：release-web 增加「Verify version baked into artifacts」步骤——构建后 `grep` 校验
`main.dart.<hash>.js` 与 `chord-server` 二进制里确实含有 `$CHORD_VERSION`，缺失直接失败（避免注入失配静默变成 `dev`）。

**v1.3.3**：修复「消息列表顶部永久转圈」（坑 24）——WS 给未打开频道预投递消息后，
`selectChannel`/`openDM` 的 `messages[id] != null` 判断误以为已加载而跳过 REST 拉取，
`noMore` 永不标记 → 顶部分页占位 spinner 永转 + 历史缺失。改为选中即拉最新一页。

### 阶段 11：v1.3.5（2026-11-19，十项反馈 + 头像压缩）

| # | 项 | 实现 |
|---|---|---|
| 1 | 图片复制/粘贴 | 粘贴：Web 由 `web/index.html` 的 JS 监听 paste → dataURL → `chord-paste-image` 自定义事件 → Dart 解码后走附件压缩上传管线；Windows 原生拦截 Ctrl+V 读 CF_DIB（RGBA→Dart 编码 PNG）。复制：图片右键菜单「复制图片」→ Web `navigator.clipboard` / Windows `copyImage` 写 CF_DIB |
| 2 | 发送键转圈/防连发 | Composer 拆 `_sending`（发送）与 `_uploading`（附件）两个状态；发送中发送键转圈并禁用，附件键独立转圈 |
| 3 | 编辑确定按钮 | 消息编辑器加「确定」（取消保留），回车仍可保存 |
| 4 | @ 提及 | 渲染正则本就支持英文名；补上中文输入法全角 `＠`（渲染/补全触发/未读提及判定三处），补全候选支持中英文 |
| 5+9 | 跨消息选择 + 复制 | 消息列表包 `SelectionArea`（跨条选择、Ctrl+C）；选区非空时右下角**固定**「复制所选 N 字」按钮——不再依赖右键菜单（右键会清空选区） |
| 6 | 发言间隔 | 服务端 `msgCooldown`：同一用户最小间隔 `SEND_INTERVAL_MS`（默认 1000ms，0=关闭），超限 429「发言太快」；客户端 429 时把原文放回输入框可重试 |
| 7/7.1 | 频道权限 + 改名 | Channel 新增 `created_by/speak_mode/allowed_speakers`；模式 all/owner(公告)/custom/none；创建对话框默认勾选「公告频道（仅我能发言）」；`PATCH /channels/:id` 改名/分组/权限（创建者或服主）；列表显示锁标 + 齿轮设置入口；受限频道输入框替换为「此频道仅特定成员可发言 + 去可发言的频道」；服务端 SendMessage 强制校验（DM 不限，服主恒可发言） |
| 8 | 修改密码 | `PATCH /users/me/password`（校验旧密码，bcrypt 重写，5 次/分限流）+ 个人资料对话框「修改密码…」 |
| 10 | 新建频道重复 | `createChannel` 的 REST 响应按 id 去重（WS `CHANNEL_CREATED` 通常先到，v1.3.4 投递串行化后必然如此） |

**v1.3.6**：修 Windows 端图片粘贴/复制失效（坑 29：键盘消息到不了顶层窗口）——
Dart 侧 Ctrl+V 主动拉取 + 桌面「粘贴图片」按钮 + 图片悬停工具条；原生 DIB 往返用独立 C++ 测试验证。

**头像压缩**：`_pickAvatar` 改用头像尺寸参数（`maxDim: 320, quality: 88, minBytes: 60KB`）——
之前复用聊天图片默认值 1600/82/500KB，手机原图省不下多少；实测 5.9MB(2000×1500) → 21.7KB(320×240)。

验证：API 层权限矩阵（owner/custom/none、403、服主兜底）、冷却 429、改密、密码错误 403；
UI 层（无头 Edge）新建频道只出现 1 次、受限频道显示锁定条、编辑有确定、发送键转圈且二次点击只发 1 条、
粘贴图片产生 `/api/upload` 且输入框插入 `![](/uploads/...)`、跨消息选择出现浮动复制按钮且鼠标移动不消失。

### 阶段 10：多端同时使用消息乱序修复（2026-11-19，v1.3.4）

用户反馈：安卓端与 Windows 端同时使用时后发的消息跑到前面。三层修复（坑 25）：

| 层 | 修复 |
|---|---|
| 服务端 | `Hub.DeliverLocal` 全程持 `deliverMu` 串行化——MemoryBus 在 REST 协程里同步回调，两条消息并发投递会交错 push，同一用户的不同连接可能收到相反顺序 |
| 客户端追加 | `_appendMessage` 按 ID（UUIDv7 字典序=时间序）二分插入到正确位置，不再盲目 append；到达顺序错也能摆正 |
| 客户端拉取 | `_loadMessages(before:null)` 整表替换改按 id 合并：保留已翻页的更早消息 + fetch 期间 WS 新到的更晚消息；并发 fetch 乱序响应也幂等 |

附带：WS 重连后补拉当前频道最新一页（断线期间漏掉的 MESSAGE_CREATE 之前永远不会补）。
验证：双无头页面并发互发 12 条（真实创建顺序本就乱序：a1,b1,a2,b5,…），两客户端渲染顺序均与 id 升序一致（修复前后各测一轮）。

---
### 阶段 12：v1.3.7（2026-11-20，安卓移动端导航栏）

用户反馈安卓上「导航栏被覆盖、无法操作」。根因：窄屏 `Scaffold.body` 没有 SafeArea，
ChatArea 自带顶栏顶到状态栏下面（☰ 点不到）；也没有系统栏配色。

| 改动 | 说明 |
|---|---|
| SafeArea | 窄屏 body 包 `SafeArea(top:true, bottom:false)`（底部仍由 Composer 的 padding.bottom 处理）；抽屉内容也包 SafeArea |
| 统一移动导航栏 `_MobileBar` | 高度 52：☰ 频道/服务器 · `#` + 频道名（或私信对方）· 分组 · 👥 成员；始终显示（未选频道时为 `Chord`），不再依赖 ChatArea 顶栏 |
| ChatArea.showHeader | 新增开关：宽屏 true（保留原顶栏），窄屏 false，避免两条栏叠加 |
| 系统栏配色 | `main()` 里 `SystemChrome.setSystemUIOverlayStyle`：状态栏透明 + 浅色图标，系统导航栏 #313338 + 浅色图标 |

验证：无头 Edge 390×844 —— 顶栏显示 `☰ # 公告 信息 👥`（不再有重复 #），点 ☰ 抽屉打开，
点 👥 成员 BottomSheet 打开。**安卓真机需用 Release APK 验证状态栏留白**（本机已装 Android SDK，可本地出包验证）。

### 阶段 13：v1.3.8（2026-11-20，用户群里的 4 项反馈）

| 项 | 修复 |
|---|---|
| 改头像/改名后聊天记录不刷新 | `_applyUser()` 统一处理 USER_UPDATE 与本机修改：me、成员列表、私信对端、**所有历史消息的 author 引用**（之前漏了最后一个，必须重登才刷新） |
| 服务器改名 | 后端 `PATCH /guilds/:id`（仅所有者，1-32 字）+ `GUILD_UPDATE` 广播 + 客户端「服务器设置」对话框（频道栏 ⋮ 菜单，仅所有者可见） |
| @ 弹出框：输入 @ 后失焦、Tab 无效 | 根因是 Composer 的 Column **条件插入**候选列表 → 下面的 TextField 被重建 → Web 端 DOM input 失焦（坑 32）。改为固定占位（空时 `SizedBox.shrink()`）+ `_applyMention` 里 setState；Tab 选中第一个候选。另加被 @ 提示：别人在其它频道 @ 我时弹 SnackBar「xxx 在 #频道 提到了你」 |
| 「无人（归档）」仍能发言 | `CanSpeak` 里 none 优先于服主放行（归档对所有人关闭）；客户端 `Channel.canSpeak` 同步；老数据 `speak_mode=''` 启动时迁移为 `all`（否则全显示锁标） |

顺带：宽屏 HomeShell 改用 `Scaffold`（原来裸 Material，导致 SnackBar 无宿主、@ 提示不显示，坑 33）；
频道行去掉多余的删除 X（保留长按删除），只留齿轮设置入口。

验证：模型单测（none 含服主全部 false）；API（改名 200/非所有者 403、none 三种身份 403）；
UI（头像改成红色后消息/成员/底栏即时变色、@bo + Tab → "@bob "、候选列表收起、@ 提示 SnackBar 出现）。

### 阶段 14：v1.3.9（2026-11-23，用户名唯一，已发布）

用户反馈：注册时用已存在的用户名会得到两个同名用户，数据混乱（@提及/搜索无法区分）。

原设计是 Discord 式 `username#discriminator`（同名不同编号允许共存），但本项目
**@提及、搜索、成员列表都只按 username 匹配**，同名直接产生歧义。

| 层 | 改动 |
|---|---|
| 数据 | 启动迁移 `migrateUsernameUnique`：先把历史重名改名为 `name_discriminator`（保留最早注册的那个），再建唯一索引 `idx_users_username`。日志会打印每一处改名（`journalctl -u chord-server` 可查） |
| 注册 | 先查重（409「用户名已被占用，请换一个」），并由唯一索引兜底并发；撞 1062 同样返回 409。discriminator 仍随机生成但只用于展示 |
| 改名 | `PATCH /users/me` 改用户名同样查重，撞唯一索引返回 409 |
| 客户端 | 无需改动，登录/注册页已有错误提示（直接显示服务端 message） |

验证（本机 MySQL）：注册 alice → 409；注册 ALICE（大小写）→ 409；注册新用户 → 200，再注册同名 → 409；
改名成 alice → 409；改名成新名字 → 200。迁移：手工插重复 bob#9999 并删索引 → 重启后自动改名 `bob_9999` 并重建索引。

**注意**：线上升级后如果历史上确实存在重名，**后来注册的那个人会被改名**（如 `test_1234`），
旧用户名将无法登录，需要用新名字登录（改名记录看 `journalctl -u chord-server | grep 重复用户名`）。

### 阶段 16：v1.4.1（2026-11-23，Logo 线条加粗）

用户反馈 v1.4.0 的图标"线条太细"。按原图重新校准：
- 描边 48 → 70（源坐标，约 +46%），图形放大到画布 68%（原 53%）
- 蓝色由 `#75CDFD` 加深到 `#45B8F0`，小尺寸下对比更清楚
- 重新导出 Web/Android/Windows/应用内全部图标；登录页 84px、rail 32px
- 另备两套备选方向（蓝底白标、白底卡片），对比图见 `scripts/guitest/shots/logo-variants.png`

### 阶段 15：v1.4.0（2026-11-23，品牌图标 + 消息搜索 + 跳转定位）

| 项 | 内容 |
|---|---|
| App Logo | 按用户提供的图（白底 + 黑椭圆 + 两个蓝环）用 Pillow 矢量重绘（`K=1.2` 内边距），导出：Web `icons/Icon-192/512` + `favicon.png`、Android `mipmap-*/ic_launcher.png`、Windows `resources/app_icon.ico`（16–256 多尺寸，exe 与托盘共用）、应用内 `client/assets/logo.png`（登录页 + 服务器 rail 顶部） |
| 消息搜索 | 后端 `GET /api/guilds/:id/search?q=`（成员校验；`INSTR(content,?)` 避免 % _ 通配；最多 50 条，时间倒序，`attachExtras` 补作者）；客户端 header/移动栏放大镜 → 搜索弹窗（350ms 防抖，显示 #频道、作者、时间、摘要），点击结果跨频道跳转并高亮 |
| 跳转定位 | 后端 `GET /api/channels/:id/messages?around=<id>`（前 25 + 后 25，正序）；客户端 `jumpToMessage`：必要时切频道、加载上下文、按索引估算滚动 + `ensureVisible` 对齐、琥珀色高亮 2.5s。搜索结果与**引用回复块点击**共用这条链路 |
| 桌面元数据 | `Runner.rc` 的 `FileDescription/ProductName` 由 `chord_client` 改为 `Chord`（任务栏/文件属性显示名） |

验证：API 搜索 `提及`/`cooldown` 均返回跨频道结果、`around` 含目标且正序；UI 搜索弹窗结果正确、
点击后跳到目标并高亮；引用块点击从最新消息跳到最早一条并高亮；移动端 390×844 顶栏出现搜索按钮；
Windows/Android 构建通过（图标与 RC 编译无碍）。

品牌色：logo 蓝 `#75CDFD`；manifest `theme_color` 改为该色、`background_color` 改白。

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
22. **Android release APK 连不上服务器**（v1.2.4 修复）：Flutter 模板的 `INTERNET` 权限只在 `debug/`、`profile/` 清单里，**`main/AndroidManifest.xml` 必须自己加** `<uses-permission android:name="android.permission.INTERNET"/>`，否则 release APK 完全断网；且 Android 9+ 默认禁明文 HTTP，服务器为 http:// 时必须加 `android:usesCleartextTraffic="true"`。两处叠加导致 v1.2.3 及之前的 APK 无法使用。附带修复：Android 上 `%APPDATA%`/`resolvedExecutable` 均不可用 → 登录态静默丢失；MainActivity 的 `chord/file` 通道新增 `storagePath` 方法返回 `filesDir`，storage_io 检测 Android 后走通道取路径。
23. **条件导入的 Web 兜底文件缺函数会拖垮 io 版编译**：`image_cache_dir_web.dart` 必须实现与 io 版**完全相同**的函数签名（曾漏 `deleteCacheDir` 导致 io 版报 undefined）。另外 GDI/绘制的位图、`dart:io` 的 HttpClient 都不可在 Web 条件分支出现（`HttpClient` 属 dart:io，Web 下载用 `package:http`）。
24. **「WS 预投递」与「按需 REST 加载」的判空冲突 → 顶部永久转圈**：`_appendMessage` 会给
    未打开的频道在 `messages` 映射里塞进残缺列表；`selectChannel` 若用 `messages[id] != null`
    判断"已加载"就会跳过拉取，`noMore` 永不置位，`chat_area` 里 `messages.length + 1` 的分页
    占位 spinner 就永远渲染（v1.3.3 起选中频道/私信一律拉最新一页修复）。**教训：缓存判空要
    区分"碰巧有数据"和"完整加载过"，最好用显式的已同步集合，别用 map 非空当信号。**
25. **多端同时发消息会乱序——投递并发交错 + 客户端按到达顺序 append**：
    MemoryBus 的 Publish 在保存消息的 REST 协程内同步执行，两台设备几乎同时发消息时两个协程
    并发跑受众解析+push，同一用户的不同连接可能以相反顺序收到两条消息；客户端 `_appendMessage`
    又只按到达顺序 append，顺序错了就永久错。修复：投递全程串行化（deliverMu）+ 客户端按
    UUIDv7 id 插入 + 拉取按 id 合并（幂等）。**教训：消息类系统里「显示顺序」必须由一个权威
    序（如时间有序 ID）决定，网络到达顺序永远不可信。**

26. **条件导出文件里不能再写同名实现**：`clipboard_image.dart` 既 `export ... if (dart.library.html)`
    又定义了同名函数（内容抛 UnsupportedError），**本地声明会遮蔽导出的平台实现**，运行时直接
    抛 "Unsupported operation: replaced by conditional export"（表现为整页灰屏）。共享类型放
    `clipboard_common.dart`，入口文件只留 export。
27. **Flutter Web 里 `dart:html` 的 FileReader 事件流不触发**：`reader.onLoadEnd.first` 在
    dart2js 产物中永不完成（同一环境用原生 JS FileReader 正常，80 字节可读）。改为在
    `web/index.html` 用 JS 读成 dataURL，派发 `CustomEvent('chord-paste-image', {detail: dataUrl})`，
    Dart 侧 `window.on['chord-paste-image']` 接收并 base64 解码（detail 用字符串，JS 对象跨
    dart:js 传递容易踩类型坑）。
28. **`SelectionArea` 上右键会清空选区**，默认工具条因此"点了就没了"。跨消息复制的可靠做法：
    `SelectionArea(onSelectionChanged:)` 记录选中文本，选区非空时显示**固定位置的浮动
    「复制所选」按钮**（不随鼠标移动消失），右键菜单只作为补充。
29. **顶层窗口收不到 WM_KEYDOWN（Windows 粘贴失效的根因）**：Flutter 的视图是子 HWND，
    键盘焦点在子窗口上，`FlutterWindow::MessageHandler` 的 `WM_KEYDOWN` 分支收不到；
    而且 `HandleTopLevelWindowProc` 在 switch 之前返回，会把键盘消息吃掉（v1.3.5 就是这样）。
    现在三层兜底：① Composer 的 `Focus.onKeyEvent` 检到 Ctrl+V → `readClipboardImage`
    主动向原生要剪贴板图；② 原生 WM_KEYDOWN 判断前移到 `HandleTopLevelWindowProc` 之前；
    ③ 桌面端输入框旁提供显式「粘贴图片」按钮（不依赖键盘/右键）。两条路径用
    「字节数 + 2 秒」去重，避免同一次 Ctrl+V 触发两次。
    原生 DIB 读写可用独立 C++ 测试验证（`clipboard_image.cpp` + 手工构造 RGBA 往返）。
32. **Column 里条件插入子组件会重建输入框 → Web 端失焦**：Composer 的候选列表/引用条如果写成
    `if (cond) widget`，插入时后续子节点索引整体后移，TextField 被当成新节点重建，DOM input
    重新挂载，焦点丢给 flutter-view（用户看到的就是「输入 @ 后光标跳出输入框，之后打不了字，
    Tab 也没反应」）。修法：**保留固定占位**（空时 `SizedBox.shrink()`），子节点数量/顺序恒定。
33. **宽屏布局没有 Scaffold 时 SnackBar 不显示且不报错**：HomeShell 宽屏分支原先是裸 `Material`，
    `ScaffoldMessenger` 找不到已注册的 Scaffold，SnackBar 进队列但永远不出现。宽屏也要用
    `Scaffold(body: Row(...))`。
31. **Gradle wrapper 发行版下载会重定向到 GitHub Releases（国内被墙）**：`services.gradle.org`
    307 → `github.com/gradle/gradle-distributions` → `release-assets.githubusercontent.com`，本机下不动。
    做法：从 `https://mirrors.cloud.tencent.com/gradle/` 下同版本 zip，**预置到
    `~/.gradle/wrapper/dists/gradle-<ver>-all/<hash>/`**（hash = base36(MD5(distributionUrl))，
    Python 一行可算；目录里要有解压好的 `gradle-<ver>/` 和 `.ok` 标记）。预置后 wrapper 直接复用，
    **不要改仓库里的 `gradle-wrapper.properties`**（否则 CI 也会走镜像）。本机已同时为官方 URL
    （`aca6g93cdtcf0oapcfka748qh`）与腾讯镜像 URL（`1rsjz3joo2ioxecfvvnmxyd43`）各缓存了一份。

36. **`SelectionArea` 会赢走子组件的 tap**：消息列表外层是 `SelectionArea`（跨消息选择），
    引用块这种「文字区域里的可点元素」用 `InkWell.onTap` 收不到点击（选择手势在竞技场胜出）。
    可靠做法是 `Listener(onPointerDown/onPointerUp)` 在原始指针层判定「按下→抬起位移 < 8px」= 点击。
37. **reverse `ListView.builder` 懒加载导致 ensureVisible 无效**：目标消息若在视口外根本没被 build，
    `GlobalKey.currentContext` 为 null，`Scrollable.ensureVisible` 什么也不会做（表现为"点了跳转但没反应"）。
    做法：① 跳转时把 `cacheExtent` 临时放大（4000），让目标附近条目被构建；② 先按
    `(len-1-index) * 平均高度` 估算 offset 粗跳，再 `ensureVisible` 精细对齐。

35. **线上库存在混用排序规则（collation），手写 SQL 要防 1267**：本地库所有列都是
    `utf8mb4_unicode_ci`（GORM 按 DSN 建表），线上部分后建的表是 MySQL 8 默认的
    `utf8mb4_0900_ai_ci`。用 `SET @uid='...'` + `WHERE user_id = @uid` 会报
    `Illegal mix of collations (utf8mb4_unicode_ci,IMPLICIT) and (utf8mb4_0900_ai_ci,IMPLICIT)`；
    跨表子查询（`messages.channel_id IN (SELECT id FROM dm_channels ...)`）同样会踩。
    手写运维 SQL 统一用 `BINARY` 逐字节比较（id 都是 ASCII，等价且不受 collation 影响）：
    `WHERE BINARY user_id = BINARY @uid`。Go 侧参数化查询不受影响（参数继承列 collation）。

34. **用户名唯一性不能只靠「用户名+编号」组合**：Discord 的 `name#discriminator` 允许同名，
    但前提是 UI 每一处都展示完整 tag。本项目 @提及/搜索只按 `username` 匹配，同名立刻产生歧义。
    收紧为**用户名全局唯一**时有两个坑：① `AutoMigrate` 直接加 `uniqueIndex` 遇到历史重复会失败，
    必须先去重再 `ALTER TABLE ... ADD UNIQUE INDEX`（见 `db.migrateUsernameUnique`）；
    ② 应用层先查重只是优化体验，**并发注册必须靠唯一索引兜底**（捕获 MySQL 1062 返回 409）。

30. **移动端全屏布局必须包 SafeArea**：窄屏 `Scaffold.body` 直接放内容时，顶部会被系统状态栏
    （时间/信号）压住、底部被手势条压住——安卓上表现为「顶栏的 ☰ 点不到」。做法：body 用
    `SafeArea(top: true, bottom: false)`，底部留给 Composer 自己的 `MediaQuery.padding.bottom`；
    Drawer 内容也要 SafeArea。另外用 `SystemChrome.setSystemUIOverlayStyle` 统一状态栏/导航栏配色与图标亮度。
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
| Android SDK | `F:\dev\runtimes\android-sdk`（platform 36 / build-tools 36.0.0 / platform-tools，cmdline-tools 19.0） | 2026-11-20 重装：原 `D:\Apps\android-sdk` 已不存在；licenses 已接受 |
| JDK 17 | `F:\dev\runtimes\jdk-17.0.21.1+2`（Microsoft OpenJDK 17.0.21.1） | Android 构建必需，`JAVA_HOME` 指向它 |
untimes\jdk-17.0.21.1+2`（Microsoft OpenJDK 17.0.21.1） | Android 构建必需，`JAVA_HOME` 指向它 |
untimes\jdk-17.0.21.1+2`（Microsoft OpenJDK 17.0.21.1） | Android 构建必需，`JAVA_HOME` 指向它 |
| VS Build Tools 2022 | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` | Windows 桌面构建 |
| gh CLI 2.104 | `D:\code\chrod\runtimes\bin\gh.exe` | 发 Release 用（见第八节） |
| 工作区 | `D:\code\chrod\`（仓库 `discord-like/`，产物 `dist/`，脚本 `deploy-scripts/`） | |

> 注意：历史文档中的 `F:\dev\runtimes\` 在本机**不存在**，实际工具链路径以上表为准。

---

## 八、构建与发布手册

### 8.1 构建

```bash
# 后端（Linux 静态二进制，供服务器）
# VERSION 打进 /api/health，用于客户端版本互查（本地不传则为 dev）
cd server && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath   -ldflags="-s -w -X chord/server/internal/handlers.Version=$VERSION" -o <out>/chord-server ./cmd/server
# 同样产出 serveweb / redisprobe（cmd/serveweb、cmd/redisprobe）
go vet ./... && go test ./internal/handlers/     # 测试

# Web（必须 cd client/；默认地址按需改）
# ⚠️ 必须带 --no-web-resources-cdn：否则 CanvasKit 从 www.gstatic.com 拉（国内被墙 → 白屏/极慢）
# ⚠️ 必须带 --web-content-hash：产物文件名带内容哈希 → serveweb 才能给 immutable 长缓存（二次访问零下载）
cd client && flutter build web --release --no-web-resources-cdn --web-content-hash \n  --dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081 --dart-define=CHORD_VERSION=$VERSION
# 校验产物含新代码（关键！）：
python -X utf8 -c "d=open('build/web/main.dart.js',encoding='utf-8',errors='ignore').read(); print(d.count(r'\u53d1\u9001\u6587\u4ef6'), d.count('/api/upload'))"

# Windows 客户端（产物 build/windows/x64/runner/Release → 改名 exe 为 Chord聊天.exe，三件套同目录打 zip）
# 桌面/移动用全量字体（不缺生僻字）；Web 才用子集
cp client/assets/fonts/full/*.ttf client/assets/fonts/
cd client && flutter build windows --release --dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081 --dart-define=CHORD_VERSION=$VERSION

# Android（推荐 arm64；另两个 ABI 用 --split-per-abi 自动产出；同样先用全量字体）
# 本机需先导出（Git Bash）：JAVA_HOME / ANDROID_HOME / ANDROID_SDK_ROOT
export JAVA_HOME="F:\dev\runtimes\jdk-17.0.21.1+2"
export ANDROID_HOME="F:\dev\runtimes\android-sdk" ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="/f/dev/runtimes/jdk-17.0.21.1+2/bin:$PATH"
cd client && flutter build apk --release --split-per-abi --dart-define=CHORD_DEFAULT_BASE=http://129.226.159.168:8081 --dart-define=CHORD_VERSION=$VERSION
```

### 8.2 打包服务器部署包

```bash
# 包目录结构（package/）：chord-server serveweb redisprobe install.sh update.sh 部署说明.md web/
tar czf chord-deploy.tar.gz package/            # 全量
cd package && tar czf chord-web-update.tar.gz web/   # 仅前端
```

### 8.3 发布 Release

**版本节奏（用户约定，2026-11-19）**：不要频繁发版——小改动/小修复先攒着，
一批一起出一个补丁号；补丁号（第三位）可以用到 **99**（v1.3.1 → v1.3.99），
用完再考虑进位 v1.4；次版本号留给真正的功能性升级（对应 ROADMAP 的大项）。
文档、CI 调整这类不发版的改动只推 main、不打 tag。

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
curl -s http://129.226.159.168:8081/api/health                       # {"status":"ok","version":"v1.x.y"}，版本必须等于刚发的 tag
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

**线上状态（2026-11-18 核对）**：服务器 Web 产物最后确认到 **v1.1.7**（bundle `main.dart.03aeab75.js`，
用户此后是否跑过 v1.1.8/v1.1.9 的 update.sh web 未经确认）；**后端二进制仍是 v1.1.3**。
核对方法：`curl -s http://129.226.159.168:3000/flutter_bootstrap.js | grep -oE "main\.dart\.[a-f0-9]+\.js"`
与本地 `client/build/web/` 的文件名比对。
- 要启用 v1.2.0 引用回复：`sudo curl -fLo /opt/chord/update.sh https://github.com/zhumin2/discord-like/releases/latest/download/update.sh`
  然后 `sudo bash /opt/chord/update.sh server && sudo bash /opt/chord/update.sh web`
  （server 模式换 chord-server 并自动迁移 `reply_to_id` 列；v1.2.1+ 的 update.sh 才支持 server 模式，所以必须先刷新脚本）。

**v1.1 遗留**：TLS 待域名（`deploy/caddy/Caddyfile` 已就绪）；CDN 未接入；每日备份 cron 未配置；
APK 为 debug 签名；Windows 无代码签名。

**v1.2.x 遗留 / 待办**：
- 跨境带宽仍是最大瓶颈（实测单连接 8-16KB/s，首屏约需 6 分钟）→ 需 BBR / CDN / 升带宽（见阶段 7）
- 引用回复：点击引用块**不会跳转**到原消息（未实现滚动定位）
- 桌面端：不做开机自启；托盘角标不做点击跳转到具体会话；Taskbar 名称仍为 `chord_client`（Runner.rc）
- 限流为单机内存实现，多实例部署需换 Redis（未做）

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

### 8.7 桌面单实例 + 托盘未读角标（v1.2.3）

- **单实例**：`main.cpp` 创建命名互斥量 `Local\ChordChatSingleInstance`；已存在时
  `FindWindowW(nullptr, L"Chord")` 找到原窗口 → `ShowWindow` + `PostMessage(WM_APP+2)`（让原实例从托盘恢复）
  然后退出。窗口标题必须保持 `"Chord"`，否则 FindWindow 失效。
- **托盘未读角标**：Dart 监听 `chatProvider.summary` 求和 → `MethodChannel('chord/app').setBadge(int)`；
  原生 `TrayManager::SetBadge` 更新 tooltip（"Chord - N 条未读"）并用 GDI 在图标右上角画红圈数字（>9 显示 9+）。
  GDI 画的 32bpp 位图 alpha 会是 0（全透明），必须用 `ForceOpaque()` 把 alpha 置 255。
- 验证方式：`SystemTray.NormalButton` 的 UI Automation Name = tooltip；导出图标 BMP 目视检查数字。

### 8.6 桌面端最小化到托盘（v1.2.2）

聊天客户端与控制台都实现了"点 X 隐藏到托盘"（原生 Win32，无插件）：

- 客户端：`client/windows/runner/tray_manager.{h,cpp}`；控制台：`gui/windows/runner/tray_manager.{h,cpp}`
- `flutter_window.cpp` 拦截 `WM_CLOSE` → `HideWindowToTray`；托盘回调 `WM_APP+1`
- 托盘菜单：客户端「打开 Chord / 退出」；控制台「打开控制台 / 打开网页 / 退出」
- 隐藏后进程与 WebSocket 继续运行（消息照常接收），只有托盘菜单「退出」真正退出
- 修改这两个文件同样需要 UTF-8 BOM（runner 已加 `/utf-8`，BOM 是保险）
- 验证：PostMessage WM_CLOSE 后 `IsWindowVisible=false` 且进程存活

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
