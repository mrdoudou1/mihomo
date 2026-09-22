#!/bin/bash
set -Eeuo pipefail
umask 077

APP_DIR="/opt/mihomo"
ENV_FILE="$APP_DIR/.env"

[ -f "$ENV_FILE" ] || {
  echo "错误: $ENV_FILE 不存在" >&2
  exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

CONFIG_DIR="${CONFIG_DIR:-$APP_DIR/config}"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
if [ -f "$CONFIG_FILE" ] && [ "${1:-}" != --force ]; then
  chmod 0600 "$CONFIG_FILE"
  echo "保留现有配置: $CONFIG_FILE（菜单 5 可重新生成）"
  exit 0
fi

HTTP_PORT="${HTTP_PORT:-7890}"
SOCKS_PORT="${SOCKS_PORT:-7891}"
UI_PORT="${UI_PORT:-9090}"
ALLOW_LAN="${ALLOW_LAN:-false}"
BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0}"
IPV6="${IPV6:-false}"
MODE="${MODE:-rule}"
LOG_LEVEL="${LOG_LEVEL:-info}"
WEB_SECRET="${WEB_SECRET:-}"
PROXY_USERNAME="${PROXY_USERNAME:-}"
PROXY_PASSWORD="${PROXY_PASSWORD:-}"
SUBSCRIBE_URLS="${SUBSCRIBE_URLS:-}"
SUBSCRIBE_NAMES="${SUBSCRIBE_NAMES:-}"
SUBSCRIBE_INTERVAL="${SUBSCRIBE_INTERVAL:-3600}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://www.gstatic.com/generate_204}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-300}"
EXTERNAL_CONTROLLER="${EXTERNAL_CONTROLLER:-0.0.0.0:${UI_PORT}}"

if [ "$BIND_ADDRESS" = "*" ]; then
  BIND_ADDRESS="0.0.0.0"
fi

mkdir -p "$CONFIG_DIR"
TMP_FILE="$(mktemp "$CONFIG_DIR/.config.XXXXXX")"
trap 'rm -f -- "$TMP_FILE"' EXIT
yaml_quote() {
  local value="$1"
  value="$(printf '%s' "$value" | sed "s/'/''/g")"
  printf "'%s'" "$value"
}
if [ -z "$WEB_SECRET" ] || [ "$WEB_SECRET" = CHANGE_ME_WEB_SECRET ]; then
  echo '错误: 请在 .env 中设置自己的 WEB_SECRET 后生成配置。' >&2
  exit 1
fi

providers=()
subscription_groups=()
mapfile -t raw_names < <(printf '%s\n' "$SUBSCRIBE_NAMES" | tr ',' '\n')
subscription_index=0
if [ -n "$SUBSCRIBE_URLS" ]; then
  mapfile -t raw_urls < <(printf '%s\n' "$SUBSCRIBE_URLS" | tr ',' '\n')
  for raw_url in "${raw_urls[@]}"; do
    label="${raw_names[$subscription_index]:-}"
    subscription_index=$((subscription_index + 1))
    url="$(echo "$raw_url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$url" ] || continue
    name="sub_$(printf '%s' "$url" | md5sum | cut -c1-8)"
    # Repeated URLs share one provider and one subscription group.
    duplicate=false
    for item in ${providers[@]+"${providers[@]}"}; do
      [ "${item%%|*}" != "$name" ] || duplicate=true
    done
    [ "$duplicate" = false ] || continue
    providers+=("$name|$url")
    label="$(printf '%s' "$label" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    group="📦 订阅 ${subscription_index}"
    [ -z "$label" ] || group="$group · $label"
    subscription_groups+=("$group")
  done
fi

