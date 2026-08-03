# FRP GitLab 内网访问架构设计与原理

## 1. 文档定位

本文是 Handshake 项目中 frp 方案的专项架构文档。它只解释 `frp-server/`、`frp-source/`、`frp-client/` 三个角色如何配合，把内网 GitLab Web、GitLab SSH 和内网机器 SSH 提供给开发者本机使用，同时避免把 GitLab 真实服务端口直接暴露到公网。

frp 方案的核心目标是降低低配阿里云服务器的业务流量压力。正常情况下，业务流量优先通过 XTCP 建立点对点路径；当 NAT 穿透失败时，客户端自动降级到 STCP，让阿里云 `frps` 临时承担中转，保证可用性。

端到端访问链路如下：

```text
developer browser/git/ssh
  -> gitlab.internal:8929 / gitlab.internal:2222 / gitlab.internal:10022
  -> developer frpc visitor on 127.0.0.1
  -> XTCP direct path to internal GitLab host when NAT traversal succeeds
  -> STCP fallback through Aliyun frps when XTCP fails
  -> internal GitLab host 127.0.0.1:8929 / 127.0.0.1:2222 / 127.0.0.1:22
```

`gitlab.internal` 不是公网域名，也不依赖公司 DNS。开发者客户端安装时会写入本机 hosts：

```text
127.0.0.1 gitlab.internal
```

因此开发者看到的是稳定的本地入口，真实链路由本机 `frpc` visitor 决定。

## 2. 三角色架构

### 2.1 `frp-server/`: 阿里云 frps 控制端

`frp-server/` 运行在公网可访问的阿里云服务器上，使用 Docker Compose 托管 `frps` 容器。

它承担三类职责：

1. 接收内网源端 `frp-source/` 的 proxy 注册。
2. 接收开发者客户端 `frp-client/` 的 visitor 注册。
3. 协助 XTCP 建立 P2P 连接，并在 XTCP 失败时作为 STCP fallback 中转。

它不承担 GitLab 应用网关职责。配置中不应该出现 GitLab Web/SSH 的 public `tcp`、`http` 或 `https` proxy，也不应该把公网域名或公网端口直接指向 GitLab。

主要文件：

- `frp-server/env.example`: frps 镜像、监听地址、认证 token、配置路径和日志配置。
- `frp-server/frps.toml.template`: frps TOML 模板，只配置 bind、auth 和 log。
- `frp-server/docker-compose.yml`: 使用 `fatedier/frps` 镜像运行容器，默认 `restart: unless-stopped`。
- `frp-server/install.sh`: 渲染 `generated/frps.toml`，设置 `600` 权限，并执行 `docker compose up -d`。
- `frp-server/status.sh`: 查看容器状态、日志和监听端口。
- `frp-server/uninstall.sh`: 停止并删除 frps 容器；设置 `FRP_REMOVE_CONFIG=1` 时清理生成配置和 `.env`。

默认 frps 监听：

```text
FRP_SERVER_BIND_ADDR=0.0.0.0
FRP_BIND_PORT=7000
```

公网防火墙只需要放行 frp 控制和传输所需端口。GitLab Web `8929`、GitLab SSH `2222`、机器 SSH `22/10022` 都不应该在公网侧开放为 GitLab 入口。

### 2.2 `frp-source/`: 内网 GitLab frpc 源端

`frp-source/` 运行在内网 GitLab 宿主机上，使用 Docker Compose 托管 `frpc` 容器。它主动连接阿里云 `frps`，并把本机服务注册为 private proxy。

`frp-source/docker-compose.yml` 使用 `network_mode: host`。这样容器内的 `frpc` 可以直接访问宿主机 loopback 上的 GitLab 服务和机器 SSH：

```text
GitLab Web: 127.0.0.1:8929
GitLab SSH: 127.0.0.1:2222
Machine SSH: 127.0.0.1:22
```

源端默认注册六个 private proxy：

```text
gitlab-web-xtcp    -> 127.0.0.1:8929
gitlab-web-stcp    -> 127.0.0.1:8929
gitlab-ssh-xtcp    -> 127.0.0.1:2222
gitlab-ssh-stcp    -> 127.0.0.1:2222
machine-ssh-xtcp   -> 127.0.0.1:22
machine-ssh-stcp   -> 127.0.0.1:22
```

