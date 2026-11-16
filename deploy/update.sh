#!/usr/bin/env bash
# =====================================================================
# Chord 服务器自动更新脚本：从 GitHub Release 拉取最新部署包并应用
#
# 用法（在服务器上以 root 执行）：
#   sudo bash update.sh web    # 更新 Web 前端（含静态服务器二进制，不需要数据库密码）
#   sudo MYSQL_PASS='数据库root密码' bash update.sh full   # 全量重装（后端+前端+.env+服务）
#
# 环境变量（可选）：
#   REPO=owner/repo       默认 zhumin2/discord-like
#   INSTALL_DIR=/opt/chord
#   RUN_USER=chord
#   WEB_PORT=3000         健康检查端口（与 install.sh 的 WEB_PORT 保持一致）
#
# 依赖：curl、tar、systemd
# =====================================================================
set -euo pipefail

REPO="${REPO:-zhumin2/discord-like}"
INSTALL_DIR="${INSTALL_DIR:-/opt/chord}"
RUN_USER="${RUN_USER:-chord}"
WEB_PORT="${WEB_PORT:-3000}"
MODE="${1:-web}"

C_GREEN='\033[0;32m'; C_RED='\033[0;31m'; C_YELLOW='\033[0;33m'; C_OFF='\033[0m'
info() { echo -e "${C_GREEN}[更新]${C_OFF} $*"; }
warn() { echo -e "${C_YELLOW}[注意]${C_OFF} $*"; }
fail() { echo -e "${C_RED}[失败]${C_OFF} $*"; exit 1; }

[ "$(id -u)" = "0" ] || fail "请用 root/sudo 执行"
command -v curl >/dev/null || fail "缺少 curl，请先安装"
BASE_URL="https://github.com/${REPO}/releases/latest/download"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- Web 更新（带备份、健康检查与回滚）----------
web_rollback() {
    trap - ERR   # 回滚自身失败时不要递归
    warn "回滚到上一版本…"
    systemctl stop chord-web 2>/dev/null || true
    if [ -f "$TMP/backup/serveweb" ]; then
        install -m 0755 "$TMP/backup/serveweb" "${INSTALL_DIR}/web/serveweb" || true
    fi
    if [ -d "$TMP/backup/htdocs" ]; then
        rm -rf "${INSTALL_DIR}/web/htdocs" || true
        cp -a "$TMP/backup/htdocs" "${INSTALL_DIR}/web/htdocs" || true
    fi
    chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}/web" 2>/dev/null || true
    systemctl start chord-web 2>/dev/null || true
    fail "更新失败，已回滚。请检查：journalctl -u chord-web -n 50 --no-pager"
}

update_web() {
    info "拉取最新 Web 产物…"
    curl -fL --connect-timeout 15 -o "$TMP/web.tgz" "${BASE_URL}/chord-web-update.tar.gz" \
        || fail "下载失败（检查网络或 Release 是否存在）"
    tar xzf "$TMP/web.tgz" -C "$TMP"
    [ -d "$TMP/web" ] || fail "压缩包结构异常：缺少 web/ 目录"

    # 1) 备份当前版本，便于失败回滚
    mkdir -p "$TMP/backup"
    [ -f "${INSTALL_DIR}/web/serveweb" ] && cp -a "${INSTALL_DIR}/web/serveweb" "$TMP/backup/" || true
    [ -d "${INSTALL_DIR}/web/htdocs" ] && cp -a "${INSTALL_DIR}/web/htdocs" "$TMP/backup/htdocs" || true

    # 从这一刻起任何未捕获错误都自动回滚（避免"换了二进制但没起来"的宕机窗口）
    trap 'web_rollback' ERR

    # 2) 停服务，原子替换静态服务器二进制（若包内附带）
    systemctl stop chord-web 2>/dev/null || true
    if [ -f "$TMP/web/serveweb" ]; then
        info "更新静态服务器 serveweb…"
        install -m 0755 "$TMP/web/serveweb" "${INSTALL_DIR}/web/serveweb.new"
        mv -f "${INSTALL_DIR}/web/serveweb.new" "${INSTALL_DIR}/web/serveweb"
        rm -f "$TMP/web/serveweb"   # 别留在 htdocs 里，避免二进制被公开下载
    fi

    # 3) 替换前端产物
    rm -rf "${INSTALL_DIR}/web/htdocs"
    cp -r "$TMP/web" "${INSTALL_DIR}/web/htdocs"

    # 4) 归属修正失败不致命（文件本就是 0644/0755 可读可执行）
    chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}/web" 2>/dev/null \
        || warn "chown 失败（不影响运行，但请检查 ${INSTALL_DIR}/web 归属）"

    # 5) 启动并探活（Type=simple 下 start 成功不代表进程真的活着）
    systemctl start chord-web || web_rollback
    local ok=0
    for _ in $(seq 1 10); do
        if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:${WEB_PORT}/"; then ok=1; break; fi
        sleep 1
    done
    [ "$ok" = "1" ] || web_rollback

    trap - ERR
    info "Web 已更新并重启（健康检查通过 :${WEB_PORT}）。"
    info "若浏览器显示旧版，强制刷新（Ctrl+F5）即可（有 PWA/HTTP 缓存）。"
}

if [ "$MODE" = "web" ]; then
    update_web

elif [ "$MODE" = "full" ]; then
    : "${MYSQL_PASS:?full 模式需要数据库密码：sudo MYSQL_PASS='数据库root密码' bash update.sh full}"
    info "拉取最新全量部署包…"
    curl -fL --connect-timeout 15 -o "$TMP/deploy.tgz" "${BASE_URL}/chord-deploy.tar.gz" \
        || fail "下载失败（检查网络或 Release 是否存在）"
    tar xzf "$TMP/deploy.tgz" -C "$TMP"
    cd "$TMP/package"
    MYSQL_PASS="$MYSQL_PASS" bash install.sh
    info "全量更新完成。"

else
    echo "用法: sudo bash update.sh [web|full]"
    echo "  web  = 更新 Web 前端（含静态服务器）"
    echo "  full = 全量重装（需要 MYSQL_PASS）"
    exit 1
fi
