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

systemd 单元模板内嵌在 `service.sh` 中，项目不再需要单独的 `mihomo.service` 文件。`./service.sh install` 会在系统单元不存在时自动生成 `/etc/systemd/system/mihomo.service` 并执行 `systemctl daemon-reload`；已存在的系统单元会保留，不会被覆盖。默认安装目录仍为 `/opt/mihomo`。

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
./service.sh enable   # 开启开机自启，不立即启动
./service.sh disable  # 关闭开机自启，不停止当前服务
source ./service.sh on     # 开启当前终端代理
source ./service.sh off    # 清除当前终端代理
./service.sh proxy         # 查看代理环境变量
./service.sh test          # 显式通过代理测试连通性
```

`on` 和 `off` 必须使用 `source`。直接执行 `./service.sh on` 只会影响子进程，无法让当前终端的 Git 使用代理，因此脚本会拒绝该用法并给出正确命令。`test` 显式指定代理，测试通过不代表当前终端已经设置了代理环境变量。

## 卸载

以 root 用户执行：

```bash
cd /opt/mihomo
source ./service.sh uninstall
```

卸载命令会清除当前终端的六个代理变量（`http_proxy`、`https_proxy`、`all_proxy` 及其大写形式），停止 `mihomo.service`、关闭开机自启、删除 `/etc/systemd/system/mihomo.service` 并重载 systemd。项目目录、配置和订阅数据会保留。脚本最后只打印 `rm -rf /opt/mihomo`，由你手动执行以删除本体。

也可以执行 `sudo ./service.sh uninstall`，但独立进程无法修改父终端环境，随后需要在当前终端执行脚本输出的 `unset` 命令。`stop`、`status`、`logs`、`disable` 和 `uninstall` 不会重新安装服务或创建二进制软链接。

上游项目：[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)，版本：`v1.19.29`。
