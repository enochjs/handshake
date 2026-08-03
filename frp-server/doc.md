# frp-server 原理与实现机制

## 1. 目录定位

`frp-server/` 是 frp 方案里的公网控制端，部署在阿里云等公网可访问机器上。它运行 `frps`，负责接收内网源端 `frp-source/` 和开发者客户端 `frp-client/` 的控制连接，协助 XTCP 建立点对点通道，并在 XTCP 不可用时为 STCP 提供中转能力。

这个目录不承载 GitLab 应用层网关职责。它不会把 GitLab Web、GitLab SSH 或宿主机 SSH 配成公网 `tcp`、`http`、`https` proxy，也不会在公网侧暴露 `8929`、`2222`、`10022` 等 GitLab 业务入口。公网机器只需要开放 frp bind 端口，默认是 `7000`。

## 2. 访问链路中的位置

frp 推荐链路如下：

```text
developer browser/git/ssh
  -> developer local frpc visitor
  -> frp-server frps control plane
  -> XTCP direct path when NAT traversal succeeds
  -> STCP relay through frps when XTCP fails
  -> internal frp-source frpc
  -> internal GitLab host services
```

`frp-server` 始终是两端会合的协调点。XTCP 成功时，它主要处理注册、鉴权、心跳和 NAT 协调；业务数据尽量不经过公网服务器。STCP fallback 触发时，它会承担业务流量中转，所以这个角色仍然需要稳定网络和合理带宽，但不需要直接理解 GitLab 协议。

## 3. 核心文件

- `env.example`: 运行参数模板，包含 frp 版本、镜像、监听地址、认证 token、生成配置路径、日志配置和卸载清理开关。
- `frps.toml.template`: `frps` 配置模板，只包含 bind、token auth 和日志配置。
- `docker-compose.yml`: 用 `fatedier/frps` 镜像运行 `frps`，挂载渲染后的 TOML，并暴露 TCP/UDP bind 端口。
- `install.sh`: 读取 `.env`，校验 `FRP_AUTH_TOKEN`，渲染 `generated/frps.toml`，启动 Docker Compose。
- `status.sh`: 输出容器状态、最近日志和监听端口。
- `uninstall.sh`: 执行 `docker compose down --remove-orphans`，可选清理 `.env` 和生成配置。

## 4. 配置生成机制

安装器先进入自身目录，然后按如下顺序加载配置：

```text
if .env exists
  -> source .env
else if not DRY_RUN
  -> copy env.example to .env and stop
```

这样第一次真实运行不会使用空 token 启动服务，而是先生成 `.env` 提醒运维人员补齐密钥。`DRY_RUN=1` 时不会创建真实文件，会直接使用脚本默认值或命令行环境变量输出将要执行的动作。

核心变量：

```text
FRP_VERSION=0.68.0
FRP_IMAGE=fatedier/frps:v0.68.0
FRP_SERVER_BIND_ADDR=0.0.0.0
FRP_BIND_PORT=7000
FRP_AUTH_TOKEN=
FRP_CONFIG_PATH=./generated/frps.toml
FRP_LOG_LEVEL=info
FRP_LOG_MAX_DAYS=7
```

`FRP_AUTH_TOKEN` 必填。它是 `frps` 控制面认证 token，`frp-source` 和 `frp-client` 必须使用同一个 token 才能连接。真实 token 不应该提交到仓库，只应该写在部署机器本地的 `.env` 中。

配置渲染使用 `sed` 替换模板占位符：

```text
frps.toml.template
  -> generated/frps.toml
  -> chmod 600
  -> mounted as /etc/frp/frps.toml in container
```

生成后的配置大致形态：

```toml
bindAddr = "0.0.0.0"
bindPort = 7000

auth.method = "token"
auth.token = "<secret>"

log.level = "info"
log.maxDays = 7
```

## 5. Docker Compose 机制

`docker-compose.yml` 使用同一个 bind 端口暴露 TCP 和 UDP：

```text
${FRP_BIND_PORT}:${FRP_BIND_PORT}/tcp
${FRP_BIND_PORT}:${FRP_BIND_PORT}/udp
```

TCP 用于 frp 控制连接和 STCP 中转。UDP 对 XTCP NAT 穿透有意义，因此即使没有公网 GitLab 端口，也需要在安全组和主机防火墙里放通对应 UDP 端口。

容器命令固定为：

```text
frps -c /etc/frp/frps.toml
```

仓库里采用容器常驻，而不是把 `frps` 安装到宿主机 systemd。这使升级、卸载和配置回滚都集中在目录内的 Compose 项目中。

## 6. 安装流程

推荐操作：

```bash
cp env.example .env
vim .env
./install.sh
```

脚本实际执行顺序：

```text
load .env
  -> validate FRP_AUTH_TOKEN
  -> render generated/frps.toml
  -> chmod 600 generated/frps.toml
  -> docker compose up -d
  -> docker compose ps
  -> print bind and image summary
```

`DRY_RUN=1 FRP_AUTH_TOKEN=test-token ./install.sh` 可用于验证模板渲染和命令输出，不会启动容器。

## 7. 状态检查

`status.sh` 会执行三类检查：

```text
docker compose ps
docker compose logs --tail=80 frps
ss -lntup | grep :${FRP_BIND_PORT}
```

其中 `ss` 主要验证宿主机端口是否监听。若容器正常但外部仍无法连接，通常要继续检查云安全组、iptables/firewalld，以及 TCP/UDP 是否都放通。

## 8. 卸载与清理

默认卸载只停止并删除容器：

```bash
./uninstall.sh
```

如果需要把本地运行配置也删掉：

```bash
FRP_REMOVE_CONFIG=1 ./uninstall.sh
```

清理逻辑会删除 `FRP_CONFIG_PATH` 和 `.env`，并尝试删除空的生成目录。真实环境中要确认 `.env` 里 token 已有其他备份，否则删除后需要重新分发给 source 和 client。

## 9. 安全边界

这个角色的安全边界有三层：

1. 公网只开放 frp bind 端口，不开放 GitLab Web/SSH 业务端口。
2. `auth.token` 限制谁能连接 `frps` 控制面。
3. private proxy 的 `secretKey` 不在本目录配置，而由 source/client 共享，用于限制 visitor 能否接入具体服务。

`frp-server` 如果被错误配置成 public GitLab proxy，就会改变整个项目的暴露面。因此本目录文档和测试都强调：`frps.toml.template` 只应该包含 bind、auth、log，不应该出现 GitLab proxy。
