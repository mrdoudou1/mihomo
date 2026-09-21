#!/bin/bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -Eeuo pipefail
fi

APP_DIR="/opt/mihomo"
SCRIPT_PATH="${BASH_SOURCE[0]}"
ENV_FILE="$APP_DIR/.env"
SERVICE_NAME="mihomo.service"
SYSTEMD_UNIT="/etc/systemd/system/$SERVICE_NAME"
COMMAND_ENTRY="/usr/local/bin/mihomo"
DEFAULT_CONFIG_DIR="$APP_DIR/config"
CONFIG_DIR="$DEFAULT_CONFIG_DIR"
PROXY_HOST="127.0.0.1"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
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
    if grep -Fqx "WorkingDirectory=$APP_DIR" "$SYSTEMD_UNIT" \
      && grep -Fqx "ExecStartPre=$APP_DIR/generate-config.sh" "$SYSTEMD_UNIT" \
      && grep -Fqx "ExecStart=$APP_DIR/mihomo -d $APP_DIR/config" "$SYSTEMD_UNIT"; then
      return 0
    fi
    if ! grep -Fq 'Description=Mihomo Proxy Service' "$SYSTEMD_UNIT"; then
      echo "[mihomo-service] ERROR: $SYSTEMD_UNIT 已存在且不是本项目管理的服务，为避免覆盖请先手动检查" >&2
      return 1
    fi
    log "检测到旧版 Mihomo 服务路径，正在迁移为 $APP_DIR"
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo "[mihomo-service] ERROR: 首次安装 mihomo.service 需要 root 权限" >&2
    echo "请使用 sudo $SCRIPT_PATH ${1:-status}" >&2
    return 1
  fi

  if [ -f "$SYSTEMD_UNIT" ]; then
    cp -p "$SYSTEMD_UNIT" "$SYSTEMD_UNIT.backup.$(date +%s)" || return
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
  log "systemd 服务文件已安装或更新: $SYSTEMD_UNIT"
}

migrate_legacy_config_path() {
  if [ -f "$ENV_FILE" ] && grep -Eq "^[[:space:]]*CONFIG_DIR=[\"']?/opt/mihomo1/config[\"']?[[:space:]]*$" "$ENV_FILE"; then
    cp -p "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)" || return
    sed -i 's#^[[:space:]]*CONFIG_DIR=.*$#CONFIG_DIR="/opt/mihomo/config"#' "$ENV_FILE" || return
    log '已将 .env 中旧的 CONFIG_DIR=/opt/mihomo1/config 迁移为 /opt/mihomo/config'
  fi
}

ensure_command_entry() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "[mihomo-service] ERROR: 安装 mihomo 全局命令需要 root 权限" >&2
    return 1
  fi

  if [ -L "$COMMAND_ENTRY" ] || { [ -e "$COMMAND_ENTRY" ] && ! grep -Fqx '# Managed by /opt/mihomo/service.sh' "$COMMAND_ENTRY" 2>/dev/null; }; then
    echo "[mihomo-service] ERROR: $COMMAND_ENTRY 已存在且不是本项目生成的命令，为避免覆盖请先手动处理" >&2
    return 1
  fi

  install -m 0755 /dev/stdin "$COMMAND_ENTRY" <<EOF || return
#!/bin/bash
# Managed by /opt/mihomo/service.sh
APP_DIR="/opt/mihomo"
REPO_URL="https://github.com/mrdoudou1/mihomo.git"