{
  echo "port: ${HTTP_PORT}"
  echo "socks-port: ${SOCKS_PORT}"
  echo "allow-lan: ${ALLOW_LAN}"
  echo "bind-address: \"${BIND_ADDRESS}\""
  echo "external-controller: ${EXTERNAL_CONTROLLER}"
  printf 'secret: %s\n' "$(yaml_quote "$WEB_SECRET")"
  echo "external-ui: ./ui"
  echo "log-level: ${LOG_LEVEL}"
  echo "ipv6: ${IPV6}"
  echo "mode: ${MODE}"
  if [ -n "$PROXY_USERNAME" ] && [ -n "$PROXY_PASSWORD" ]; then
    echo "authentication:"
    printf '  - %s\n' "$(yaml_quote "${PROXY_USERNAME}:${PROXY_PASSWORD}")"
  fi
  echo
  echo "proxies: []"
  echo
  echo "proxy-groups:"
  echo "  - name: 🎯 选择节点"
  echo "    type: select"
  if [ ${#providers[@]} -gt 0 ]; then
    echo "    use:"
    for item in "${providers[@]}"; do
      name="${item%%|*}"
      echo "      - ${name}"
    done
  fi
  echo "    proxies:"
  echo "      - DIRECT"
  echo "      - ♻️ 自动选择"
  echo "      - 🚀 手动选择"
  for group in ${subscription_groups[@]+"${subscription_groups[@]}"}; do
    printf '      - %s\n' "$(yaml_quote "$group")"
  done
  echo
  echo "  - name: ♻️ 自动选择"
  echo "    type: url-test"
    printf '    url: %s\n' "$(yaml_quote "$HEALTH_CHECK_URL")"
  echo "    interval: ${HEALTH_CHECK_INTERVAL}"
  if [ ${#providers[@]} -gt 0 ]; then
    echo "    use:"
    for item in "${providers[@]}"; do
      name="${item%%|*}"
      echo "      - ${name}"
    done
  else
    echo "    proxies:"
    echo "      - DIRECT"
  fi
  echo
  echo "  - name: 🚀 手动选择"
  echo "    type: select"
  if [ ${#providers[@]} -gt 0 ]; then
    echo "    use:"
    for item in "${providers[@]}"; do
      name="${item%%|*}"
      echo "      - ${name}"
    done
  fi
  echo "    proxies:"
  echo "      - DIRECT"
  echo
  if [ ${#providers[@]} -gt 0 ]; then
    for index in "${!providers[@]}"; do
      item="${providers[$index]}"
      printf '  - name: %s\n' "$(yaml_quote "${subscription_groups[$index]}")"
      echo "    type: select"
      echo "    use:"
      echo "      - ${item%%|*}"
      echo
    done
    echo "proxy-providers:"
    for item in "${providers[@]}"; do
      name="${item%%|*}"
      url="${item#*|}"
      cat <<EOF
  ${name}:
    type: http
    url: $(yaml_quote "$url")
    interval: ${SUBSCRIBE_INTERVAL}
    path: ./${name}.yaml
    health-check:
      enable: true
      url: ${HEALTH_CHECK_URL}
      interval: ${HEALTH_CHECK_INTERVAL}
EOF
    done
  fi
} > "$TMP_FILE"

if [ -x "$APP_DIR/mihomo" ]; then
  "$APP_DIR/mihomo" -t -d "$CONFIG_DIR" -f "$TMP_FILE" >/dev/null 2>&1 || {
    echo '配置校验失败，原配置已保留。请检查 .env。' >&2
    exit 1
  }
fi
if [ -f "$CONFIG_FILE" ]; then
  backup_file="$CONFIG_FILE.backup.$(date +%s)"
  cp -p "$CONFIG_FILE" "$backup_file"
  chmod 0600 "$backup_file"
fi
chmod 0600 "$TMP_FILE"
mv "$TMP_FILE" "$CONFIG_FILE"

echo "配置文件已生成: $CONFIG_FILE"
echo "HTTP 端口: ${HTTP_PORT}"
echo "SOCKS 端口: ${SOCKS_PORT}"
echo "Web 端口: ${UI_PORT}"
echo "运行模式: ${MODE}"
echo "订阅数量: ${#providers[@]}"
