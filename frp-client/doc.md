# frp-client 原理与实现机制

## 1. 目录定位

`frp-client/` 部署在每个开发者机器上。它运行本地 `frpc` visitor，把开发者熟悉的本地地址转换成 frp private proxy 访问。

安装完成后，开发者使用：

```text
Web:         http://gitlab.internal:8929
GitLab SSH: ssh://git@gitlab.internal:2222/<group>/<repo>.git
Machine SSH: ssh linkmore@gitlab.internal -p 10022
```

`gitlab.internal` 不是公网 DNS，而是客户端安装器写入 `/etc/hosts` 的本机别名：

```text
127.0.0.1 gitlab.internal
```

因此所有入口都先落到本机 loopback，再由本机 `frpc` visitor 连接内网 source。

## 2. 链路原理

访问 GitLab Web 时：

```text
browser
  -> http://gitlab.internal:8929
  -> /etc/hosts resolves gitlab.internal to 127.0.0.1
  -> frpc gitlab-web-xtcp-visitor
  -> frp-source gitlab-web-xtcp
  -> internal GitLab 127.0.0.1:8929
```

如果 XTCP 建连超时，visitor 会切到 STCP：

```text
local request
  -> xtcp visitor
  -> fallbackTimeoutMs reached
  -> stcp visitor
  -> frp-server frps relay
  -> frp-source stcp proxy
  -> internal service
```

GitLab SSH 和宿主机 SSH 也是同样机制，只是本地端口和远端 proxy 名不同。

## 3. 核心文件

- `env.example`: 客户端变量模板，包含 frps 地址、token、secret key、本地域名、本地端口、fallback 参数、Git rewrite 和服务管理方式。
- `frpc.toml.template`: visitor 配置模板，定义 Web、GitLab SSH、机器 SSH 三组 XTCP/STCP visitor。
- `install.sh`: 安装 `frpc` 二进制、渲染配置、写 hosts、写 Git rewrite、安装 systemd 或 launchd 服务。
- `status.sh`: 检查 hosts、GitLab Web health、GitLab SSH、机器 SSH 和 Git rewrite。
- `frpc.toml`: 目录内保留的示例 visitor 配置；真实安装默认写到 `/etc/frp/frpc-client.toml`。

## 4. visitor 配置机制

每个业务入口有两个 visitor：一个 STCP visitor 作为 fallback 目标，一个 XTCP visitor 绑定本地端口。

以 GitLab SSH 为例：

```toml
[[visitors]]
name = "gitlab-ssh-stcp-visitor"
type = "stcp"
serverName = "gitlab-ssh-stcp"
secretKey = "${FRP_SECRET_KEY}"
bindPort = -1

[[visitors]]
name = "gitlab-ssh-xtcp-visitor"
type = "xtcp"
serverName = "gitlab-ssh-xtcp"
secretKey = "${FRP_SECRET_KEY}"
bindAddr = "${GITLAB_SSH_BIND_ADDR}"
bindPort = ${GITLAB_SSH_BIND_PORT}
keepTunnelOpen = ${FRP_KEEP_TUNNEL_OPEN}
fallbackTo = "gitlab-ssh-stcp-visitor"
fallbackTimeoutMs = ${FRP_FALLBACK_TIMEOUT_MS}
```

STCP visitor 使用 `bindPort = -1`，它不直接占用开发者看到的本地业务端口，只作为 XTCP visitor 的 fallback 目标。XTCP visitor 绑定固定本地端口，比如 GitLab SSH 默认 `127.0.0.1:2222`。

三组默认绑定：

```text
gitlab-web-xtcp-visitor  -> 127.0.0.1:8929  -> gitlab-web-xtcp
gitlab-ssh-xtcp-visitor  -> 127.0.0.1:2222  -> gitlab-ssh-xtcp
machine-ssh-xtcp-visitor -> 127.0.0.1:10022 -> machine-ssh-xtcp
```

## 5. 配置变量

必填：

```text
FRP_SERVER_ADDR
FRP_AUTH_TOKEN
FRP_SECRET_KEY
```

常用默认值：

