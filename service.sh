#!/bin/bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -Eeuo pipefail
fi

APP_DIR="/opt/mihomo"
SCRIPT_PATH="${BASH_SOURCE[0]}"
ENV_FILE="$APP_DIR/.env"
SERVICE_NAME="mihomo.service"
SYSTEMD_UNIT="/etc/systemd/system/$SERVICE_NAME"
DEFAULT_CONFIG_DIR="$APP_DIR/config"
CONFIG_DIR="$DEFAULT_CONFIG_DIR"
PROXY_HOST="127.0.0.1"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

load_env() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE" || return
  fi
  CONFIG_DIR="${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
  HTTP_PORT="${HTTP_PORT:-7890}"
  SOCKS_PORT="${SOCKS_PORT:-7891}"
  PROXY_USERNAME="${PROXY_USERNAME:-}"
  PROXY_PASSWORD="${PROXY_PASSWORD:-}"
}

ensure_arch_binary() {
  local machine target current
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64) target="bin/linux-amd64/mihomo" ;;
        aarch64|arm64) target="bin/linux-arm64/mihomo" ;;
        *) echo "[mihomo-service] ERROR: 不支持的 CPU 架构: $machine（支持 x86_64/amd64/aarch64/arm64）" >&2; return 1 ;;
  esac
  [ -x "$APP_DIR/$target" ] || { echo "[mihomo-service] ERROR: 找不到可执行文件: $APP_DIR/$target" >&2; return 1; }
  if [ -e "$APP_DIR/mihomo" ] && [ ! -L "$APP_DIR/mihomo" ]; then
    echo "[mihomo-service] ERROR: $APP_DIR/mihomo 已存在且不是软链接，为避免覆盖请先手动处理" >&2; return 1
  fi
  current=""; [ -L "$APP_DIR/mihomo" ] && current="$(readlink "$APP_DIR/mihomo")"
  if [ "$current" != "$target" ]; then ln -sfn "$target" "$APP_DIR/mihomo"; log "已根据架构 $machine 选择 Mihomo: $target"; fi
}

build_proxy_urls() {
  if [ -n "$PROXY_USERNAME" ] && [ -n "$PROXY_PASSWORD" ]; then
    HTTP_PROXY_URL="http://${PROXY_USERNAME}:${PROXY_PASSWORD}@${PROXY_HOST}:${HTTP_PORT}"
    SOCKS_PROXY_URL="socks5h://${PROXY_USERNAME}:${PROXY_PASSWORD}@${PROXY_HOST}:${SOCKS_PORT}"
  else
    HTTP_PROXY_URL="http://${PROXY_HOST}:${HTTP_PORT}"
    SOCKS_PROXY_URL="socks5h://${PROXY_HOST}:${SOCKS_PORT}"
  fi
}

ensure_systemd_unit() {
  if [ -f "$SYSTEMD_UNIT" ]; then
    return 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo "[mihomo-service] ERROR: 首次安装 mihomo.service 需要 root 权限" >&2
    echo "请使用 sudo $SCRIPT_PATH ${1:-status}" >&2
    return 1
  fi

  install -m 0644 /dev/stdin "$SYSTEMD_UNIT" <<'UNIT_EOF' || return
[Unit]
Description=Mihomo Proxy Service
Documentation=https://github.com/MetaCubeX/mihomo
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/mihomo
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStartPre=/opt/mihomo/generate-config.sh
ExecStart=/opt/mihomo/mihomo -d /opt/mihomo/config
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
TimeoutStartSec=30s
TimeoutStopSec=20s
KillMode=control-group
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT_EOF
  systemctl daemon-reload || return
  log "检测到 systemd 服务文件不存在，已自动安装: $SYSTEMD_UNIT"
}

prepare_service_command() {
  case "${1:-}" in
    install|start|restart|reload|update|enable)
      ensure_arch_binary || return
      ensure_systemd_unit "$1" || return
      ;;
  esac
}
log() {
  echo "[mihomo-service] $*"
}

show_help() {
  cat <<EOF
Mihomo 统一管理脚本（systemd + 终端代理）

服务管理:
  $0 install    按 CPU 架构创建 mihomo 软链接并安装 systemd 服务
  $0 start      生成配置、清理订阅缓存并启动
  $0 restart    生成配置、保留订阅缓存并重启
  $0 reload     重新加载配置（等同 restart）
  $0 update     清理订阅缓存、生成配置并重启
  $0 stop       停止服务
  $0 status     查看 systemd 服务状态
  $0 logs       查看最近日志
  $0 enable     开启开机自启（不立即启动）
  $0 disable    关闭开机自启（不停止当前服务）
  $0 uninstall  停止服务、关闭自启并删除系统单元，保留项目目录
  source $SCRIPT_PATH uninstall  卸载服务并清除当前终端代理（root 执行）

终端代理管理:
  source $0 on       开启当前终端代理
  source $0 off      关闭当前终端代理
  source $0 proxy    查看当前终端代理环境变量
  $0 test            测试 Mihomo 代理连通性

提示：on/off 必须使用 source，才能修改当前终端的环境变量。
      test 显式连接代理，不代表当前终端或 Git 已经启用代理。
EOF
}

generate_config() {
  [ -x "$APP_DIR/generate-config.sh" ] || {
    echo "[mihomo-service] ERROR: generate-config.sh 不存在或不可执行" >&2
    return 1
  }
  "$APP_DIR/generate-config.sh"
}

prepare_config() {
  load_env || return
  mkdir -p "$CONFIG_DIR" || return
  generate_config
}

