#!/usr/bin/env bash
# =====================================================================
# Chord 服务器自动更新脚本：从 GitHub Release 拉取最新部署包并应用
#
# 用法（在服务器上以 root 执行）：
#   sudo bash update.sh web    # 只更新 Web 前端（最常用，不需要数据库密码）
#   sudo MYSQL_PASS='数据库root密码' bash update.sh full   # 全量重装（后端+前端+.env+服务）
#
# 依赖：curl、tar、systemd（安装时的前提不变）
# =====================================================================
set -euo pipefail

REPO="${REPO:-zhumin2/discord-like}"
INSTALL_DIR="${INSTALL_DIR:-/opt/chord}"
RUN_USER="${RUN_USER:-chord}"
MODE="${1:-web}"

C_GREEN='\033[0;32m'; C_RED='\033[0;31m'; C_OFF='\033[0m'
info() { echo -e "${C_GREEN}[更新]${C_OFF} $*"; }
fail() { echo -e "${C_RED}[失败]${C_OFF} $*"; exit 1; }

[ "$(id -u)" = "0" ] || fail "请用 root/sudo 执行"
command -v curl >/dev/null || fail "缺少 curl，请先安装"
BASE_URL="https://github.com/${REPO}/releases/latest/download"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$MODE" = "web" ]; then
    info "拉取最新 Web 产物…"
    curl -fL --connect-timeout 15 -o "$TMP/web.tgz" "${BASE_URL}/chord-web-update.tar.gz"
    tar xzf "$TMP/web.tgz" -C "$TMP"
    systemctl stop chord-web 2>/dev/null || true

    # 若包内附带静态服务器二进制（serveweb），一并升级——缓存策略/压缩等改动都随它生效
    if [ -f "$TMP/web/serveweb" ]; then
        info "更新静态服务器 serveweb…"
        install -m 755 -o root -g root "$TMP/web/serveweb" "${INSTALL_DIR}/web/serveweb.new"
        mv -f "${INSTALL_DIR}/web/serveweb.new" "${INSTALL_DIR}/web/serveweb"
        rm -f "$TMP/web/serveweb"   # 不要留在 htdocs 里（会被公开下载）
    fi

    rm -rf "${INSTALL_DIR}/web/htdocs"
    cp -r "$TMP/web" "${INSTALL_DIR}/web/htdocs"
    chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}/web"
    systemctl start chord-web
    info "Web 已更新并重启。若浏览器显示旧版，强制刷新（Ctrl+F5）即可（有 PWA 缓存）。"

elif [ "$MODE" = "full" ]; then
    : "${MYSQL_PASS:?full 模式需要数据库密码：sudo MYSQL_PASS='数据库root密码' bash update.sh full}"
    info "拉取最新全量部署包…"
    curl -fL --connect-timeout 15 -o "$TMP/deploy.tgz" "${BASE_URL}/chord-deploy.tar.gz"
    tar xzf "$TMP/deploy.tgz" -C "$TMP"
    cd "$TMP/package"
    MYSQL_PASS="$MYSQL_PASS" bash install.sh
    info "全量更新完成。"

else
    echo "用法: sudo bash update.sh [web|full]"
    echo "  web  = 只更新 Web 前端（最常用）"
    echo "  full = 全量重装（需要 MYSQL_PASS）"
    exit 1
fi