每个服务都同时配置 XTCP 和 STCP。XTCP 是首选路径，STCP 是兜底路径；两者都使用同一组 `FRP_SECRET_KEY` 做访问隔离。

主要文件：

- `frp-source/env.example`: frps 地址、认证 token、secret key、本地 GitLab 和机器 SSH 端口。
- `frp-source/frpc.toml.template`: source 侧 XTCP/STCP proxy 定义。
- `frp-source/docker-compose.yml`: 使用 `fatedier/frpc` 镜像运行容器，并挂载渲染后的配置。
- `frp-source/install.sh`: 渲染 `generated/frpc-source.toml`，设置 `600` 权限，并启动容器。
- `frp-source/status.sh`: 查看源端容器状态和日志。
- `frp-source/uninstall.sh`: 停止并删除源端容器；设置 `FRP_REMOVE_CONFIG=1` 时清理生成配置和 `.env`。

### 2.3 `frp-client/`: 开发者 frpc visitor

`frp-client/` 运行在每个开发者机器上，负责提供稳定的本地入口。开发者访问本机 loopback，`frpc` visitor 再根据 frp 配置连接对应的源端 private proxy。

默认本地入口：

```text
Web:         http://gitlab.internal:8929
GitLab SSH: ssh://git@gitlab.internal:2222/<group>/<repo>.git
Machine SSH: ssh linkmore@gitlab.internal -p 10022
```

客户端 visitor 默认绑定：

```text
gitlab-web-xtcp-visitor  -> 127.0.0.1:8929  -> gitlab-web-xtcp
gitlab-ssh-xtcp-visitor  -> 127.0.0.1:2222  -> gitlab-ssh-xtcp
machine-ssh-xtcp-visitor -> 127.0.0.1:10022 -> machine-ssh-xtcp
```

每个 XTCP visitor 都配置对应的 STCP visitor 作为 fallback：

```text
gitlab-web-xtcp-visitor  fallbackTo gitlab-web-stcp-visitor
gitlab-ssh-xtcp-visitor  fallbackTo gitlab-ssh-stcp-visitor
machine-ssh-xtcp-visitor fallbackTo machine-ssh-stcp-visitor
```

默认 `FRP_FALLBACK_TIMEOUT_MS=300`，也就是 XTCP 建立连接超过 300ms 仍不可用时，visitor 会降级到 STCP。

客户端安装器会做四件事：

1. 下载并安装 `frpc` 到 `FRP_BINARY_PATH`，默认 `/usr/local/bin/frpc`。
2. 渲染 `FRP_CONFIG_PATH`，默认 `/etc/frp/frpc-client.toml`。
3. 写入 hosts：`127.0.0.1 gitlab.internal`。
4. 写入 Git 全局 rewrite，把旧直连 GitLab SSH 前缀改写到 frp 本地入口。

在 Linux 上，安装器默认创建并启动 `frp-client.service`；在 macOS 上，默认创建 LaunchAgent；其他环境会输出手动启动命令。

## 3. 核心访问原理

### 3.1 XTCP 首选路径

XTCP 的目标是让开发者客户端和内网 GitLab 宿主机尽量建立点对点连接。`frps` 在这个过程中主要承担控制面职责：

```text
frp-source frpc
  -> register gitlab-web-xtcp / gitlab-ssh-xtcp / machine-ssh-xtcp
  -> keep control connection to frps

frp-client frpc visitor
  -> register xtcp visitors
  -> ask frps to coordinate NAT traversal
  -> exchange traffic directly with source frpc if traversal succeeds
```

XTCP 成功时，Git clone/pull/push、网页请求、机器 SSH 数据流量不经过阿里云 `frps`。这能显著减少低配公网服务器的 CPU、内存和带宽压力。

### 3.2 STCP fallback 路径

XTCP 依赖两端 NAT 类型和网络策略，不能保证每个网络环境都成功。因此每个服务都配置 STCP fallback：

```text
developer local request
  -> local frpc xtcp visitor
  -> XTCP connect timeout
  -> fallbackTo stcp visitor
  -> Aliyun frps relay
  -> internal source frpc
  -> internal GitLab host loopback service
```

STCP fallback 会让业务流量经过阿里云 `frps`，成本更高，但可用性更稳。这个设计把“优先省带宽”和“失败仍可用”放在同一套配置里，不要求开发者手动切换。

