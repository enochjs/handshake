# Handshake 项目架构设计与原理

## 1. 项目定位

Handshake 是一套面向内网 GitLab 的 SSH 访问通道安装包。它把开发者机器、阿里云跳板机、内网 GitLab 宿主机和 GitLab Docker 服务拆成四个清晰角色，通过 SSH 反向隧道、ProxyJump、Git URL rewrite 和一次性 token 公钥注册，提供一条可安装、可切换、可回滚的访问路径。

核心目标不是构建一个复杂网关，而是用 Linux、OpenSSH、Git config、systemd、Docker Compose 这些稳定组件，拼出一套运维成本低、边界清楚的私有 GitLab 访问方案。

端到端链路如下：

```text
developer client
  -> Aliyun handshake server / gitproxy
  -> reverse tunnel on 127.0.0.1:12222
  -> internal GitLab host 127.0.0.1:2222
  -> GitLab Docker SSH service
```

网页访问链路如下：

```text
developer client 127.0.0.1:8929
  -> local SSH -L tunnel
  -> Aliyun 127.0.0.1:18080
  -> reverse tunnel
  -> internal GitLab host 127.0.0.1:8929
  -> GitLab Docker HTTP service
```

推荐迁移后的 frp 链路如下：

```text
developer browser/git
  -> gitlab.internal:8929 / gitlab.internal:2222
  -> developer frpc visitor on 127.0.0.1
  -> XTCP direct path to internal GitLab host when NAT traversal succeeds
  -> STCP fallback through Aliyun frps when XTCP fails
  -> internal GitLab host 127.0.0.1:8929 / 127.0.0.1:2222
```

这个 frp 链路的目标是降低低配公网服务器压力。XTCP 成功时，Git clone/pull/push 和 Web 请求的业务流量不经过阿里云 `frps`，`frps` 只承担注册、心跳、NAT 协调等控制面工作；XTCP 失败时，STCP fallback 会让业务流量临时经过 `frps`，牺牲一部分服务器带宽换取可用性。

`gitlab.internal` 不依赖公司 DNS。开发者客户端安装时把下面这一行写入本机 hosts：

```text
127.0.0.1 gitlab.internal
```

公网侧不发布 GitLab Web 或 GitLab SSH 地址。阿里云只开放 frp 控制和传输所需端口，GitLab 真实端口仍留在内网宿主机和开发者本机 loopback 上。

## 2. 四角色架构

### 2.1 `gitlab/`: 内网 GitLab 服务

`gitlab/` 负责在内网 GitLab 宿主机上运行 GitLab CE。

主要文件：

- `gitlab/docker-compose.yml`: 定义 GitLab CE 容器、端口、数据卷和健康检查。
- `gitlab/install.sh`: 安装 Docker / Compose，创建数据目录，并启动 GitLab。
- `gitlab/status.sh`, `backup.sh`, `restore.sh`, `set-user-password.sh`: 运维辅助脚本。

默认暴露在内网宿主机上的服务：

```text
HTTP: 10.10.0.216:8929 -> container:80
SSH:  10.10.0.216:2222 -> container:22
```

设计上，GitLab 不需要直接暴露到公网。公网入口由阿里云跳板机承接，内网 GitLab 只面向内网宿主机和反向隧道。

### 2.2 `handshake-server/`: 阿里云握手服务端

`handshake-server/` 运行在阿里云跳板机上，是公网侧的固定入口。

它承担三件事：

1. 创建并管理跳板用户，默认是 `gitproxy`。
2. 运行公钥注册服务，把受邀开发者的公钥写入 `/home/gitproxy/.ssh/authorized_keys`。
3. 接收内网源端创建的反向 SSH tunnel，使阿里云本机 loopback 可以访问内网 GitLab。

主要文件：

- `handshake-server/install.sh`: 安装依赖、创建 `gitproxy`、配置 `authorized_keys`、安装 systemd 服务。
- `handshake-server/server/add_key_server.py`: token 保护的公钥注册 HTTP 服务。
- `handshake-server/create-token.sh`: 生成一次性 invite token。
- `handshake-server/systemd/handshake-add-key.service`: 将公钥注册服务托管给 systemd。

默认端口：

```text
key registration: 127.0.0.1:8787 或配置为 0.0.0.0:8787
reverse GitLab SSH: Aliyun 127.0.0.1:12222
reverse GitLab HTTP: Aliyun 127.0.0.1:18080
```

### 2.3 `handshake-source/`: 内网源端反向隧道

`handshake-source/` 也运行在内网 GitLab 宿主机上。它主动连到阿里云跳板机，并用 `ssh -R` 把内网 GitLab 的本地端口发布到阿里云 loopback。

核心命令由 `handshake-source/tunnel.sh` 生成：

