#!/usr/bin/env bash
# =====================================================================
# Chord 一键部署脚本（在服务器上、解压后的包目录内执行）
#
# 前置条件（本脚本不负责安装）：
#   - MySQL 8 已运行在 127.0.0.1:3306（root 有密码）
#   - Redis 已运行在 127.0.0.1:6379（无密码，可选；连不上自动降级）
#   - systemd 可用（Ubuntu / Debian / CentOS 等）
#
# 用法：
#   sudo MYSQL_PASS='数据库root密码' bash install.sh
#   # 可用环境变量覆盖默认参数，例如：
#   # sudo SERVER_IP=1.2.3.4 MYSQL_PASS='xxx' bash install.sh
# 注意：出于安全，本脚本不内嵌数据库密码，必须通过 MYSQL_PASS 传入。
# =====================================================================
set -euo pipefail

# ===== 部署参数（按需修改或用环境变量覆盖） =====
SERVER_IP="${SERVER_IP:-129.226.159.168}"   # 对外访问 IP（用于 CORS 白名单）
INSTALL_DIR="${INSTALL_DIR:-/opt/chord}"    # 安装目录
MYSQL_ADDR="${MYSQL_ADDR:-127.0.0.1:3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-}"   # 必传：sudo MYSQL_PASS='数据库root密码' bash install.sh
REDIS_ADDR="${REDIS_ADDR:-127.0.0.1:6379}"  # 留空 = 单实例进程内模式
API_PORT="${API_PORT:-8081}"
WEB_PORT="${WEB_PORT:-3000}"
SEED_DEMO="${SEED_DEMO:-true}"              # 空库自动写入演示数据 alice/bob/carol
RUN_USER="${RUN_USER:-chord}"

C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_OFF='\033[0m'
info()  { echo -e "${C_GREEN}[部署]${C_OFF} $*"; }
warn()  { echo -e "${C_YELLOW}[注意]${C_OFF} $*"; }
fail()  { echo -e "${C_RED}[失败]${C_OFF} $*"; exit 1; }

# ---------- 0. 权限与产物检查 ----------
[ "$(id -u)" = "0" ] || fail "请用 root/sudo 执行：sudo MYSQL_PASS='数据库root密码' bash install.sh"
[ -n "${MYSQL_PASS}" ] || fail "缺少数据库密码，请用：sudo MYSQL_PASS='数据库root密码' bash install.sh"
[ -f chord-server ] || fail "当前目录缺少 chord-server（Linux amd64 后端）"
[ -f serveweb ]     || fail "当前目录缺少 serveweb（Linux amd64 静态托管）"
[ -d web ] && [ -f web/index.html ] || fail "当前目录缺少 web/（Flutter Web 构建产物）"
command -v systemctl >/dev/null || fail "未检测到 systemd"

# ---------- 1. 目录布局 ----------
info "安装目录：${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/server" "${INSTALL_DIR}/web/htdocs" "${INSTALL_DIR}/server/.data"
install -m 0755 chord-server "${INSTALL_DIR}/server/chord-server"
install -m 0755 serveweb     "${INSTALL_DIR}/web/serveweb"
cp -r web/. "${INSTALL_DIR}/web/htdocs/"
# update.sh 装到 /opt/chord，供 update.sh web|full 全局调用（包内缺失则跳过）
if [ -f update.sh ]; then
    install -m 0755 update.sh "${INSTALL_DIR}/update.sh"
fi

# ---------- 2. 运行用户 ----------
if ! id "${RUN_USER}" >/dev/null 2>&1; then
    info "创建系统用户 ${RUN_USER}"
    useradd --system --no-create-home --shell /usr/sbin/nologin "${RUN_USER}" \
        || useradd --system --no-create-home --shell /sbin/nologin "${RUN_USER}"
fi
chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}"

