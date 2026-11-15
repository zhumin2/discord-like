#!/usr/bin/env bash
# =============================================================
# Chord 服务管理脚本（Git Bash）
# 用法:
#   bash chord.sh start  [api|web|mysql]   启动（缺省全部）
#   bash chord.sh stop   [api|web|mysql]   停止（缺省全部；mysql 停止为优雅关闭）
#   bash chord.sh restart[api|web|mysql]   重启
#   bash chord.sh status                   查看各服务状态
#   bash chord.sh logs   [api|web|mysql]   查看日志（tail -f，Ctrl+C 退出）
# 说明:
#   - API 监听 :8081，Web 托管 :3000，MySQL :3306（库名 chord）
#   - 日志写入 /tmp/chord-{api,web,mysql}.log
#   - stop 全部时也会尝试清理遗留的旧版 8080 进程
# =============================================================
set -u
cd "$(dirname "$0")"

RUNTIMES=${RUNTIMES:-/f/dev/runtimes}
PORT_API=8081
PORT_WEB=3000
PORT_MYSQL=3306
LOG_DIR=/tmp

cgreen='\033[0;32m'; cred='\033[0;31m'; cyellow='\033[0;33m'; cend='\033[0m'
ok()   { echo -e "  ${cgreen}✓${cend} $*"; }
bad()  { echo -e "  ${cred}✗${cend} $*"; }
info() { echo -e "  ${cyellow}•${cend} $*"; }

# ---------- 探测 ----------
pid_on_port() {
  netstat -ano 2>/dev/null | grep -E "[:.]$1[[:space:]]" | grep -i LISTENING | head -1 | awk '{print $NF}'
}
api_up()   { curl -s --max-time 2 "http://127.0.0.1:$PORT_API/api/health" >/dev/null 2>&1; }
web_up()   { curl -s --max-time 2 "http://127.0.0.1:$PORT_WEB/" >/dev/null 2>&1; }
mysql_up() { "$RUNTIMES/mysql/bin/mysqladmin" --no-defaults -u root ping >/dev/null 2>&1; }

