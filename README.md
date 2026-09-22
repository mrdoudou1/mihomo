# Mihomo Template

适用于 Linux `x86_64`（amd64）和 `arm64` 的 Mihomo v1.19.29 模板，包含 systemd 管理脚本与 MetaCubeXD Web UI。

## 安装

在线一键安装（root 用户执行）：

```bash
curl -fSL https://raw.githubusercontent.com/mrdoudou1/mihomo/main/install.sh -o /tmp/mihomo-install.sh && sudo bash /tmp/mihomo-install.sh
```

若服务器需要代理才能访问 GitHub，先导出 `http_proxy`、`https_proxy`，再执行上述命令。

离线安装：将完整项目放到 `/opt/mihomo`，执行 `sudo bash /opt/mihomo/service.sh install`。脚本会修复执行权限，并在缺少 `.env` 时生成权限为 0600 的配置文件；填写订阅与认证信息后再启动服务。

在线安装需要 Git 和访问 GitHub 的网络；安装器不会自动启动未配置的服务。已有安装会保留 `.env` 并修复服务和入口。新安装的下载在临时目录完成，失败不会留下残缺的 `/opt/mihomo`。

手动安装也可使用以下方式，`service.sh` 会持续保留：

```bash
cd /opt
sudo git clone --depth 1 https://github.com/mrdoudou1/mihomo.git mihomo
cd /opt/mihomo
sudo cp .env.example .env
# 仅在本机编辑 .env，填写订阅地址和密钥；不要提交 .env
sudo chmod +x generate-config.sh service.sh proxy.sh bin/linux-amd64/mihomo bin/linux-arm64/mihomo
sudo ./service.sh install
sudo ./service.sh start
```

安装完成后，在任意目录输入以下命令即可打开数字交互式管理菜单：

```bash
mihomo
```

仓库为公开仓库，不需要 GitHub Token。`service.sh install` 会安全地根据 `uname -m` 创建 `/opt/mihomo/mihomo` 软链接并安装 systemd 服务：`x86_64` 和 `amd64` 使用 `bin/linux-amd64/mihomo`，`aarch64` 和 `arm64` 使用 `bin/linux-arm64/mihomo`；未知架构会直接报错。若 `/opt/mihomo/mihomo` 已是普通文件，脚本不会覆盖它。首次启动会由脚本生成 `config/config.yaml` 并拉取订阅。

服务器无法直连 GitHub、但已有 Mihomo 代理时，先在当前终端导出带认证的 `http_proxy`、`https_proxy`，再执行克隆；单独执行 `./service.sh on` 不会影响 Git。