bootstrap_install() {
  if [ "\$(id -u)" -ne 0 ]; then
    echo "[mihomo] ERROR: 安装需要 root 权限，请使用 sudo mihomo" >&2
    return 1
  fi
  if [ -e "\$APP_DIR" ] || [ -L "\$APP_DIR" ]; then
    echo "[mihomo] ERROR: \$APP_DIR 已存在但程序不完整，为避免覆盖请先检查该目录" >&2
    return 1
  fi
  echo '[mihomo] 正在从 GitHub 安装 Mihomo...'
  local stage
  stage="\$(mktemp -d /opt/.mihomo-install.XXXXXX)" || return
  git clone --depth 1 "\$REPO_URL" "\$stage/project" || {
    rm -rf -- "\$stage"
    echo '[mihomo] ERROR: 克隆失败。若服务器无法直连 GitHub，请先在当前终端配置 http_proxy/https_proxy 后重试。' >&2
    return 1
  }
  if [ -e "\$APP_DIR" ] || [ -L "\$APP_DIR" ]; then
    rm -rf -- "\$stage"
    return 1
  fi
  mv -T "\$stage/project" "\$APP_DIR" || return
  rmdir "\$stage"
  install -m 0600 "\$APP_DIR/.env.example" "\$APP_DIR/.env" || return
  chmod +x "\$APP_DIR/service.sh" "\$APP_DIR/generate-config.sh" "\$APP_DIR/proxy.sh" \
    "\$APP_DIR/bin/linux-amd64/mihomo" "\$APP_DIR/bin/linux-arm64/mihomo" || return
  "\$APP_DIR/service.sh" install || return
  echo '请先编辑 /opt/mihomo/.env，填写订阅及认证信息，再启动服务。'
  exec "\$APP_DIR/service.sh" menu
}

if [ -f "\$APP_DIR/service.sh" ]; then
  exec bash "\$APP_DIR/service.sh" "\${@:-menu}"
fi

case "\${1:-}" in
  install) bootstrap_install ;;
  '' )
    echo 'Mihomo 尚未安装。'
    echo '  1) 安装 Mihomo'
    echo '  0) 退出'
    read -r -p '请输入数字 [0-1]: ' choice || exit 0
    case "\$choice" in
      1) bootstrap_install ;;
      0) exit 0 ;;
      *) echo '❌ 无效选项。' >&2; exit 1 ;;
    esac
    ;;
  *) echo "[mihomo] 程序尚未安装。执行 mihomo 后选择 1 安装。" >&2; exit 1 ;;
esac
EOF
  log "已安装全局菜单命令: mihomo"
}

prepare_service_command() {
  case "${1:-}" in
    install|start|restart|reload|update|enable)
      if [ "$1" = install ]; then
        [ "$(id -u)" -eq 0 ] || { echo '安装需要 root 权限。' >&2; return 1; }
        chmod +x "$APP_DIR/service.sh" "$APP_DIR/generate-config.sh" "$APP_DIR/proxy.sh" \
          "$APP_DIR/bin/linux-amd64/mihomo" "$APP_DIR/bin/linux-arm64/mihomo" || return
        if [ ! -f "$ENV_FILE" ]; then
          install -m 0600 "$APP_DIR/.env.example" "$ENV_FILE" || return
          log '已创建 .env，请填写订阅和认证信息后启动服务。'
        fi
      fi
      migrate_legacy_config_path || return
      ensure_arch_binary || return
      ensure_systemd_unit "$1" || return
      if [ "$1" = install ]; then
        ensure_command_entry || return
      fi
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
  $0 upgrade    通过 Mihomo 代理从 GitHub 更新项目代码
  $0 stop       停止服务
  $0 status     查看 systemd 服务状态
  $0 logs       查看最近日志
  $0 enable     开启开机自启（不立即启动）
  $0 disable    关闭开机自启（不停止当前服务）
  $0 uninstall  停止服务、关闭自启、删除系统单元和 /opt/mihomo
  mihomo        打开全局数字管理菜单

终端代理管理:
  source $0 on       开启当前终端代理
  source $0 off      关闭当前终端代理
  source $0 proxy    查看当前终端代理环境变量
  $0 test            测试 Mihomo 代理连通性

提示：on/off 必须使用 source，才能修改当前终端的环境变量。
      test 显式连接代理，不代表当前终端或 Git 已经启用代理。
EOF
}