### 3.3 private proxy 与 visitor

frp 方案不使用公网 `tcp` proxy，而使用 private proxy 加 visitor。源端定义 private proxy：

```toml
[[proxies]]
name = "gitlab-ssh-xtcp"
type = "xtcp"
secretKey = "${FRP_SECRET_KEY}"
localIP = "127.0.0.1"
localPort = 2222
```

客户端定义 visitor：

```toml
[[visitors]]
name = "gitlab-ssh-xtcp-visitor"
type = "xtcp"
serverName = "gitlab-ssh-xtcp"
secretKey = "${FRP_SECRET_KEY}"
bindAddr = "127.0.0.1"
bindPort = 2222
fallbackTo = "gitlab-ssh-stcp-visitor"
```

只有同时拥有 `FRP_AUTH_TOKEN` 和 `FRP_SECRET_KEY` 的客户端，才能注册 visitor 并访问对应 private proxy。公网用户即使能连到 `frps` 控制端口，也不能直接访问 GitLab 服务端口。

### 3.4 本地命名与 Git rewrite

开发者不直接记忆阿里云地址，也不直接使用内网 IP。客户端统一使用：

```text
gitlab.internal -> 127.0.0.1
```

Git SSH remote 通过全局 rewrite 透明迁移：

```bash
git config --global \
  url.ssh://git@gitlab.internal:2222/.insteadOf \
  ssh://git@10.10.0.216:2222/
```

效果是：旧仓库 remote 不需要逐个修改，Git 在访问时会自动把旧直连地址改写到本机 frp visitor。

## 4. 安装与迁移链路

推荐安装顺序：

```text
1. gitlab/       内网宿主机启动 GitLab Docker
2. frp-server/   阿里云启动 frps 控制端
3. frp-source/   内网 GitLab 宿主机注册 private proxy
4. frp-client/   开发者机器启动 visitor、写 hosts、写 Git rewrite
```

每个 frp 角色目录都采用同一套操作习惯：

```bash
cp env.example .env
vim .env
./install.sh
```

已有 Handshake 客户端的开发者机器，推荐从仓库根目录运行迁移脚本：

```bash
scripts/migrate-client-to-frp.sh
```

迁移脚本会先清理旧 Handshake 客户端状态：

1. 删除 Handshake 相关 Git rewrite。
2. 从 `~/.ssh/config` 删除 `Include ~/.ssh/handshake_config`。
3. 删除 `~/.ssh/handshake_config`。
4. 如本机安装了 Cargo，尝试卸载 `handshake-client`。
5. 进入 `frp-client/` 执行 `install.sh`。

## 5. 安全边界设计

### 5.1 最小公网暴露

公网服务器只运行 `frps` 控制端，不发布 GitLab Web 或 GitLab SSH 的公网 proxy。GitLab 真实服务仍绑定在内网宿主机或开发者本机 loopback 上：

```text
internal GitLab host 127.0.0.1:8929
internal GitLab host 127.0.0.1:2222
developer client    127.0.0.1:8929
developer client    127.0.0.1:2222
developer client    127.0.0.1:10022
```

### 5.2 双层共享密钥

frp 方案使用两类密钥：

- `FRP_AUTH_TOKEN`: 用于 frpc 连接 frps 的认证。
- `FRP_SECRET_KEY`: 用于 private proxy 和 visitor 的访问配对。

两者都不应提交到仓库，应该只写在各机器的 `.env` 中。`install.sh` 渲染出的配置文件默认设置为 `600` 权限，降低本机泄漏风险。

### 5.3 本地入口隔离

`frp-client` 默认绑定 `127.0.0.1`，而不是 `0.0.0.0`。这样开发者机器上的 GitLab Web、GitLab SSH 和机器 SSH 入口只对本机可见，不会顺手暴露到同一局域网。

### 5.4 GitLab SSH 与机器 SSH 分端口

GitLab Docker SSH 使用本地 `2222`，机器系统 SSH 使用本地 `10022`。两者分开可以避免误把系统账号登录流量打到 GitLab SSH，也方便运维时快速判断入口类型：

```text
ssh://git@gitlab.internal:2222/...    -> GitLab 仓库 SSH
ssh linkmore@gitlab.internal -p 10022 -> 内网宿主机 SSH
```