```text
ssh -N
  -R 127.0.0.1:18080:127.0.0.1:8929
  -R 127.0.0.1:12222:127.0.0.1:2222
  gitproxy@<handshake-server>
```

这意味着：

- 阿里云的 `127.0.0.1:12222` 实际通向内网 GitLab SSH。
- 阿里云的 `127.0.0.1:18080` 实际通向内网 GitLab HTTP。
- 内网不需要开放入站公网端口，只需要源端能主动 SSH 到阿里云。

`handshake-source/install.sh` 会把 tunnel 注册为 `handshake-source-tunnel.service`，用 systemd 保持隧道常驻和自动重启。

### 2.4 `handshake-client/`: 开发者客户端

`handshake-client/` 是一个 Rust CLI，安装后命令名为 `git-hs`，Git 会把它暴露成 `git hs`。

它提供这些主要命令：

- `git hs setup --token <token>`: 初始化开发者机器。
- `git hs enable`: 开启 handshake 访问模式。
- `git hs disable`: 切回直连 216 GitLab。
- `git hs status`: 查看当前 rewrite 状态。
- `git hs web`: 启动前台网页访问隧道。

客户端初始化流程由 `handshake-client/src/setup.rs` 定义：

```text
read public key
  -> POST /keys register public key with invite token
  -> write ~/.ssh/handshake_config
  -> ensure Include ~/.ssh/handshake_config in ~/.ssh/config
  -> enable Git URL rewrite
```

### 2.5 `frp-server/`: 阿里云 frps 控制端

`frp-server/` 运行在阿里云低配服务器上，使用 Docker Compose 托管 `frps` 容器。

它只承担三类职责：

1. 接收 `frp-source/` 和 `frp-client/` 的控制连接。
2. 协助 XTCP 建立 P2P 连接。
3. 在 XTCP 失败时作为 STCP fallback 中转。

它不应该配置 GitLab Web/SSH 的 public `tcp`、`http` 或 `https` proxy。这样可以避免公网出现 `gitlab.example.com`、公网 `:8929` 或公网 `:2222` 这类直接入口。

主要文件：

- `frp-server/env.example`: frps 镜像、端口、认证 token、配置路径和版本。
- `frp-server/docker-compose.yml`: 使用 `fatedier/frps` 镜像运行 `frps`，并配置 `restart: unless-stopped`。
- `frp-server/frps.toml.template`: frps TOML 模板。
- `frp-server/install.sh`: 渲染配置并执行 `docker compose up -d`。
- `frp-server/status.sh`: 查看容器状态、日志和监听端口。
- `frp-server/uninstall.sh`: 执行 `docker compose down --remove-orphans`；设置 `FRP_REMOVE_CONFIG=1` 时同时删除生成配置和 `.env`。

### 2.6 `frp-source/`: 内网 GitLab frpc 源端

`frp-source/` 运行在内网 GitLab 宿主机上，使用 Docker Compose 托管 `frpc` 容器。它主动连接阿里云 `frps`，并把本机 GitLab Web/SSH 作为私有 proxy 注册出去。

`frp-source/docker-compose.yml` 使用 `network_mode: host`，这样容器里的 `frpc` 可以直接访问宿主机上的 `127.0.0.1:8929` 和 `127.0.0.1:2222`。这会减少 Docker 网络映射带来的额外复杂度，也避免把 GitLab 端口发布到公网。

默认 proxy：

```text
gitlab-web-xtcp -> 127.0.0.1:8929
gitlab-web-stcp -> 127.0.0.1:8929
gitlab-ssh-xtcp -> 127.0.0.1:2222
gitlab-ssh-stcp -> 127.0.0.1:2222
```

XTCP 是首选路径，STCP 是兜底路径。两者都使用 `secretKey`，只有拿到同一组 `FRP_AUTH_TOKEN` 和 `FRP_SECRET_KEY` 的开发者 visitor 才能接入。

卸载源端通道：

```bash
cd frp-source
./uninstall.sh
```

如果需要连本地生成配置和 `.env` 一起删除：

```bash
cd frp-source
FRP_REMOVE_CONFIG=1 ./uninstall.sh
```

### 2.7 `frp-client/`: 开发者 frpc visitor

`frp-client/` 运行在每个开发者机器上，负责提供稳定的本地入口。

默认本地入口：

```text
Web: http://gitlab.internal:8929
SSH: ssh://git@gitlab.internal:2222/<group>/<repo>.git
```

客户端安装器会做三件事：

1. 渲染 `frpc-client.toml`，绑定 `127.0.0.1:8929` 和 `127.0.0.1:2222`。
2. 写入 hosts：`127.0.0.1 gitlab.internal`。
3. 写入 Git rewrite：把 `ssh://git@10.10.0.216:2222/` 改写到 `ssh://git@gitlab.internal:2222/`。

