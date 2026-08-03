# handshake-source 原理与实现机制

## 1. 目录定位

`handshake-source/` 部署在内网 GitLab 宿主机上，是旧 Handshake 链路里的源端隧道角色。它主动 SSH 登录阿里云 `handshake-server` 的跳板用户，并通过 `ssh -R` 把内网 GitLab 的本地端口发布到阿里云 loopback。

它不处理开发者公钥、不改 Git 配置、不运行 GitLab，只负责维持内网到公网跳板机的一条反向 SSH tunnel。

## 2. 反向隧道原理

普通公网访问要求公网机器主动连接内网服务。内网机器通常没有公网入站能力，所以本目录反过来让内网机器主动连出到阿里云：

```text
internal GitLab host
  -> ssh gitproxy@Aliyun
  -> -R Aliyun 127.0.0.1:18080 to local 127.0.0.1:8929
  -> -R Aliyun 127.0.0.1:12222 to local 127.0.0.1:2222
```

映射结果：

```text
Aliyun 127.0.0.1:18080 -> internal GitLab Web 127.0.0.1:8929
Aliyun 127.0.0.1:12222 -> internal GitLab SSH 127.0.0.1:2222
```

开发者不能直接访问这些 loopback 端口，但可以通过 `handshake-client` 的 ProxyJump 或本地 `ssh -L` 使用它们。

## 3. 核心文件

- `env.example`: 阿里云 host/user、SSH identity、keepalive 参数、本地 GitLab 端口和远端 loopback 端口。
- `tunnel.sh`: 生成并执行 `ssh -R` 或连通性检查命令。
- `install.sh`: 安装 openssh client/curl，验证 SSH 登录，把 `tunnel.sh tunnel` 安装为 systemd 服务。
- `status.sh`: 查看 systemd 服务状态并打印本地/远端端口配置。
- `tests/tunnel_test.sh`: 验证 `tunnel.sh` 的 help、dry-run、端口映射和必填 host 校验。
- `README.md`: 简明安装和检查说明。

## 4. tunnel.sh 命令机制

`tunnel.sh` 支持：

```bash
./tunnel.sh tunnel
./tunnel.sh check
./tunnel.sh help
```

配置加载顺序：

```text
save command-line env overrides
  -> source .env when exists
  -> fallback source env.example
  -> restore explicit env overrides
  -> apply defaults
```

这样测试可以用 `DRY_RUN=1 HANDSHAKE_SERVER_HOST=...` 覆盖 `.env`。

`tunnel` 子命令会生成：

```bash
ssh -N \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R 127.0.0.1:18080:127.0.0.1:8929 \
  -R 127.0.0.1:12222:127.0.0.1:2222 \
  gitproxy@<HANDSHAKE_SERVER_HOST>
```

如果配置了 `SSH_IDENTITY_FILE`，会额外加入：

```text
-i <file> -o IdentitiesOnly=yes
```

`check` 子命令只测试能否非交互登录跳板机：

```text
ssh -o BatchMode=yes -o ConnectTimeout=10 gitproxy@<host> true
```

## 5. 关键 SSH 参数

`ExitOnForwardFailure=yes` 很重要。如果远端端口已经被占用，或者跳板机 `authorized_keys` 的 `permitlisten` 不允许监听对应端口，SSH 会立即失败，而不是留下一个看似运行但没有转发成功的进程。

`ServerAliveInterval` 和 `ServerAliveCountMax` 用来让 SSH 在网络断开时退出。配合 systemd 的 `Restart=always`，隧道会自动重连。

## 6. systemd 安装机制

`install.sh` 会写入：

```text
/etc/systemd/system/handshake-source-tunnel.service
```

服务内容核心：

```text
WorkingDirectory=<handshake-source directory>
EnvironmentFile=<handshake-source directory>/.env
ExecStart=<handshake-source directory>/tunnel.sh tunnel
Restart=always
RestartSec=5
```

服务以当前执行安装脚本的用户运行：

```text
User=$(id -un)
Group=$(id -gn)
```

因此 source 主机上用于登录阿里云的私钥也应该对这个用户可用。

## 7. 安装流程

推荐操作：

```bash
cp env.example .env
vim .env
./install.sh
```

脚本执行顺序：

```text
create .env when missing
  -> source .env
  -> validate HANDSHAKE_SERVER_HOST
  -> apt install openssh-client curl
  -> ./tunnel.sh check
  -> render systemd unit
  -> systemctl daemon-reload
  -> systemctl enable --now handshake-source-tunnel.service
```

`./tunnel.sh check` 能提前发现 source key 没有加入阿里云 `gitproxy`、host 不可达、私钥不匹配等问题。

## 8. 状态检查

`status.sh` 只检查 systemd 状态并打印配置：

```text
Local GitLab HTTP: 127.0.0.1:8929
Local GitLab SSH:  127.0.0.1:2222
Aliyun host:        <host>
Remote HTTP:        127.0.0.1:18080
Remote SSH:         127.0.0.1:12222
```

如果客户端 Git SSH 不通，应按顺序确认：

```text
GitLab 本地 2222 是否通
source 到 Aliyun SSH 是否通
handshake-source-tunnel.service 是否运行
Aliyun authorized_keys 是否允许 permitlisten 12222/18080
client SSH config 是否指向 gitlab-via-handshake
```

## 9. 安全边界

远端监听绑定在 `127.0.0.1`，不是 `0.0.0.0`。这意味着阿里云公网不会直接开放 GitLab Web/SSH，只有登录到跳板机或通过 ProxyJump 的受限 SSH 连接才能使用这些 loopback 端口。

source 主机公钥应该使用 `permitlisten` 限权，只允许创建本项目需要的 `12222` 和 `18080` 两个远端监听。