systemd 单元模板内嵌在 `service.sh` 中，项目不再需要单独的 `mihomo.service` 文件。`./service.sh install` 会生成 `/etc/systemd/system/mihomo.service` 并执行 `systemctl daemon-reload`。路径正确的已有单元会保留；本项目旧版单元的路径错误会在备份后修复，`.env` 中旧的 `/opt/mihomo1/config` 同样会备份后迁移。默认安装目录为 `/opt/mihomo`。

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
./service.sh start    # 保留配置与缓存并启动，首次自动生成配置
./service.sh restart  # 保留配置与缓存并重启
./service.sh update   # 清理缓存并重启
./service.sh upgrade  # 通过 Mihomo 代理直接下载并在线更新
./service.sh status
./service.sh logs
./service.sh enable   # 开启开机自启，不立即启动
./service.sh disable  # 关闭开机自启，不停止当前服务
source ./service.sh on     # 开启当前终端代理
source ./service.sh off    # 清除当前终端代理
./service.sh proxy         # 查看代理环境变量
./service.sh test          # 显式通过代理测试连通性
mihomo                     # 打开数字交互式管理菜单
```

`mihomo` 菜单按“服务管理 / 启动与代理 / 项目维护”分组。每次操作显示结果，按 Enter 返回菜单。停止状态的查询不视为操作失败；代理测试任何一项失败都会报告失败，单次请求最长 20 秒。

启动、重启和升级保留已有 `config/config.yaml`。修改 `.env` 后，通过菜单 5“更新订阅和配置”应用：先备份旧配置，生成并校验新配置，成功后替换、清理订阅缓存并重启。配置生成失败则保留旧配置。`.env` 和生成配置权限为 0600。首次生成前必须设置自己的 `WEB_SECRET`，它会作为控制 API 的认证密钥写入配置。已有手工配置的 `secret` 由用户维护。

菜单 11“升级程序”直接下载 GitHub 压缩包，无需 Git。依次尝试环境代理、本机运行中的 Mihomo 代理和直连，显示下载进度。升级和卸载使用互斥锁。升级只替换已知程序文件，保留 `.env`、`proxy.sh`、`config/`、`.git/` 及额外的本地文件。程序、配置与系统入口备份保留在 `/var/tmp/mihomo-upgrade.*/backup`，路径显示在结果中，成功后可按需清理。

升级前校验脚本和配置，原服务运行时会重启并检查进程稳定及 HTTP/SOCKS 端口；原服务停止时保持停止。失败或收到常规中断信号时尝试回滚，只有回滚成功才提示恢复；回滚失败会保留备份和明确报错。断电或强制杀进程无法触发自动回滚，需要利用保留的备份恢复。

菜单无法修改父终端环境变量，终端代理仍需手动使用 `source ./service.sh on/off`。

`on` 和 `off` 必须使用 `source`。直接执行 `./service.sh on` 只会影响子进程，无法让当前终端的 Git 使用代理，因此脚本会拒绝该用法并给出正确命令。`test` 显式指定代理，测试通过不代表当前终端已经设置了代理环境变量。

## 局域网终端代理

`proxy.sh` 是独立脚本，适合局域网内的其他机器使用。编辑文件顶部的 `PROXY_HOST`、`HTTP_PORT`、`SOCKS_PORT`、`PROXY_USERNAME` 和 `PROXY_PASSWORD` 后执行：

```bash
source ./proxy.sh on
source ./proxy.sh off
./proxy.sh proxy
./proxy.sh test
```

`on` 和 `off` 同样必须使用 `source`，代理账号和密码不会显示在命令输出中。

## 按订阅选择节点

每个订阅会生成独立分组，例如 `📦 订阅 1`、`📦 订阅 2`，组内只展示该订阅的节点。在 `🎯 选择节点` 中选择订阅组，再进入该组选择节点；全局模式也可在 `GLOBAL` 中选择订阅组。原有自动选择、手动选择等聚合分组保留。

可在 `.env` 中设置名称，按订阅地址的顺序一一对应：

```bash
SUBSCRIBE_NAMES="机场 A,机场 B"
```

名称和地址都支持逗号或换行分隔，名称本身不要包含逗号。未填写名称时使用编号；重复地址只生成一个分组。修改后在 `mihomo` 菜单选择 `5`（更新订阅和配置），刷新面板即可。在线升级保留现有配置，因此升级后也需要执行一次菜单 `5` 才会显示新分组。

## 卸载

在 `mihomo` 菜单中选择 `12`，或以 root 用户直接执行：

```bash
cd /opt/mihomo
./service.sh uninstall
```

卸载会停止 `mihomo.service`、关闭开机自启、删除 `/etc/systemd/system/mihomo.service`、重载 systemd，并删除 `/opt/mihomo` 中的程序、配置和订阅数据。`/usr/local/bin/mihomo` 全局入口会保留，因此之后仍可执行 `mihomo` 并选择安装；如需彻底删除入口，手动执行：

```bash
rm -rf /usr/local/bin/mihomo
```

菜单属于子进程，无法清除它的父终端环境变量。**卸载前必须先退出菜单，并在当前终端执行**：

```bash
source /opt/mihomo/service.sh off
```

请在卸载前执行此命令，因为 `/opt/mihomo` 会随卸载删除，之后无法再通过原脚本关闭该终端的代理环境变量。菜单检测到当前终端代理仍开启时会拒绝继续卸载。

上游项目：[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)，版本：`v1.19.29`。
