# gitlab 原理与实现机制

## 1. 目录定位

`gitlab/` 是内网 GitLab 服务角色，负责在内网宿主机上通过 Docker Compose 启动 GitLab CE。它提供真实的 GitLab Web、GitLab SSH、数据卷、备份恢复和用户密码管理能力。

推荐 frp 链路和旧 handshake 链路都以这个目录提供的 GitLab 为最终服务端：

```text
frp-client or handshake-client
  -> tunnel path
  -> internal GitLab host
  -> gitlab/docker-compose.yml
  -> GitLab CE container
```

## 2. 对外服务端口

默认端口：

```text
HTTP: 10.10.0.216:8929 -> container 80
SSH:  10.10.0.216:2222 -> container 22
```

这些端口是内网宿主机上的服务端口，不是公网入口。frp 方案中，`frp-source` 通过宿主机 loopback 访问它们；handshake 方案中，`handshake-source` 通过 `ssh -R` 把它们映射到阿里云 loopback。

## 3. 核心文件

- `env.example`: GitLab 镜像、容器名、宿主机 IP、HTTP/SSH 端口、备份保留时间和内存预留。
- `docker-compose.yml`: GitLab CE 容器定义、Omnibus 配置、端口映射、数据卷和健康检查。
- `install.sh`: 安装 Docker/Compose、创建数据目录并启动 GitLab。
- `status.sh`: 查看容器状态、`gitlab-ctl status` 和 health endpoint。
- `backup.sh`: 创建 GitLab 官方数据备份，并额外备份配置和密钥。
- `restore.sh`: 根据备份时间戳恢复 GitLab 数据。
- `set-user-password.sh`: 通过 `gitlab-rails runner` 设置或创建用户。
- `README.md`: 简明安装和日常运维说明。

## 4. Docker Compose 机制

GitLab 容器使用：

```yaml
image: ${GITLAB_IMAGE:-gitlab/gitlab-ce:latest}
container_name: ${GITLAB_CONTAINER:-gitlab}
restart: always
```

端口映射：

```yaml
${GITLAB_HTTP_PORT:-8929}:80
${GITLAB_SSH_PORT:-2222}:22
```

数据卷：

```text
./config -> /etc/gitlab
./logs   -> /var/log/gitlab
./data   -> /var/opt/gitlab
```

这三个目录是 GitLab 的持久化核心。`config` 保存 Omnibus 配置和密钥，`data` 保存仓库、数据库相关数据、上传文件等，`logs` 保存日志。

## 5. Omnibus 配置

`docker-compose.yml` 通过 `GITLAB_OMNIBUS_CONFIG` 注入 GitLab 配置：

```ruby
external_url 'http://${GITLAB_HOST_IP}:${GITLAB_HTTP_PORT}'
nginx['listen_port'] = 80
nginx['listen_https'] = false
gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}
gitlab_rails['backup_keep_time'] = ${GITLAB_BACKUP_KEEP_SECONDS}
```

其中 `external_url` 决定 GitLab 页面里生成的 URL，`gitlab_shell_ssh_port` 决定 GitLab 页面展示的 SSH clone 端口。这里保留内网宿主机地址和 `2222`，再由客户端 rewrite 或本地域名把访问导向隧道。

Compose 中还设置了性能相关参数：

```text
puma worker_processes = 4
sidekiq max_concurrency = 20
postgres shared_buffers = 2GB
postgres effective_cache_size = 8GB
mem_reservation = 24g
```

这些值更适合资源较充足的内网宿主机，不适合低配公网服务器。

## 6. 安装流程

推荐操作：

```bash
cp env.example .env
vim .env
./install.sh
```

安装器执行顺序：

```text
create .env when missing
  -> source .env
  -> install docker.io if missing
  -> install docker-compose-v2 if missing
  -> mkdir config logs data backups
  -> docker compose up -d
  -> docker compose ps
  -> print HTTP and SSH clone URL
```

`DRY_RUN=1 ./install.sh` 会打印将执行的命令，适合在新机器上先确认行为。

## 7. 健康检查

`status.sh` 做三层检查：

```text
docker compose ps
docker exec gitlab gitlab-ctl status
curl http://127.0.0.1:${GITLAB_HTTP_PORT}/-/health
```

如果 `docker compose ps` 正常但 health 失败，GitLab 可能仍在首次初始化。GitLab CE 首次启动可能需要较长时间，Compose healthcheck 也配置了 `start_period: 300s`。

## 8. 备份机制

`backup.sh` 做两类备份：

1. GitLab 官方备份：

```bash
docker exec -t gitlab gitlab-backup create STRATEGY=copy CRON=1
```

这会把仓库、数据库、上传文件等数据备份到容器内 `/var/opt/gitlab/backups`，对应宿主机 `./data/backups`。

2. 配置和密钥快照：

```text
gitlab.rb
gitlab-secrets.json
ssh_host_* keys
```

官方数据备份不包含这些密钥。缺少 `gitlab-secrets.json` 可能导致恢复后加密字段、CI secrets、token 等异常；缺少 SSH host keys 会导致客户端看到 host key 变化。

配置快照保存在：

```text
gitlab/backups/config/<timestamp>/
```

`BACKUP_KEEP_DAYS` 控制配置快照清理；官方数据 tar 的保留由 `GITLAB_BACKUP_KEEP_SECONDS` 控制。

## 9. 恢复机制

`restore.sh` 不带参数时列出可用备份；带时间戳时执行恢复：

```bash
./restore.sh <TIMESTAMP>
```

恢复流程：

```text
find matching *_gitlab_backup.tar
  -> wait 5 seconds for manual cancel
  -> gitlab-ctl stop puma
  -> gitlab-ctl stop sidekiq
  -> gitlab-backup restore BACKUP=<TIMESTAMP> force=yes
  -> gitlab-ctl reconfigure
  -> gitlab-ctl restart
```

如果是整机恢复，应先从 `backups/config/<timestamp>/` 恢复 `gitlab-secrets.json`，必要时恢复 `gitlab.rb` 和 SSH host keys，再执行数据恢复。

## 10. 用户密码脚本

`set-user-password.sh` 通过环境变量把目标用户、密码、邮箱、名称传入 `gitlab-rails runner`。

两种模式：

```bash
./set-user-password.sh root 'NewPassword'
./set-user-password.sh --create fenghe 'NewPassword' --email fenghe@example.com --name 'Feng He'
```

脚本会先按 username 或 email 查找用户。`--create` 模式下找不到就创建，并跳过邮件确认。保存时使用 `validate: false`，适合内部应急和初始化场景，生产长期用户管理仍建议通过 GitLab 管理界面或正式流程处理。

## 11. 安全与运维边界

`gitlab/` 目录保存真实数据。`config`、`data`、`backups` 都不应随意删除。仓库根目录的 `scripts/destroy.sh ROLE=gitlab` 会删除这些目录和 `.env`，属于不可逆的强破坏操作，必须先确认备份。

GitLab 不应该直接暴露到公网。公网访问应通过 frp private visitor 或旧 handshake ProxyJump 链路完成。