## 6. 运维与验证

常用状态检查：

```bash
frp-server/status.sh
frp-source/status.sh
frp-client/status.sh
```

`frp-client/status.sh` 会检查：

- `/etc/hosts` 中是否存在 `gitlab.internal`。
- GitLab Web health endpoint 是否可访问。
- GitLab SSH 握手是否可达。
- 机器 SSH 是否可达。
- Git 全局 rewrite 是否存在。

项目根级验证入口：

```bash
scripts/verify.sh
```

frp 相关安装器 dry-run 测试入口：

```bash
scripts/test_frp_installers.sh
```

删除 frp 组件：

```bash
cd frp-server && ./uninstall.sh
cd frp-source && ./uninstall.sh
```

开发者侧如果只想停止服务，应优先使用系统服务管理器；如果需要彻底清理配置，再按当前机器的 systemd、launchd 或手动安装方式删除对应服务、配置文件和 Git rewrite。

## 7. 故障定位

### 7.1 本机端口不可访问

先确认 `frp-client` 是否运行，再看本地端口是否监听：

```bash
frp-client/status.sh
```

如果 `gitlab.internal` 解析失败，检查 `/etc/hosts` 是否有：

```text
127.0.0.1 gitlab.internal
```

如果本地端口被占用，调整 `frp-client/.env` 中的 bind port，并同步调整 `FRP_GITLAB_SSH_PREFIX`。

### 7.2 XTCP 不稳定但 STCP 可用

这通常和 NAT 类型、公司网络、防火墙或运营商策略有关。只要 fallback 可用，业务可继续运行；代价是阿里云 `frps` 会承担更多中转流量。

可以关注三类现象：

- clone/pull/push 可用但速度明显受阿里云带宽限制。
- frpc 日志中出现 XTCP 建连超时后 fallback。
- 不同办公网络下表现不同。

### 7.3 源端服务不可达

源端 `frpc` 使用 `network_mode: host` 访问宿主机 loopback。若 visitor 能连接但 GitLab 返回异常，应在内网 GitLab 宿主机上确认：

```bash
curl -fsS http://127.0.0.1:8929/-/health
ssh -T -p 2222 git@127.0.0.1
ssh -p 22 linkmore@127.0.0.1 true
```

如果这些本地检查失败，问题在 GitLab 或宿主机 SSH，而不是 frp 隧道。

## 8. 设计取舍

### 8.1 为什么不用 public tcp proxy

public tcp proxy 最简单，但会把 GitLab SSH 或 Web 变成公网入口。frp 方案选择 private proxy + visitor，是为了把访问入口固定在开发者本机 loopback，并用 `FRP_SECRET_KEY` 做接入隔离。

### 8.2 为什么 XTCP 和 STCP 同时配置

只配置 XTCP 可以节省服务器带宽，但在复杂 NAT 环境下会不可用。只配置 STCP 最稳，但所有业务流量都会压到阿里云。双配置让常见场景走 P2P，失败时自动兜底。

### 8.3 为什么保留 `gitlab.internal`

固定本地域名让 Web、Git remote、脚本输出和团队说明保持一致。它不依赖外部 DNS，也不暴露真实内网 IP。后续如果 GitLab 宿主机或 frps 地址变化，开发者入口仍然可以保持不变。

### 8.4 为什么继续使用 Git rewrite

Git rewrite 让迁移发生在客户端全局配置里，不要求逐个仓库修改 remote URL。它也让回滚更简单：删除 frp rewrite 或切回旧 Handshake rewrite 即可改变访问路径。

## 9. 扩展方向

可演进但不必一开始引入的能力：

- 多 GitLab 实例：按实例增加 proxy/visitor 名称和本地域名。
- secret 轮换脚本：批量更新 `FRP_AUTH_TOKEN` 和 `FRP_SECRET_KEY`。
- fallback 可观测性：统计 XTCP 成功率、STCP fallback 次数和 frps 中转流量。
- 客户端卸载器：统一删除 frp 服务、配置文件、hosts 入口和 Git rewrite。
- 多环境配置：为办公室、家庭网络、CI 机器提供不同 `.env` 模板。

这些扩展应继续遵守当前设计原则：公网最小暴露、默认本机 loopback、XTCP 优先、STCP 兜底、客户端迁移和回滚可控。
