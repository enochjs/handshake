# handshake-server 原理与实现机制

## 1. 目录定位

`handshake-server/` 是旧 Handshake 链路中的阿里云跳板机角色。它提供公网固定 SSH 入口、一次性 token 公钥注册服务，并接收内网 GitLab 宿主机通过 `handshake-source/` 建立的 SSH 反向隧道。

在推荐 frp 方案中，这个目录主要作为回滚路径保留；在旧链路中，它是开发者客户端和内网 source 的会合点。

## 2. 旧链路中的位置

端到端 Git SSH 链路：

```text
developer git
  -> ssh config Host gitlab-via-handshake
  -> ProxyJump gitproxy@Aliyun
  -> Aliyun 127.0.0.1:12222
  -> reverse SSH tunnel
  -> internal GitLab host 127.0.0.1:2222
  -> GitLab container SSH
```

Web 链路：

```text
developer git hs web
  -> local ssh -L 8929:127.0.0.1:18080 gitproxy@Aliyun
  -> Aliyun 127.0.0.1:18080
  -> reverse SSH tunnel
  -> internal GitLab host 127.0.0.1:8929
```

## 3. 核心文件

- `env.example`: 跳板用户、token 文件、authorized_keys 文件、key server bind/port 和 SSH key 限权选项。
- `install.sh`: 安装依赖、创建 `gitproxy`、初始化 authorized_keys、安装 source tunnel key、部署 Python 注册服务到 systemd。
- `server/add_key_server.py`: token 保护的 HTTP 公钥注册服务。
- `server/add_key_server_test.py`: Python 注册服务单元测试。
- `create-token.sh`: 生成或追加一次性 invite token。
- `status.sh`: 检查 systemd 服务、health endpoint、用户和关键文件。
- `systemd/handshake-add-key.service`: 以 root 运行 key server，使其能写入 `gitproxy` 的 authorized_keys。
- `README.md`: 简明操作说明。

## 4. 跳板用户机制

默认跳板用户：

```text
HANDSHAKE_JUMP_USER=gitproxy
HANDSHAKE_AUTHORIZED_KEYS=/home/gitproxy/.ssh/authorized_keys
```

安装器会：

```text
apt install python3 openssh-server curl rsync
  -> enable ssh
  -> useradd --create-home --shell /bin/bash gitproxy when missing
  -> passwd -l gitproxy
  -> create /home/gitproxy/.ssh
  -> touch authorized_keys
  -> chown/chmod authorized_keys
```

`passwd -l` 锁定密码登录，访问只靠 SSH public key。实际能做什么由 `authorized_keys` 每行前面的 options 限制。

## 5. 开发者 key 注册服务

`server/add_key_server.py` 暴露两个接口：

```text
GET  /healthz
POST /keys
```

`POST /keys` 请求体包含：

```json
{"token":"...","public_key":"ssh-ed25519 AAAA...","comment":"..."}
```

处理流程：

```text
parse JSON
  -> validate public key is single line
  -> validate key type in allowed set
  -> load token file
  -> consume matching token
  -> append key to authorized_keys when not already present
  -> chmod .ssh 700 and authorized_keys 600
```

支持的 key 类型：

```text
ssh-ed25519
ssh-rsa
ecdsa-sha2-nistp256
ecdsa-sha2-nistp384
ecdsa-sha2-nistp521
```

token 是一次性的。`consume_token` 会把已使用 token 从 token 文件中删除，因此同一个 invite token 成功注册后不能重复使用。

## 6. authorized_keys 限权

开发者公钥默认选项来自：

```text
HANDSHAKE_AUTHORIZED_KEYS_OPTIONS='restrict,port-forwarding,permitopen="127.0.0.1:12222"'
```

含义：

```text
restrict       -> 禁用大部分 SSH 会话能力
port-forwarding -> 允许端口转发
permitopen     -> 只允许打开 Aliyun 本机 127.0.0.1:12222
```

开发者通过 ProxyJump 访问 GitLab SSH 时，只能打开反向隧道提供的 GitLab SSH 端口，不能任意访问跳板机内网。

source 端公钥使用另一组选项：

```text
restrict,port-forwarding,permitlisten="127.0.0.1:12222",permitlisten="127.0.0.1:18080"
```

这允许内网 source 登录 `gitproxy` 后创建指定的远端监听端口，也就是 `ssh -R` 所需能力。

## 7. source tunnel key 安装

`install.sh` 支持两种方式配置内网 source 主机公钥：

```text
HANDSHAKE_SOURCE_PUBLIC_KEY='ssh-ed25519 AAAA... source-host'
HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE=/path/to/source-public-keys
```

安装器会规范化 key，只保留 key type 和 key body，并追加 comment `source-tunnel`。写入前会用 key body 去重，避免重复追加同一个 source key。

如果没有配置 source key，安装器不会失败，而是输出提示。这允许先部署 key server，再由运维稍后补 source key 并重跑安装器。

## 8. systemd 服务机制

安装器会把整个仓库同步到：

```text
/opt/handshake
```

然后复制：

```text
handshake-server/systemd/handshake-add-key.service
  -> /etc/systemd/system/handshake-add-key.service
```

服务文件使用：

```text
EnvironmentFile=/etc/handshake-server/handshake-server.env
ExecStart=/usr/bin/python3 /opt/handshake/handshake-server/server/add_key_server.py
User=root
```

使用 root 的原因是注册服务需要写入 `/home/gitproxy/.ssh/authorized_keys` 和 token 文件。服务自身逻辑很小，主要安全控制依赖 token、authorized_keys options 和 SSH 用户权限。

## 9. token 生成机制

`create-token.sh` 默认用 Python `secrets.token_urlsafe(32)` 生成 token，然后追加到：

```text
HANDSHAKE_TOKEN_FILE=/etc/handshake-client/tokens
```

也可以指定 token：

```bash
HANDSHAKE_NEW_TOKEN='invite-token-1' ./create-token.sh
```

脚本会确保 token 文件目录权限为 `700`，文件权限为 `600`。

## 10. 状态检查

`status.sh` 检查：

```text
systemctl status handshake-add-key.service
curl http://${HANDSHAKE_SERVER_BIND}:${HANDSHAKE_KEY_SERVER_PORT}/healthz
id gitproxy
getent passwd gitproxy
token file exists
authorized_keys exists
```

如果 health 正常但客户端注册失败，优先检查 token 是否存在、是否已被消费、key server URL 是否能从客户端到达，以及客户端是否通过临时 SSH tunnel 访问本机 `8787`。

## 11. 与 frp 方案的关系

frp 方案上线后，`handshake-server` 不再是首选业务通道。它仍可作为回滚路径：只要 `handshake-source` 反向隧道和 `handshake-client` rewrite 仍可恢复，就能让开发者切回 `gitlab-via-handshake`。
