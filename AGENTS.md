# AGENTS.md — Chord 项目交接文档

> 本文档面向接手本项目的 AI agent / 开发者，记录项目全貌、历史决策、环境事实与已知坑。
> 最后更新：2026-11-15

## 一、项目是什么

**Chord** —— 一个模仿 Discord 的实时聊天产品，已完成可运行 MVP：

| 端 | 形态 | 入口 |
|---|---|---|
| Web / PWA | Flutter Web，浏览器访问，可加主屏 | `http://127.0.0.1:3000` |
| **Windows 桌面客户端** | 原生窗口 1200×800 | `app\Chord聊天.exe`（启动器：`启动聊天客户端.bat`） |
| **服务管理控制台（GUI）** | Laragon 风格托盘程序 560×640 | `console\Chord控制台.exe`（启动器：`启动控制台.bat`） |
| 命令行管理 | Git Bash 脚本 | `chord.sh start/stop/restart/status/logs` |

功能：注册登录(JWT)、服务器/邀请码、频道分组、实时消息(WS)、编辑删除、Markdown-lite 渲染、@提及、表情回应、私信 DM、在线状态、typing 提示、未读/提及数、响应式(PC 四栏/手机单栏+抽屉)、PWA。

**演示账号**：alice / bob / carol，密码均为 `123456`；演示服务器邀请码 `demo2024`。

## 二、技术栈与目录结构

- **后端** Go 1.27：Gin + gorilla/websocket + GORM(MySQL) + go-redis
- **前端** Flutter 3.50 stable（Web + Windows 桌面同一套代码），Riverpod 3.x 状态管理
- **存储** MySQL 8（持久化）+ Redis（在线状态/presence、事件扇出/pub-sub，**可选**）

```
├── server/                    Go 后端
│   ├── cmd/server/            主服务（REST + WS 网关，编译产物 chord-server.exe）
│   ├── cmd/serveweb/          Flutter Web 静态托管（serveweb.exe，含 wasm MIME + SPA 回退）
│   ├── cmd/fakeredis/         Redis 协议兼容开发服务器（miniredis + TCP 透传固定 6379）
│   ├── cmd/redisprobe/        Redis 状态探针（presence 键 / -sub 订阅验证）
│   ├── internal/
│   │   ├── config/            .env + 默认值（REDIS_ADDR 默认 127.0.0.1:6379，连不上自动降级）
│   │   ├── models/            GORM 模型（UUIDv7 主键 = 消息分页游标）
│   │   ├── auth/              JWT + bcrypt
│   │   ├── handlers/          REST（auth/guild/message/dm 四组）
│   │   ├── ws/                WebSocket Hub：连接管理、事件路由、presence、typing
│   │   ├── bus/               事件总线抽象：MemoryBus（单实例）/ redisBus（多实例 pub/sub）
│   │   └── db/                连接迁移 + 演示数据 seed
│   ├── chord-server.exe       ⚠️ 预编译产物（GUI/chord.sh 优先使用）
│   └── .data/jwt_secret       ⚠️ JWT 密钥（绝不入库/上传）
├── client/                    Flutter 聊天应用（Web + Windows）
│   ├── lib/state/app_state.dart   核心：Riverpod ChatNotifier（REST+WS→统一状态）
│   ├── lib/api_client.dart        REST 客户端
│   ├── lib/gateway.dart           WS 网关（心跳 25s + 指数退避重连）
│   ├── lib/storage.dart           条件导入 KV 存储（桌面=JSON 文件 / Web=localStorage）
│   ├── lib/widgets|screens/       UI（消息/面板/对话框/响应式外壳）
│   ├── assets/fonts/              内置 Noto Sans SC（中文必需，见"坑"）
│   └── windows/runner/            桌面壳（托盘最小化在 tray_manager.cpp）
├── gui/                       服务管理控制台（独立 Flutter Windows 工程）
│   └── windows/runner/        托盘/关闭拦截 = 原生 Win32（tray_manager.cpp）
├── console/                   控制台部署产物（Chord控制台.exe）
├── app/                       桌面客户端部署产物（Chord聊天.exe）
├── scripts/guitest/           GUI 黑盒走查（playwright-core + 无头 Edge，token 预注入）
├── chord.sh / chord.bat       服务管理（start/stop/restart/status/logs [api|web|mysql]）
├── start-dev.sh / stop-dev.sh chord.sh 的 start/stop 快捷方式
├── 启动控制台.bat / 启动聊天客户端.bat
└── docker-compose.yml         mysql + redis（有 Docker 的环境用）
```