```text
FRP_SERVER_PORT=7000
GITLAB_LOCAL_NAME=gitlab.internal
GITLAB_WEB_BIND_ADDR=127.0.0.1
GITLAB_WEB_BIND_PORT=8929
GITLAB_SSH_BIND_ADDR=127.0.0.1
GITLAB_SSH_BIND_PORT=2222
MACHINE_SSH_BIND_ADDR=127.0.0.1
MACHINE_SSH_BIND_PORT=10022
FRP_FALLBACK_TIMEOUT_MS=300
FRP_KEEP_TUNNEL_OPEN=true
```

`FRP_AUTH_TOKEN` 必须与 `frp-server` 一致；`FRP_SECRET_KEY` 必须与 `frp-source` 一致。前者解决“能否连上 frps”，后者解决“能否访问指定 private proxy”。

## 6. 安装器实现机制

`install.sh` 的流程：

```text
preserve command-line env overrides
  -> source .env when exists
  -> restore explicit env overrides
  -> validate required variables
  -> optionally download frpc binary
  -> render /etc/frp/frpc-client.toml
  -> ensure /etc/hosts contains gitlab.internal
  -> git config --global url.<frp-prefix>.insteadOf <direct-prefix>
  -> install service by systemd, launchd, or manual mode
```

脚本开头保存了一组 `_env_...` 和 `_has_...` 变量，是为了让命令行临时传入的环境变量优先级高于 `.env`。这对测试和一次性覆盖很重要，例如：

```bash
DRY_RUN=1 FRP_SKIP_BINARY_INSTALL=1 FRP_SERVICE_MANAGER=systemd ./install.sh
```

即使 `.env` 里设置了其他值，上面的显式环境变量仍会生效。

## 7. 二进制安装

默认会从 frp GitHub release 下载：

```text
https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_${os}_${arch}.tar.gz
```

然后提取 `frpc` 并安装到：

```text
FRP_BINARY_PATH=/usr/local/bin/frpc
```

测试或已预装 frpc 的机器可以设置：

```bash
FRP_SKIP_BINARY_INSTALL=1
```

## 8. 服务管理

`FRP_SERVICE_MANAGER=auto` 时：

```text
Linux  -> systemd
macOS  -> launchd
other  -> manual
```

Linux 上写入 `/etc/systemd/system/frp-client.service`，`ExecStart` 指向 `FRP_BINARY_PATH -c FRP_CONFIG_PATH`。

macOS 上写入：

```text
~/Library/LaunchAgents/com.handshake.frp-client.plist
```

其他系统只输出手动启动命令。这个分支让同一个目录能覆盖服务器 Linux 和开发者 macOS 场景。

## 9. Git rewrite 机制

客户端安装器写入：

```bash
git config --global \
  url.ssh://git@gitlab.internal:2222/.insteadOf \
  ssh://git@10.10.0.216:2222/
```

效果是旧仓库 remote 不需要逐个修改。Git 在解析 URL 时，会把旧的内网 GitLab SSH 前缀自动替换为本机 frp visitor 前缀。

这个机制只影响 Git URL，不影响浏览器访问。浏览器访问靠 `/etc/hosts` 和本地 `frpc` 端口。

## 10. 迁移入口

已有旧 `handshake-client` 的开发者机器，推荐从仓库根目录运行：

```bash
scripts/migrate-client-to-frp.sh
```

迁移脚本会删除旧 handshake rewrite、移除 `~/.ssh/handshake_config` include、尝试卸载 `git-hs`，然后进入 `frp-client/` 执行安装器。

## 11. 状态检查

`status.sh` 会检查：

```text
/etc/hosts 是否包含 gitlab.internal
http://gitlab.internal:8929/-/health
ssh -T -p 2222 git@gitlab.internal
ssh -p 10022 linkmore@gitlab.internal true
Git rewrite 是否存在
```

SSH 命令允许失败后继续输出，因为 GitLab SSH 常见返回并不总是 0，机器 SSH 也可能需要交互认证。排障时主要看是否能建立连接、是否是认证失败、还是端口完全不通。
