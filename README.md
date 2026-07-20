# Mihomo Template

适用于 Linux `x86_64`（amd64）和 `arm64` 的 Mihomo v1.19.29 模板，包含 systemd 管理脚本与 MetaCubeXD Web UI。

## 安装

```bash
sudo mkdir -p /opt/mihomo
sudo cp -a . /opt/mihomo/
cd /opt/mihomo
cp .env.example .env
# 仅在本机编辑 .env，填写订阅地址和密钥；不要提交 .env
chmod +x generate-config.sh service.sh bin/linux-amd64/mihomo bin/linux-arm64/mihomo
sudo ./service.sh install
sudo ./service.sh start
```

`service.sh install` 会安全地根据 `uname -m` 创建 `/opt/mihomo/mihomo` 软链接并安装 systemd 服务：`x86_64` 使用 `bin/x86_64/mihomo`，`amd64` 使用 `bin/amd64/mihomo`，`aarch64` 使用 `bin/aarch64/mihomo`，`arm64` 使用 `bin/arm64/mihomo`；未知架构会直接报错。若 `/opt/mihomo/mihomo` 已是普通文件，脚本不会覆盖它。首次启动会由脚本生成 `config/config.yaml` 并拉取订阅。

## 二进制目录

```text
bin/
├── linux-amd64/mihomo   # x86_64 / amd64
└── linux-arm64/mihomo   # aarch64 / arm64
```

仓库只保留两份实际不同的 Mihomo v1.19.29 ELF。启动脚本会自动把 `x86_64` / `amd64` 映射到 amd64 程序，把 `aarch64` / `arm64` 映射到 arm64 程序，避免重复占用空间。

## 配置与安全

- `.env.example` 只列变量名；复制为 `.env` 后在本地填写真实值。
- `config/config.example.yaml` 是不含秘密和订阅地址的安全示例。
- `config/config.yaml`、`config/sub_*.yaml`、数据库、metadb、备份文件均被 `.gitignore` 排除。
- 不要把订阅 URL、Web secret、代理密码或节点配置提交到 Git。

## 管理

```bash
./service.sh start    # 生成配置、清理订阅缓存并启动
./service.sh restart  # 生成配置并重启，保留缓存
./service.sh update   # 清理缓存并重启
./service.sh status
./service.sh logs
source ./service.sh on|off|proxy
```

上游项目：[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)，版本：`v1.19.29`。