## 三、架构要点（为什么这样设计）

1. **消息 ID 用 UUIDv7**（时间有序）——历史消息分页直接 `WHERE id < cursor`，无需额外排序列。
2. **WS 事件与 REST 分离**：写操作走 REST（可靠、可校验），结果以 WS 事件广播给所有连接（含作者本人，客户端按消息 ID 去重）。
3. **事件总线抽象 `bus.Bus`**：`MemoryBus`（单实例，进程内回调）与 `redisBus`（PUBLISH/SUBSCRIBE chord:events）同接口；API 默认连 127.0.0.1:6379，**连不上自动降级**。多实例部署时事件跨实例扇出就靠它。
4. **presence 键**：`presence:<uid>`（TTL 60s），心跳续期（`Hub.SetActivity`）；成员列表在线状态 = 本地连接表优先、Redis 键兜底（跨实例感知）。
5. **前端存储抽象 `storage.dart`**：条件导入——桌面 JSON 文件（%APPDATA%\Chord\storage.json）/ Web localStorage（自动迁移旧 `flutter.<key>` 键）。**刻意不依赖任何 Flutter 平台插件**，否则 Windows 构建需要开发者模式（符号链接限制）。
6. **服务管理三件套行为一致**：GUI / chord.sh / 手动命令都优先使用预编译 exe（chord-server.exe / serveweb.exe），缺失时自动编译（GUI 用合并系统环境变量的 Process.run）。
7. **控制台托盘**：关闭窗口=隐藏到托盘（原生 Win32 `tray_manager.cpp`，WM_CLOSE 拦截），只有托盘菜单「退出」真正退出，且不停服务。

## 四、运行环境事实（本机专属）

- **运行时全部便携化**，无管理员权限：`F:\dev\runtimes\`（flutter/、mysql/ 含 data 目录、downloads/）。MySQL root 无密码，端口 3306，库名 chord。
- **端口**：API 8081、Web 3000、MySQL 3306、Redis(开发) 6379。⚠️ 有一个**无法 kill 的遗留 8080 进程**（旧版 bug 服务，沙箱保护），重启电脑才释放——8081 端口由此而来。
- **国内网络**：GitHub HTTPS 被墙，**SSH 22 端口可用**（密钥 `~/.ssh/id_ed25519_github`，账号 `zhumin2`，~/.ssh/config 已配 443 通道）。Go/Flutter/pub 依赖一律走镜像：`GOPROXY=https://goproxy.cn,direct`、`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。
- **ZCode 沙箱**：从沙箱内启动的跨会话进程可能无法被 taskkill 终止（拒绝访问）；GUI/chord.bat 由用户双击启动的进程完全可控。
- MySQL/API/Redis 数据特点：presence/typing 是临时数据（fakeredis 重启即清）；唯一需要持久化的秘密是 `server/.data/jwt_secret`。

## 五、踩坑记录（重要！避免重蹈）

1. **GORM 只自动填充 `CreatedAt/UpdatedAt`**；其他 time.Time 字段（如 `GuildMember.JoinedAt`）零值 `0001-01-01` 会被 MySQL 严格模式拒绝 → 事务静默回滚。新增模型必须显式赋值（曾导致"创建服务器 500"）。
2. **Flutter Windows：宽屏布局缺 `Material` 祖先** → 所有 Text 渲染为红字+黄双下划线、ExpansionTile 画成灰块（是框架调试样式，不是业务 bug）。HomeShell 宽屏分支必须包 `Material`。
3. **中文显示方框**：CanvasKit 默认从 fonts.gstatic.com 拉字体（被墙）→ 必须内置 NotoSansSC（已在 pubspec fonts 注册，FontManifest 兜底即生效）。
4. **GUI 的 C++ 源文件含中文注释**：必须 UTF-8 BOM + runner CMakeLists 加 `/utf-8`（默认 /WX 下 GBK 代码页触发 C4819 编译失败）。
5. **Process.run 的 `environment` 参数是整体替换**：必须 `{...Platform.environment, ...extra}` 合并，否则 go build/flutter build 缺系统变量直接失败。
6. **`flutter create` 后同端口僵尸进程**：TaskStop 杀不死 dartvm 子进程，导致新构建"看似部署实则旧代码在服务"。改端口/杀进程（`netstat -ano` + `taskkill /F /PID`）后复测。
7. **Flutter Web + 无头浏览器自动化**：canvas 渲染 DOM 快照为空，需先 `dispatchEvent(click)` 激活 `flt-semantics-placeholder`；截图偶发超时，改视口 ±1px 可解；Prepared token 注入键为 `flutter.<key>` 且值需 `JSON.stringify`（SharedPreferences 语义）。
8. **shared_preferences 插件使 Windows 构建需要开发者模式**（符号链接）→ 已移除并自研 storage 抽象。**不要给 client/gui 加任何平台插件**，托盘/窗口行为全走原生 C++。
9. **miniredis 只支持随机端口**：fakeredis 用 TCP 字节透传（net.Listen 6379 → Dial miniredis）固定端口，Redis 协议是纯流，透传无损。
10. **Windows 控制台 GBK**：含中文的 bash/python 脚本输出需 `PYTHONIOENCODING`/`-X utf8`；C++/SQL 交互避免在命令行内联中文字面量（会被转码污染）。