# ---------- 3. 应用配置 .env ----------
info "写入 ${INSTALL_DIR}/server/.env"
cat > "${INSTALL_DIR}/server/.env" <<EOF
PORT=${API_PORT}
DB_DSN=${MYSQL_USER}:${MYSQL_PASS}@tcp(${MYSQL_ADDR})/chord?charset=utf8mb4&parseTime=True&loc=Local
REDIS_ADDR=${REDIS_ADDR}
JWT_SECRET=
SEED_DEMO=${SEED_DEMO}
CLIENT_ORIGIN=http://${SERVER_IP}:${WEB_PORT}
UPLOAD_DIR=${INSTALL_DIR}/data/uploads
EOF
chmod 600 "${INSTALL_DIR}/server/.env"
chown "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}/server/.env"
mkdir -p "${INSTALL_DIR}/data/uploads"
chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}/data"

# ---------- 4. 数据库初始化（幂等，失败不阻断） ----------
DB_HOST="${MYSQL_ADDR%%:*}"; DB_PORT="${MYSQL_ADDR##*:}"
SQL="CREATE DATABASE IF NOT EXISTS chord CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
MYSQL_CLI=""
for c in mysql /usr/local/mysql/bin/mysql; do
    command -v "$c" >/dev/null 2>&1 && { MYSQL_CLI="$c"; break; }
done
if [ -n "${MYSQL_CLI}" ]; then
    info "创建数据库 chord（若不存在）"
    "${MYSQL_CLI}" -h"${DB_HOST}" -P"${DB_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASS}" \
        -e "${SQL}" 2>/dev/null || warn "数据库创建失败，请手动执行：${SQL}"
else
    warn "未找到 mysql 客户端，请手动在 MySQL 中执行：${SQL}"
fi

# ---------- 5. systemd 服务单元 ----------
info "写入 systemd 单元"
cat > /etc/systemd/system/chord-server.service <<EOF
[Unit]
Description=Chord API server (REST + WebSocket)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}/server
ExecStart=${INSTALL_DIR}/server/chord-server
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/chord-web.service <<EOF
[Unit]
Description=Chord Web static hosting (Flutter Web)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}/web
ExecStart=${INSTALL_DIR}/web/serveweb -dir ${INSTALL_DIR}/web/htdocs -port ${WEB_PORT}
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
info "启动/重启服务 chord-server / chord-web"
# restart 而非 enable --now：已运行的老进程必须重启才能用上新二进制
systemctl enable chord-server chord-web >/dev/null 2>&1
systemctl restart chord-server chord-web

# ---------- 6. 本机防火墙（如有启用才动） ----------
open_port() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "$1/tcp" >/dev/null 2>&1 && info "ufw 已放行 $1/tcp"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="$1/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1 && info "firewalld 已放行 $1/tcp"
    fi
}
open_port "${API_PORT}"
open_port "${WEB_PORT}"
warn "若是云服务器（腾讯云等），请到控制台安全组放行 ${API_PORT} 和 ${WEB_PORT} 端口（TCP）"

# ---------- 7. 健康检查 ----------
info "等待服务就绪..."
for i in $(seq 1 15); do
    if curl -sf "http://127.0.0.1:${API_PORT}/api/health" >/dev/null 2>&1; then API_OK=1; break; fi
    sleep 1
done
if [ "${API_OK:-0}" = "1" ]; then
    info "API 健康：http://${SERVER_IP}:${API_PORT}/api/health"
else
    warn "API 未就绪，查看日志：journalctl -u chord-server -n 50 --no-pager"
fi
if curl -sf "http://127.0.0.1:${WEB_PORT}/" >/dev/null 2>&1; then
    info "Web 就绪：http://${SERVER_IP}:${WEB_PORT}"
else
    warn "Web 未就绪，查看日志：journalctl -u chord-web -n 50 --no-pager"
fi

# ---------- 8. 完成摘要 ----------
cat <<EOF

==================== 部署完成 ====================
Web  地址 : http://${SERVER_IP}:${WEB_PORT}
API  地址 : http://${SERVER_IP}:${API_PORT}
演示账号 : alice / bob / carol   密码均为 123456
          （演示服务器邀请码 demo2024，需 SEED_DEMO=true 且空库时写入）

常用命令 :
  systemctl status  chord-server chord-web
  systemctl restart chord-server
  journalctl -u chord-server -f        # API 日志
  journalctl -u chord-web    -f        # Web 日志
配置文件 : ${INSTALL_DIR}/server/.env
JWT 密钥 : ${INSTALL_DIR}/server/.data/jwt_secret（首次启动自动生成，请勿外泄）
==================================================
EOF