在 Linux 上，`frp-client/install.sh` 默认安装 `frp-client.service`；在 macOS 上，默认安装 LaunchAgent；其他环境会输出手动启动命令。

## 3. 核心访问原理

### 3.1 SSH 反向隧道

内网源端使用 `ssh -R` 创建反向隧道。普通正向连接要求外部能访问内网服务，而反向隧道把连接方向反过来：内网机器主动连出到阿里云，阿里云上出现一组 loopback 监听端口。

本项目默认映射：

```text
internal 127.0.0.1:2222 -> Aliyun 127.0.0.1:12222
internal 127.0.0.1:8929 -> Aliyun 127.0.0.1:18080
```

这样做的好处是：

- 内网 GitLab 不需要公网地址。
- 阿里云只暴露 SSH 登录入口，不直接暴露 GitLab SSH 端口。
- GitLab 的真实服务端口仍然留在内网主机上。

### 3.2 ProxyJump 二跳 SSH

客户端写入一个受管理的 SSH include 文件，默认内容等价于：

```sshconfig
Host handshake-client-jump
    HostName 106.14.219.191
    User gitproxy
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host gitlab-via-handshake
    HostName 127.0.0.1
    Port 12222
    User git
    ProxyJump handshake-client-jump
```

当 Git 访问 `gitlab-via-handshake` 时，SSH 先登录阿里云 `gitproxy`，再从阿里云本机访问 `127.0.0.1:12222`。这个端口由源端反向隧道接住，最终落到内网 GitLab SSH。

### 3.3 Git URL rewrite

客户端不要求每个仓库都改 remote URL，而是用 Git 全局 rewrite 规则做透明切换。

Handshake 模式写入：

```bash
git config --global \
  url.ssh://git@gitlab-via-handshake/.insteadOf \
  ssh://git@10.10.0.216:2222/
```

效果是：原本指向 `ssh://git@10.10.0.216:2222/...` 的 remote，会被 Git 自动改写为 `ssh://git@gitlab-via-handshake/...`。

直连模式写入相反规则：

```bash
git config --global \
  url.ssh://git@10.10.0.216:2222/.insteadOf \
  ssh://git@gitlab-via-handshake/
```

`handshake-client/src/rewrite_rules.rs` 定义两组前缀和四种状态：

- `Handshake`: 直连地址会被改写到 handshake alias。
- `Direct`: handshake alias 会被改写回直连地址。
- `Mixed`: 两组规则同时存在，配置冲突。
- `Unconfigured`: 两组规则都不存在。

`ToggleService` 在 `enable` / `disable` 时会先写入目标规则，再清理相反规则，使配置最终收敛到单一模式。

### 3.4 一次性 token 公钥注册

开发者第一次安装时需要 invite token。客户端把 token、公钥和 comment 发送到服务端 `/keys`：

```text
POST /keys
{
  "token": "...",
  "public_key": "ssh-ed25519 ...",
  "comment": "handshake-client"
}
```

`add_key_server.py` 的处理逻辑：

1. 校验 token 必须存在。
2. 校验公钥必须是单行，类型必须在允许列表内。
3. 从 token 文件中消费该 token。
4. 把公钥追加到 `gitproxy` 的 `authorized_keys`。
5. 如果 key 已存在，则不重复写入。

默认写入的 authorized_keys options 是：

```text
restrict,port-forwarding,permitopen="127.0.0.1:12222"
```

这限制开发者 key 只能用于受控端口转发，不给它普通 shell 能力。源端 tunnel key 则使用 `permitlisten`，允许它在阿里云 loopback 上监听 `12222` 和 `18080`。

## 4. 安装与启动链路

推荐安装顺序：

```text
1. gitlab/             内网宿主机启动 GitLab Docker
2. handshake-server/   阿里云创建 gitproxy、注册服务和 source key 权限
3. handshake-source/   内网宿主机创建反向隧道 systemd 服务
4. handshake-client/   开发者注册公钥、写 SSH config、开启 Git rewrite
```

每个角色目录都采用同一套操作习惯：

```bash
cp env.example .env
vim .env
./install.sh
```

这种设计让仓库既是源码，又是部署说明。每台机器只需要进入自己的角色目录，不需要理解其他角色的所有细节。

## 5. 安全边界设计

### 5.1 最小暴露

GitLab 的 SSH 和 HTTP 服务默认只在内网宿主机端口上运行。阿里云上反向隧道监听也绑定在 `127.0.0.1`，开发者通过 SSH 跳板访问，而不是直接暴露 GitLab 端口。

### 5.2 最小权限 key

项目用 OpenSSH `authorized_keys` options 限制不同 key 的能力：

