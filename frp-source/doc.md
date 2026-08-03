# frp-source 原理与实现机制

## 1. 目录定位

`frp-source/` 部署在内网 GitLab 宿主机上。它运行 `frpc`，主动连接公网 `frp-server/` 的 `frps`，并把内网宿主机上的服务注册成 frp private proxy。

它是 frp 链路里的“服务提供端”。开发者不会直接连接 `frp-source` 所在内网 IP，而是连接本机 `frp-client` visitor；visitor 再通过 frp 与 source 上的 private proxy 建立通道。

## 2. 服务映射

默认把三类本机服务提供给开发者：

```text
GitLab Web: 127.0.0.1:8929
GitLab SSH: 127.0.0.1:2222
Machine SSH: 127.0.0.1:22
```

每个服务同时注册 XTCP 和 STCP 两个 proxy：

```text
gitlab-web-xtcp    -> 127.0.0.1:8929
gitlab-web-stcp    -> 127.0.0.1:8929
gitlab-ssh-xtcp    -> 127.0.0.1:2222
gitlab-ssh-stcp    -> 127.0.0.1:2222
machine-ssh-xtcp   -> 127.0.0.1:22
machine-ssh-stcp   -> 127.0.0.1:22
```

XTCP 是首选路径，用于尝试点对点穿透；STCP 是兜底路径，用于在 XTCP 失败时通过 `frps` 中转。

## 3. 核心文件

- `env.example`: source 侧部署变量，包括 frps 地址、token、secret key、本地 GitLab 和机器 SSH 端口。
- `frpc.toml.template`: source 侧 `frpc` 模板，定义六个 private proxy。
- `docker-compose.yml`: 使用 `fatedier/frpc` 镜像运行 source 容器，并启用 host network。
- `install.sh`: 读取 `.env`，校验必要密钥，渲染 `generated/frpc-source.toml`，启动 Compose。
- `status.sh`: 输出容器状态、日志、本地 GitLab health、GitLab SSH 和机器 SSH 连通性。
- `uninstall.sh`: 停止 source 容器，可选删除 `.env` 和生成配置。

## 4. host network 的原因

`docker-compose.yml` 使用：

```yaml
network_mode: host
```

这是本目录的关键实现选择。GitLab 容器在宿主机上暴露为 `127.0.0.1:8929` 和 `127.0.0.1:2222` 时，如果 `frpc` 放在普通 Docker bridge 网络中，容器里的 `127.0.0.1` 指向的是 frpc 容器自己，而不是宿主机。

host network 让 `frpc` 容器共享宿主机网络命名空间，所以模板中的：

```toml
localIP = "127.0.0.1"
localPort = 8929
```

可以直接访问内网宿主机上的 GitLab Web。这样也避免额外暴露 GitLab 端口或引入 Docker 网关地址差异。

## 5. 配置加载与渲染

安装脚本会优先读取 `.env`。如果真实运行时 `.env` 不存在，会复制 `env.example` 后退出，提醒运维人员补齐配置。`DRY_RUN=1` 时允许直接从环境变量传入临时值。

必填变量：

```text
FRP_SERVER_ADDR
FRP_AUTH_TOKEN
FRP_SECRET_KEY
```

`FRP_AUTH_TOKEN` 用于连接 `frps` 控制面；`FRP_SECRET_KEY` 用于 private proxy 和 visitor 之间的授权。两者职责不同，source 和 client 必须同时一致。

渲染流程：

```text
frpc.toml.template
  -> generated/frpc-source.toml
  -> chmod 600
  -> mounted as /etc/frp/frpc.toml
  -> docker compose up -d
```

## 6. frpc 模板机制

模板先配置 frps 连接：

```toml
serverAddr = "${FRP_SERVER_ADDR}"
serverPort = ${FRP_SERVER_PORT}

auth.method = "token"
auth.token = "${FRP_AUTH_TOKEN}"
```

然后用 `[[proxies]]` 定义 private proxy。例如 GitLab SSH：

```toml
[[proxies]]
name = "gitlab-ssh-xtcp"
type = "xtcp"
secretKey = "${FRP_SECRET_KEY}"
localIP = "${GITLAB_LOCAL_HOST}"
localPort = ${GITLAB_SSH_PORT}

[[proxies]]
name = "gitlab-ssh-stcp"
type = "stcp"
secretKey = "${FRP_SECRET_KEY}"
localIP = "${GITLAB_LOCAL_HOST}"
localPort = ${GITLAB_SSH_PORT}
```

proxy 名称是 source 和 client 的接口契约。`frp-client/frpc.toml.template` 中 visitor 的 `serverName` 必须与这里的 `name` 完全一致。

## 7. 安装流程

推荐操作：

```bash
cp env.example .env
vim .env
./install.sh
```

脚本执行顺序：

```text
load .env
  -> validate FRP_SERVER_ADDR, FRP_AUTH_TOKEN, FRP_SECRET_KEY
  -> render generated/frpc-source.toml
  -> chmod 600 generated config
  -> docker compose up -d
  -> docker compose ps
  -> print local service summary
```

source 端不写 Git 配置、不改 hosts，也不安装 systemd。它的持久化由 Docker Compose 的 `restart: unless-stopped` 负责。

## 8. 状态检查

`status.sh` 检查四件事：

```text
docker compose ps
docker compose logs --tail=80 frpc-source
curl http://127.0.0.1:8929/-/health
nc -z 127.0.0.1 2222
nc -z 127.0.0.1 22
```

如果本地 GitLab health 不通，问题通常在 `gitlab/`。如果本地服务都通但开发者访问失败，继续检查 `frp-server` 的 token、网络、防火墙，以及 `frp-client` 的 visitor 配置。

## 9. 卸载与边界

默认卸载：

```bash
./uninstall.sh
```

完整清理：

```bash
FRP_REMOVE_CONFIG=1 ./uninstall.sh
```

source 端删除后，开发者本地 visitor 仍可能监听端口，但无法真正连到 GitLab private proxy。排障时要区分“本地端口存在”和“端到端链路可用”。

## 10. 安全边界

source 主动连公网 frps，因此内网 GitLab 机器不需要开放公网入站端口。GitLab Web、GitLab SSH 和宿主机 SSH 都只作为 private proxy 出现，不作为 public proxy 出现。

`FRP_SECRET_KEY` 是访问这些 private proxy 的核心共享密钥。新增或移除开发者时，若需要强制失效旧客户端，应同步更换 source 和所有允许访问的 client 上的 secret key。