show_runtime_summary() {
  local service_state boot_state proxy_state controller controller_host controller_port local_controller lan_ip
  load_env >/dev/null 2>&1 || true
  service_state="$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)"
  boot_state="$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true)"
  [ -n "$service_state" ] || service_state='未安装'
  [ -n "$boot_state" ] || boot_state='未启用'
  if [ -n "${http_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ]; then proxy_state='已开启'; else proxy_state='未开启'; fi
  controller='127.0.0.1:9090'
  if [ -f "$CONFIG_DIR/config.yaml" ]; then
    controller="$(sed -nE 's/^[[:space:]]*external-controller:[[:space:]]*([^[:space:]#]+).*/\1/p' "$CONFIG_DIR/config.yaml" | head -n 1 | tr -d '\"')"
    [ -n "$controller" ] || controller='127.0.0.1:9090'
  fi
  controller_host="${controller%:*}"
  controller_port="${controller##*:}"
  local_controller="$controller"
  case "$controller_host" in
    0.0.0.0|::|\[::\]) local_controller="127.0.0.1:$controller_port" ;;
  esac
  lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '\n%b%s%b\n' "$BOLD$CYAN" '当前状态' "$NC"
  case "$service_state" in
    active) printf '  服务状态: %b%s%b' "$GREEN$BOLD" '● 运行中' "$NC" ;;
    inactive|failed|deactivating) printf '  服务状态: %b%s%b' "$RED$BOLD" "● $service_state" "$NC" ;;
    *) printf '  服务状态: %b%s%b' "$YELLOW$BOLD" "● $service_state" "$NC" ;;
  esac
  case "$boot_state" in
    enabled|enabled-runtime) printf '    开机自启: %b%s%b' "$GREEN" '已开启' "$NC" ;;
    *) printf '    开机自启: %b%s%b' "$YELLOW" "$boot_state" "$NC" ;;
  esac
  if [ "$proxy_state" = '已开启' ]; then
    printf '    终端代理: %b%s%b\n' "$GREEN" "$proxy_state" "$NC"
  else
    printf '    终端代理: %b%s%b\n' "$RED" "$proxy_state" "$NC"
  fi
  printf '  %bHTTP/SOCKS:%b %s / %s\n' "$BLUE" "$NC" "${HTTP_PORT:-7890}" "${SOCKS_PORT:-7891}"
  printf '  %b控制面板:%b   http://%s/ui\n' "$MAGENTA" "$NC" "$local_controller"
  if [ -n "$lan_ip" ]; then
    printf '  %b局域网访问:%b http://%s:%s/ui\n' "$MAGENTA" "$NC" "$lan_ip" "$controller_port"
  fi
}

menu_command() {
  bash "$SCRIPT_PATH" "$@" || {
    echo -e "${RED}操作未成功，请检查错误信息或服务日志。${NC}"
  }
}

show_menu() {
  local choice confirm
  while true; do
    show_runtime_summary
    cat <<'EOF'

========== Mihomo 全局管理菜单 ==========
[服务管理]
  1) 安装或修复服务
  2) 启动服务
  3) 重启服务
  4) 停止服务
  5) 更新订阅和配置
  6) 查看服务状态
  7) 查看最近日志
[启动与代理]
  8) 开启开机自启
  9) 关闭开机自启
  10) 测试代理连通性
[项目维护]
  11) 升级服务程序（GitHub）
  12) 卸载 Mihomo 服务及程序
  0) 退出
=====================================
提示：终端代理请手动执行 source /opt/mihomo/service.sh on 或 off
EOF
    read -r -p '请输入数字 [0-12]: ' choice || { echo; return 0; }
    case "$choice" in
      1) menu_command install ;;
      2) menu_command start ;;
      3) menu_command restart ;;
      4) menu_command stop ;;
      5) menu_command update ;;
      6) menu_command status ;;
      7) menu_command logs ;;
      8) menu_command enable ;;
      9) menu_command disable ;;
      10) menu_command test ;;
      11) menu_command upgrade ;;
      12)
        echo -e "${RED}${BOLD}重要：卸载会删除 /opt/mihomo，包括 service.sh。${NC}"
        echo '如果当前终端之前执行过 source /opt/mihomo/service.sh on，请先：'
        echo -e "  ${YELLOW}1) 输入 0 退出本菜单${NC}"
        echo -e "  ${YELLOW}2) 在当前终端执行：source /opt/mihomo/service.sh off${NC}"
        echo -e "  ${YELLOW}3) 再执行 mihomo，并选择 12 卸载${NC}"
        if proxy_env_set; then
          echo -e "${RED}检测到当前终端代理仍开启；为避免卸载后无法通过原脚本关闭代理，已取消卸载。${NC}"
          continue
        fi
        read -r -p '已确认终端代理关闭；继续删除服务和 /opt/mihomo 全部文件？[y/N] ' confirm
        case "$confirm" in
          y|Y|yes|YES) "$SCRIPT_PATH" uninstall && return 0 ;;
          *) echo '已取消卸载。' ;;
        esac
        ;;
      0) return 0 ;;
      *) echo '❌ 无效选项，请输入 0-12。' ;;
    esac
  done
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