- 开发者 key: 允许连到 `127.0.0.1:12222`，用于 Git SSH。
- 源端 key: 允许监听 `127.0.0.1:12222` 和 `127.0.0.1:18080`，用于创建反向隧道。

### 5.3 一次性邀请

Token 文件一行一个 token。成功注册后 token 会被移除，降低 token 泄漏后的复用风险。

### 5.4 客户端可回滚

客户端只管理：

- `~/.ssh/handshake_config`
- `~/.ssh/config` 中的一行 `Include`
- Git 全局 `url.*.insteadOf` rewrite

`git hs disable` 可以把 Git 访问切回直连，`scripts/destroy.sh ROLE=client` 可以清理客户端侧配置。

## 6. 代码模块设计

### 6.1 Rust 客户端分层

`handshake-client/src/lib.rs` 暴露以下模块：

- `setup`: 编排首次安装流程。
- `key_register`: 用 `curl` 调用 key server。
- `ssh_config`: 渲染和写入受管理 SSH config。
- `git_config`: 封装 `git config --global` 读写。
- `rewrite_rules`: 定义 rewrite 前缀和模式检测。
- `toggle_service`: 提供 `status`、`enable`、`disable` 的领域服务。

这种分层把副作用隔离在接口后面：

- `SetupEnvironment` 抽象文件读取、公钥注册、SSH config 写入和 rewrite 开关。
- `GitConfig` 抽象 Git 配置读写。
- `CommandRunner` / `HttpCommandRunner` 抽象外部命令执行。

测试可以用 fake runner 和 fake environment 验证流程顺序、参数和状态，不需要真的修改用户机器。

### 6.2 Python key server

`add_key_server.py` 使用标准库 `ThreadingHTTPServer`，没有引入 Web 框架。

它只提供两个接口：

- `GET /healthz`: 健康检查。
- `POST /keys`: 注册公钥。

服务端保持极小职责：校验、消费 token、写 authorized_keys。它不保存用户表，不管理 GitLab 权限，也不承担 SSH 数据转发。

### 6.3 Shell 安装器

各目录的 `install.sh` 都遵循几个共同原则：

- 从 `.env` 读取配置，缺失时可从 `env.example` 初始化。
- 支持 `DRY_RUN=1` 输出将要执行的命令。
- systemd 服务只用于长期运行组件：key server 和 source tunnel。
- 角色内脚本只操作本角色需要的资源。

## 7. 运维与验证

项目提供根级验证入口：

```bash
scripts/verify.sh
```

它覆盖：

- Shell 脚本语法检查。
- 安装器 dry-run 行为测试。
- GitLab helper 测试。
- Python key server 测试。
- source tunnel 测试。
- Rust client `cargo test`。

常用状态检查：

```bash
gitlab/status.sh
handshake-server/status.sh
handshake-source/status.sh
git hs status
```

完整删除由 `scripts/destroy.sh` 统一处理，按角色清理服务、配置、运行数据和 `.env`。其中 server 角色会移除 `gitproxy` 用户，属于高影响操作，应先用 `DRY_RUN=1` 验证。

## 8. 设计取舍

### 8.1 为什么不用 VPN

VPN 可以解决网络可达性，但会扩大网络边界，并增加客户端和网络侧维护成本。Handshake 只解决 GitLab SSH/HTTP 访问问题，边界更小，部署依赖更少。

### 8.2 为什么用 Git rewrite

如果要求每个仓库改 remote URL，迁移和回滚都容易出错。Git rewrite 把切换点放到全局配置，开发者可以用 `git hs enable` / `git hs disable` 在两种路径之间切换。

### 8.3 为什么 key server 简单化

key server 只负责受邀公钥登记。认证使用一次性 token，授权边界交给 OpenSSH `authorized_keys` options。这样服务端逻辑少，审计面小，失败时也容易定位。

### 8.4 为什么反向隧道跑在 source 端

内网 GitLab 通常不能被公网主动访问，但可以主动连出。让内网源端主动连接阿里云，可以避开公网入站端口、防火墙和 NAT 复杂度。

## 9. 扩展方向

可演进但不必一开始引入的能力：

- 多 GitLab 实例：扩展 `gitlab-via-handshake` alias、端口映射和 rewrite 前缀。
- token 审计：记录 token 创建者、消费时间、公钥指纹。
- key 回收：增加按 comment 或 fingerprint 删除 authorized_keys 条目的工具。
- 自动健康巡检：周期检查 reverse tunnel、key server、GitLab health endpoint。
- 客户端配置模板化：允许不同团队选择不同 jump host、GitLab host alias 和端口。

这些扩展应继续遵守当前设计原则：角色边界清楚、默认最小暴露、客户端可回滚、核心链路尽量基于标准系统组件。