# ---------- 启动 ----------
start_fakeredis() {
  # best-effort：6379 未开时启动 Redis 兼容开发服务器（API 会自动检测并使用）
  if pid_on_port 6379 >/dev/null; then ok "Redis :6379 已在运行"; return 0; fi
  info "启动 Redis(开发兼容) :6379 ..."
  if [ -f server/fakeredis.exe ]; then
    (cd server && cmd //c "start /b fakeredis.exe" >/dev/null 2>&1)
  else
    (cd server && GOPROXY=https://goproxy.cn,direct go run ./cmd/fakeredis >"$LOG_DIR/chord-fakeredis.log" 2>&1 &)
  fi
  local i; for i in $(seq 1 10); do pid_on_port 6379 >/dev/null && break; sleep 1; done
  pid_on_port 6379 >/dev/null && ok "Redis 就绪 :6379" || info "Redis 未启动（API 将自动降级为进程内模式，不影响功能）"
  return 0
}

start_mysql() {
  if mysql_up; then ok "MySQL 已在运行 :$PORT_MYSQL"; return 0; fi
  if [ ! -d "$RUNTIMES/mysql/data/mysql" ]; then
    info "初始化 MySQL 数据目录..."
    "$RUNTIMES/mysql/bin/mysqld" --no-defaults --initialize-insecure \
      --datadir="$(cygpath -w "$RUNTIMES/mysql/data")" --character-set-server=utf8mb4 || return 1
  fi
  info "启动 MySQL 8 :$PORT_MYSQL ..."
  ("$RUNTIMES/mysql/bin/mysqld" --no-defaults \
      --datadir="$(cygpath -w "$RUNTIMES/mysql/data")" \
      --port=$PORT_MYSQL --character-set-server=utf8mb4 --console \
      >"$LOG_DIR/chord-mysql.log" 2>&1 &)
  local i; for i in $(seq 1 30); do mysql_up && break; sleep 1; done
  if mysql_up; then
    "$RUNTIMES/mysql/bin/mysql" --no-defaults -u root \
      -e "CREATE DATABASE IF NOT EXISTS chord CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    ok "MySQL 就绪（日志 $LOG_DIR/chord-mysql.log）"
  else
    bad "MySQL 启动失败，查看 $LOG_DIR/chord-mysql.log"; return 1
  fi
}

start_api() {
  if api_up; then ok "API 已在运行 :$PORT_API"; return 0; fi
  if [ -f server/chord-server.exe ]; then
    info "启动 chord-server.exe :$PORT_API ..."
    (cd server && cmd //c "start /b chord-server.exe" >/dev/null 2>&1)
  else
    info "启动 Go 后端 :$PORT_API ..."
    (cd server && GOPROXY=https://goproxy.cn,direct go run ./cmd/server >"$LOG_DIR/chord-api.log" 2>&1 &)
  fi
  local i; for i in $(seq 1 40); do api_up && break; sleep 1; done
  if api_up; then ok "API 就绪 http://127.0.0.1:$PORT_API（日志 $LOG_DIR/chord-api.log）"
  else bad "API 启动失败，查看 $LOG_DIR/chord-api.log"; return 1; fi
}

start_web() {
  if web_up; then ok "Web 已在运行 :$PORT_WEB"; return 0; fi
  if [ ! -f client/build/web/index.html ]; then
    info "首次构建 Flutter Web（约 1-3 分钟）..."
    export PUB_HOSTED_URL=https://pub.flutter-io.cn
    export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
    (cd client && flutter build web --release) || { bad "前端构建失败"; return 1; }
  fi
  info "托管静态站点 :$PORT_WEB ..."
  if [ -f server/serveweb.exe ]; then
    (cd server && cmd //c "start /b serveweb.exe -dir ..\\client\\build\\web -port $PORT_WEB" >/dev/null 2>&1)
  else
    (cd server && go run ./cmd/serveweb \
        -dir "$(cygpath -w "$(pwd)/client/build/web")" -port $PORT_WEB \
        >"$LOG_DIR/chord-web.log" 2>&1 &)
  fi
  local i; for i in $(seq 1 20); do web_up && break; sleep 1; done
  if web_up; then ok "Web 就绪 http://127.0.0.1:$PORT_WEB（日志 $LOG_DIR/chord-web.log）"
  else bad "Web 启动失败，查看 $LOG_DIR/chord-web.log"; return 1; fi
}

# ---------- 停止 ----------
kill_port() { # $1=端口 $2=名称
  local pid killed=0
  while pid=$(pid_on_port "$1"); do
    [ -z "$pid" ] && break
    info "结束 $2 (PID $pid, 端口 $1)"
    if taskkill //F //PID "$pid" >/dev/null 2>&1; then
      killed=1; sleep 1
    else
      bad "无法结束 PID $pid（权限不足？请用管理员终端重试，或重启电脑后自然释放）"
      return 1
    fi
  done
  [ $killed -eq 0 ] && info "$2 未在运行"
  return 0
}

stop_api() { kill_port $PORT_API "API"; }
stop_web() { kill_port $PORT_WEB "Web"; }

stop_mysql() {
  if ! mysql_up; then info "MySQL 未在运行"; return 0; fi
  info "优雅关闭 MySQL ..."
  if "$RUNTIMES/mysql/bin/mysqladmin" --no-defaults -u root shutdown >/dev/null 2>&1; then
    local i; for i in $(seq 1 15); do mysql_up || break; sleep 1; done
    mysql_up && { bad "MySQL 未能关闭"; return 1; }
    ok "MySQL 已关闭"
  else
    bad "关闭失败（权限不足？）"; return 1
  fi
}

stop_legacy_8080() { # 清理历史遗留的旧版 8080 进程（若有）
  if pid_on_port 8080 >/dev/null; then
    kill_port 8080 "旧版 API(8080, 遗留)"
  fi
}

# ---------- 状态 ----------
do_status() {
  echo "=== Chord 服务状态 ==="
  if mysql_up; then ok "MySQL   :$PORT_MYSQL 运行中 (PID $(pid_on_port $PORT_MYSQL))"
  else bad "MySQL   :$PORT_MYSQL 未运行"; fi
  if api_up; then ok "API     :$PORT_API 运行中 (PID $(pid_on_port $PORT_API))"
  else bad "API     :$PORT_API 未运行"; fi
  if web_up; then ok "Web     :$PORT_WEB 运行中 (PID $(pid_on_port $PORT_WEB))"
  else bad "Web     :$PORT_WEB 未运行"; fi
  echo "    网页端: http://127.0.0.1:$PORT_WEB   演示账号: alice/bob/carol (密码 123456)"
}

# ---------- 分发 ----------
target="${2:-all}"
case "${1:-}" in
  start)
    case "$target" in
      mysql) start_mysql ;;
      api)   start_api ;;
      web)   start_web ;;
      all)   start_mysql && start_fakeredis && start_api && start_web
             echo ""; echo "============================================"
             echo "  Chord 已启动"
             echo "  网页端:  http://127.0.0.1:$PORT_WEB"
             echo "  API:     http://127.0.0.1:$PORT_API"
             echo "  演示账号: alice / bob / carol（密码 123456）"
             echo "  邀请码:   demo2024"
             echo "============================================" ;;
      *) bad "未知服务: $target（可选 api|web|mysql）"; exit 1 ;;
    esac ;;
  stop)
    case "$target" in
      mysql) stop_mysql ;;
      api)   stop_api ;;
      web)   stop_web ;;
      all)   stop_api; stop_web; stop_legacy_8080; stop_mysql
             ok "全部服务已停止" ;;
      *) bad "未知服务: $target（可选 api|web|mysql）"; exit 1 ;;
    esac ;;
  restart)
    bash "$0" stop "$target" && bash "$0" start "$target" ;;
  status)
    do_status ;;
  logs)
    case "$target" in
      api) tail -f "$LOG_DIR/chord-api.log" ;;
      web) tail -f "$LOG_DIR/chord-web.log" ;;
      mysql) tail -f "$LOG_DIR/chord-mysql.log" ;;
      all) tail -f "$LOG_DIR"/chord-*.log ;;
      *) bad "未知服务: $target"; exit 1 ;;
    esac ;;
  *)
    grep '^# ' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
