#!/bin/bash
set -Eeuo pipefail

APP_DIR="/opt/mihomo1"
ENV_FILE="$APP_DIR/.env"

[ -f "$ENV_FILE" ] || {
  echo "错误: $ENV_FILE 不存在" >&2
  exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

CONFIG_DIR="${CONFIG_DIR:-$APP_DIR/config}"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
TMP_FILE="$CONFIG_FILE.tmp"

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
SUBSCRIBE_INTERVAL="${SUBSCRIBE_INTERVAL:-3600}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://www.gstatic.com/generate_204}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-300}"
EXTERNAL_CONTROLLER="${EXTERNAL_CONTROLLER:-0.0.0.0:${UI_PORT}}"

if [ "$BIND_ADDRESS" = "*" ]; then
  BIND_ADDRESS="0.0.0.0"
fi

mkdir -p "$CONFIG_DIR"

providers=()
if [ -n "$SUBSCRIBE_URLS" ]; then
  mapfile -t raw_urls < <(printf '%s\n' "$SUBSCRIBE_URLS" | tr ',' '\n')
  for raw_url in "${raw_urls[@]}"; do
    url="$(echo "$raw_url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$url" ] || continue
    name="sub_$(printf '%s' "$url" | md5sum | cut -c1-8)"
    providers+=("$name|$url")
  done
fi

{
  echo "port: ${HTTP_PORT}"
  echo "socks-port: ${SOCKS_PORT}"
  echo "allow-lan: ${ALLOW_LAN}"
  echo "bind-address: \"${BIND_ADDRESS}\""
  echo "external-controller: ${EXTERNAL_CONTROLLER}"
  echo "external-ui: ./ui"
  echo "log-level: ${LOG_LEVEL}"
  echo "ipv6: ${IPV6}"
  echo "mode: ${MODE}"
  if [ -n "$PROXY_USERNAME" ] && [ -n "$PROXY_PASSWORD" ]; then
    echo "authentication:"
    echo "  - \"${PROXY_USERNAME}:${PROXY_PASSWORD}\""
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
  echo
  echo "  - name: ♻️ 自动选择"
  echo "    type: url-test"
  echo "    url: '${HEALTH_CHECK_URL}'"
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
    echo "proxy-providers:"
    for item in "${providers[@]}"; do
      name="${item%%|*}"
      url="${item#*|}"
      cat <<EOF
  ${name}:
    type: http
    url: "${url}"
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

mv "$TMP_FILE" "$CONFIG_FILE"

echo "配置文件已生成: $CONFIG_FILE"
echo "HTTP 端口: ${HTTP_PORT}"
echo "SOCKS 端口: ${SOCKS_PORT}"
echo "Web 端口: ${UI_PORT}"
echo "运行模式: ${MODE}"
echo "订阅数量: ${#providers[@]}"
