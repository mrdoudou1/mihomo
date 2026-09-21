#!/bin/bash
set -Eeuo pipefail

APP_DIR="/opt/mihomo"
REPO_URL="https://github.com/mrdoudou1/mihomo.git"

if [ "$(id -u)" -ne 0 ]; then
  echo '[mihomo-install] 请使用 root 或 sudo 执行安装。' >&2
  exit 1
fi

if [ -x "$APP_DIR/service.sh" ]; then
  echo '[mihomo-install] 检测到已有安装，正在修复全局入口和 systemd 服务...'
  chmod +x "$APP_DIR/service.sh" "$APP_DIR/generate-config.sh" "$APP_DIR/proxy.sh"
  "$APP_DIR/service.sh" install
  echo '[mihomo-install] 完成。请执行 mihomo 打开管理菜单。'
  exit 0
fi

if [ -e "$APP_DIR" ]; then
  echo "[mihomo-install] ERROR: $APP_DIR 已存在但不是完整安装，为避免覆盖已停止。" >&2
  exit 1
fi

git clone --depth 1 "$REPO_URL" "$APP_DIR"
cp "$APP_DIR/.env.example" "$APP_DIR/.env"
chmod +x "$APP_DIR/service.sh" "$APP_DIR/generate-config.sh" "$APP_DIR/proxy.sh" \
  "$APP_DIR/bin/linux-amd64/mihomo" "$APP_DIR/bin/linux-arm64/mihomo"
"$APP_DIR/service.sh" install
echo '[mihomo-install] 安装完成。请先编辑 /opt/mihomo/.env，再执行 mihomo 启动服务。'