upgrade_project() {
  local before after
  load_env || return
  build_proxy_urls
  git -C "$APP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "[mihomo-service] ERROR: $APP_DIR 不是 Git 仓库，无法升级" >&2
    return 1
  }

  before="$(git -C "$APP_DIR" rev-parse --short HEAD)" || return
  if ! git -C "$APP_DIR" diff --quiet; then
    log '检测到本地未提交修改；仅当它们不与远端更新冲突时才会继续。'
  fi
  log '正在通过 Mihomo 代理从 GitHub 获取更新...'
  if ! http_proxy="$HTTP_PROXY_URL" https_proxy="$HTTP_PROXY_URL" \
       HTTP_PROXY="$HTTP_PROXY_URL" HTTPS_PROXY="$HTTP_PROXY_URL" \
       git -C "$APP_DIR" pull --ff-only origin main; then
    echo '[mihomo-service] ERROR: 更新失败；本地文件未被强制覆盖。' >&2
    return 1
  fi
  after="$(git -C "$APP_DIR" rev-parse --short HEAD)" || return
  if [ "$before" = "$after" ]; then
    log "项目已是最新版本: $after"
  else
    log "项目已升级: $before -> $after"
  fi
  chmod +x "$APP_DIR/service.sh" || return
  bash "$APP_DIR/service.sh" install
}

uninstall_service() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "[mihomo-service] ERROR: 卸载 systemd 服务需要 root 权限" >&2
    return 1
  fi
  echo '卸载前请在当前终端执行：source /opt/mihomo/service.sh off'
  if proxy_env_set; then
    echo '检测到代理环境变量，已取消卸载。关闭代理后重试。' >&2
    return 1
  fi
  [ "$APP_DIR" = /opt/mihomo ] && [ ! -L "$APP_DIR" ] \
    && [ "$(readlink -f "$APP_DIR")" = /opt/mihomo ] || return 1
  ensure_command_entry || return
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
  if [ "$(systemctl show "$SERVICE_NAME" -p LoadState)" != LoadState=not-found ]; then
    systemctl stop "$SERVICE_NAME" || return
    systemctl disable "$SERVICE_NAME" || return
  fi
  rm -f -- "$SYSTEMD_UNIT" || return
  systemctl daemon-reload || return
  systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
  case "$APP_DIR" in
    /opt/mihomo) rm -rf -- "$APP_DIR" || return ;;
    *) echo "[mihomo-service] ERROR: 拒绝删除非预期目录: $APP_DIR" >&2; return 1 ;;
  esac
  log "Mihomo 服务、开机自启、配置和 /opt/mihomo 已删除。"
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    log "当前终端的代理环境变量已清除。"
  else
    echo "独立执行脚本不能清除父终端环境变量，请在当前终端执行："
    echo 'unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY'
  fi
  echo '全局入口 /usr/local/bin/mihomo 已保留，可再次执行 mihomo 重新安装。'
  echo '如需彻底删除全局入口，请手动执行：rm -rf /usr/local/bin/mihomo'
}

proxy_env_set() {
  [ -n "${http_proxy:-}${https_proxy:-}${all_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}" ]
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
  upgrade)
    upgrade_project
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
  menu)
    show_menu
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