## 六、验证方式

- **后端冒烟**：`server/cmd/redisprobe`（presence 键）、curl `/api/health`
- **GUI 黑盒**：`scripts/guitest/walk.mjs` / `final-walk.mjs`（双账号实时消息、桌面/移动双视口、截图到 shots/）
- **全链路**：双浏览器窗口登录不同演示账号互发消息；移动端 375×812 视口 + 抽屉
- 运行 GUI 测试前先 `cd scripts/guitest && npm i`（playwright-core + 系统 Edge）

## 七、已知限制 / 未做事项（按价值排序的下一步）

1. **语音频道**（WebRTC mesh）——已留 ws/ 与频道模型扩展点
2. **文件/图片上传**——消息表 content 为纯文本，需加 attachment 表与静态服务
3. **角色权限体系**——目前仅 owner/member 两级；权限点已在 owner 判断处集中
4. **好友系统 / 消息搜索 / 推送通知**（Web Push / WNS）
5. **生产部署**：真 Redis（Docker/WSL/Memurai）+ 多实例 + Nginx TLS 反代（WS 走 wss）
6. **测试**：目前无单元测试，验证靠 scripts/guitest 黑盒走查；可补 Go httptest 与 widget 测试
7. 控制台 GUI 可加：MySQL/API 的资源占用显示、开机自启、日志级别切换

## 八、一键恢复环境（新机器/重置后）

```bash
# 1. 运行时：Flutter 3.50 (含 Windows desktop) + MySQL 8 便携版放 F:\dev\runtimes\
# 2. 数据库：chord.sh start mysql 会自动建库；空库自动 seed 演示数据（SEED_DEMO=true）
# 3. 全套启动：bash chord.sh start all   （MySQL → fakeredis → API → Web）
# 4. 桌面端/控制台：flutter build windows --release（client/ 与 gui/ 各一次）
# 5. 验证：bash chord.sh status && cd server && go run ./cmd/redisprobe
```

## 九、中文名候选（待定，2026-11-15 讨论未决）

当前对外名仍是 **Chord**。中文名候选及利弊分析（选定后落地位置：桌面窗口标题
`client/windows/runner/main.cpp`、托盘 `gui/windows/runner/tray_manager.cpp`、Web 标题
`client/web/index.html`+`manifest.json`、登录页、README）：

| 候选 | 亮点 | 短板 |
|---|---|---|
| 共鸣 | 音乐×情感双关，传播性最好 | 品类感缺失；重名/搜索极差；口语"你共鸣了吗"不顺；气质偏播客文艺 |
| 同频 | 年轻化口语（"同频的人"），和弦物理本质 | 品类暗示中等；重名一般 |
| 合鸣 | 琴瑟合鸣，雅致 | 书卷气重，口语弱 |
| 声部 | 结构隐喻最妙（服务器=合唱、频道=声部） | 更适合做世界观文案而非名字 |
| **弦外**（后补，评价最高） | Chord=弦直译；"弦外之音"=聊天的言外之意；搜索唯一性极高；气质可硬可软 | 尚无重名调研反例 |

决策原则：游戏/兴趣社群定位 → 弦外/同频更强；泛情感文艺社区 → 共鸣成立。**尚未拍板。**
