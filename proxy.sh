#!/bin/bash

# 局域网代理配置：按实际 Mihomo 服务修改以下值。
PROXY_HOST="127.0.0.1"
HTTP_PORT="7890"
SOCKS_PORT="7891"
PROXY_USERNAME=""
PROXY_PASSWORD=""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

build_proxy_urls() {
  if [ -n "$PROXY_USERNAME" ] && [ -n "$PROXY_PASSWORD" ]; then
    HTTP_PROXY_URL="http://${PROXY_USERNAME}:${PROXY_PASSWORD}@${PROXY_HOST}:${HTTP_PORT}"
    SOCKS_PROXY_URL="socks5h://${PROXY_USERNAME}:${PROXY_PASSWORD}@${PROXY_HOST}:${SOCKS_PORT}"
  else
    HTTP_PROXY_URL="http://${PROXY_HOST}:${HTTP_PORT}"
    SOCKS_PROXY_URL="socks5h://${PROXY_HOST}:${SOCKS_PORT}"
  fi
}

proxy_on() {
  build_proxy_urls
  export http_proxy="$HTTP_PROXY_URL"
  export https_proxy="$HTTP_PROXY_URL"
  export all_proxy="$SOCKS_PROXY_URL"
  export HTTP_PROXY="$HTTP_PROXY_URL"
  export HTTPS_PROXY="$HTTP_PROXY_URL"
  export ALL_PROXY="$SOCKS_PROXY_URL"
  echo -e "${GREEN}当前终端代理已开启${NC}"
  echo "HTTP 代理地址:  $PROXY_HOST:$HTTP_PORT"
  echo "SOCKS5 代理地址: $PROXY_HOST:$SOCKS_PORT"
}

proxy_off() {
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
  echo -e "${RED}当前终端代理已关闭${NC}"
}

proxy_status() {
  if [ -n "${http_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ]; then
    echo -e "${GREEN}当前终端代理已开启${NC}"
    echo "HTTP 代理地址:  $PROXY_HOST:$HTTP_PORT"
    echo "SOCKS5 代理地址: $PROXY_HOST:$SOCKS_PORT"
  else
    echo -e "${RED}当前终端代理未开启${NC}"
    echo "如需开启，请执行：source ${BASH_SOURCE[0]} on"
  fi
}

proxy_test() {
  build_proxy_urls
  echo -n "测试 HTTP 代理连通性... "
  if curl -sS --connect-timeout 5 -x "$HTTP_PROXY_URL" http://www.gstatic.com/generate_204 >/dev/null 2>&1; then
    echo -e "${GREEN}正常${NC}"
  else
    echo -e "${RED}失败${NC}"
  fi

  echo -n "测试外网访问能力... "
  if curl -sS --connect-timeout 5 -x "$HTTP_PROXY_URL" https://www.google.com >/dev/null 2>&1; then
    echo -e "${GREEN}正常${NC}"
  else
    echo -e "${RED}失败${NC}"
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

show_help() {
  cat <<EOF
局域网 Mihomo 终端代理脚本

先在脚本顶部配置 PROXY_HOST、HTTP_PORT、SOCKS_PORT、PROXY_USERNAME、PROXY_PASSWORD。

  source ${BASH_SOURCE[0]} on   开启当前终端代理
  source ${BASH_SOURCE[0]} off  关闭当前终端代理
  ${BASH_SOURCE[0]} proxy       查看当前终端代理状态
  ${BASH_SOURCE[0]} test        测试代理连通性和出口 IP
EOF
}

main() {
  case "${1:-}" in
    on|off)
      if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        echo "请执行：source $0 $1" >&2
        echo "直接执行脚本无法修改当前终端的代理环境变量。" >&2
        return 1
      fi
      "proxy_$1"
      ;;
    proxy|status)
      proxy_status
      ;;
    test)
      proxy_test
      ;;
    help|-h|--help|"")
      show_help
      ;;
    *)
      echo "未知命令: $1" >&2
      show_help >&2
      return 1
      ;;
  esac
}

main "$@"