proxy_on() {
  load_env || return
  build_proxy_urls
  export http_proxy="$HTTP_PROXY_URL"
  export https_proxy="$HTTP_PROXY_URL"
  export all_proxy="$SOCKS_PROXY_URL"
  export HTTP_PROXY="$HTTP_PROXY_URL"
  export HTTPS_PROXY="$HTTP_PROXY_URL"
  export ALL_PROXY="$SOCKS_PROXY_URL"
  echo -e "${GREEN}✅ 当前终端代理已开启${NC}"
  echo "HTTP 代理地址:  $PROXY_HOST:$HTTP_PORT"
  echo "SOCKS5 代理地址: $PROXY_HOST:$SOCKS_PORT"
}

proxy_off() {
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
  echo -e "${RED}❌ 当前终端代理已关闭${NC}"
}

proxy_status() {
  if [ -n "${http_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ]; then
    echo -e "${GREEN}✅ 当前终端代理已开启${NC}"
    echo "HTTP_PROXY : ${HTTP_PROXY:-未设置}"
    echo "HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"
    echo "ALL_PROXY  : ${ALL_PROXY:-未设置}"
  else
    echo -e "${RED}❌ 当前终端代理未开启${NC}"
    echo "如需开启，请执行：source $SCRIPT_PATH on"
  fi
}

proxy_test() {
  load_env || return
  build_proxy_urls
  echo "以下测试显式使用 Mihomo 代理，不检查当前终端或 Git 的代理设置。"
  echo -n "测试 HTTP 代理连通性... "
  if curl -sS --connect-timeout 5 -x "$HTTP_PROXY_URL" http://www.gstatic.com/generate_204 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 正常${NC}"
  else
    echo -e "${RED}❌ 失败${NC}"
  fi

  echo -n "测试外网访问能力... "
  if curl -sS --connect-timeout 5 -x "$HTTP_PROXY_URL" https://www.google.com >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 正常${NC}"
  else
    echo -e "${RED}❌ 失败${NC}"
  fi

  echo -n "获取当前出口 IP... "
  local ip
  ip="$(curl -sS --connect-timeout 5 -x "$HTTP_PROXY_URL" https://api.ip.sb/ip 2>/dev/null || true)"
  if [ -n "$ip" ]; then
    echo -e "${GREEN}${ip}${NC}"
  else
    echo -e "${YELLOW}获取失败${NC}"
  fi
}

uninstall_service() {
  local load_state
  if [ "$(id -u)" -ne 0 ]; then
    echo "[mihomo-service] ERROR: 卸载 systemd 服务需要 root 权限" >&2
    return 1
  fi
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
  load_state="$(systemctl show "$SERVICE_NAME" -p LoadState)" || return
  if [ -e "$SYSTEMD_UNIT" ] || [ -L "$SYSTEMD_UNIT" ] || [ "$load_state" != 'LoadState=not-found' ]; then
    systemctl stop "$SERVICE_NAME" || return
    systemctl disable "$SERVICE_NAME" || return
  fi
  rm -f -- "$SYSTEMD_UNIT" || return
  systemctl daemon-reload || return
  systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
  log "系统服务已卸载；项目目录、配置和订阅数据已保留。"
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    log "当前终端的代理环境变量已清除。"
  else
    echo "独立执行脚本不能清除父终端环境变量，请在当前终端执行："
    echo 'unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY'
  fi
  echo "如需删除程序本体和配置，请手动执行以下命令："
  echo 'rm -rf /opt/mihomo'
}

main() {
if [[ "${BASH_SOURCE[0]}" == "$0" ]] && { [ "${1:-}" = on ] || [ "${1:-}" = off ]; }; then
  echo "请执行：source $SCRIPT_PATH $1" >&2
  echo "直接执行脚本无法修改当前终端的代理环境变量。" >&2
  return 1
fi
prepare_service_command "${1:-}" || return

case "${1:-}" in
  install)
    log "Mihomo 架构选择和 systemd 服务安装完成"
    ;;
  start)
    prepare_config || return
    find "$CONFIG_DIR" -maxdepth 1 -type f -name 'sub_*.yaml' -delete
    log "已生成配置并清理订阅缓存，交由 systemd 启动"
    systemctl start "$SERVICE_NAME"
    ;;
  restart|reload)
    prepare_config || return
    log "已生成配置，保留订阅缓存，交由 systemd 重启"
    systemctl restart "$SERVICE_NAME"
    ;;
  update)
    prepare_config || return
    find "$CONFIG_DIR" -maxdepth 1 -type f -name 'sub_*.yaml' -delete
    log "已清理订阅缓存，交由 systemd 重启并重新拉取订阅"
    systemctl restart "$SERVICE_NAME"
    ;;
  stop)
    systemctl stop "$SERVICE_NAME"
    ;;
  status)
    systemctl status "$SERVICE_NAME" --no-pager -l
    ;;
  logs)
    journalctl -u "$SERVICE_NAME" -n 100 --no-pager -o short-iso
    ;;
  enable)
    systemctl enable "$SERVICE_NAME"
    ;;
  disable)
    systemctl disable "$SERVICE_NAME"
    ;;
  uninstall)
    uninstall_service
    ;;
  on)
    proxy_on
    ;;
  off)
    proxy_off
    ;;
  proxy|proxy-status)
    proxy_status
    ;;
  test|proxy-test)
    proxy_test
    ;;
  help|-h|--help|"")
    show_help
    ;;
  *)
    echo "❌ 输入命令错误: $1" >&2
    show_help >&2
    return 1
    ;;
esac
}

main "$@"
