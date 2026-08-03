# scripts 原理与实现机制

## 1. 目录定位

`scripts/` 是仓库级运维和验证入口，不属于单台机器角色。它负责把 `gitlab/`、`handshake-*`、`frp-*` 这些角色串起来做测试、迁移和销毁。

这个目录里的脚本大多从仓库根目录运行，目的是避免操作者进入某个角色目录后漏掉跨目录状态。

## 2. 核心文件

- `verify.sh`: 全仓验证入口，串联 shell 语法检查、安装器 smoke test、Python 测试、source tunnel 测试和 Rust 测试。
- `test_installers.sh`: 旧 handshake 方案和 GitLab 脚本的 dry-run smoke test。
- `test_frp_installers.sh`: frp 方案的 dry-run smoke test。
- `test_gitlab_user_helper.sh`: GitLab 用户密码脚本测试。
- `migrate-client-to-frp.sh`: 开发者机器从旧 handshake client 迁移到 frp client。
- `destroy.sh`: 按角色删除运行时服务、配置和数据的强破坏脚本。

## 3. verify.sh 总体验证机制

`verify.sh` 是本仓库的主验证命令：

```bash
scripts/verify.sh
```

执行顺序：

```text
bash -n role scripts
  -> scripts/test_installers.sh
  -> scripts/test_frp_installers.sh
  -> scripts/test_gitlab_user_helper.sh
  -> python3 handshake-server/server/add_key_server_test.py
  -> handshake-source/tests/tunnel_test.sh
  -> cd handshake-client && cargo test
```

第一步 `bash -n` 只做语法检查，不执行真实安装或删除命令。后续 smoke test 主要依赖 `DRY_RUN=1`，通过断言输出内容验证安装器会生成正确命令、模板和关键提示。

## 4. test_installers.sh 机制

`test_installers.sh` 覆盖旧 handshake 路径：

```text
assert role env.example exists
assert install/status scripts executable
assert important strings in templates/scripts
run DRY_RUN=1 installers
assert expected commands and warnings
```

重点覆盖：

```text
handshake-server creates gitproxy
handshake-server enables handshake-add-key.service
source public key writes permitlisten 12222/18080
handshake-source tunnel renders ssh -R mappings
handshake-client install runs cargo setup and temporary key-server tunnel
403 token path does not abort binary refresh
destroy.sh requires explicit confirmation
```

这些测试不证明远端机器真实可用，但能防止脚本接口、默认端口和关键安全限制被意外改坏。

## 5. test_frp_installers.sh 机制

`test_frp_installers.sh` 覆盖 frp 新路径：

```text
frp-server files and docker compose behavior
frp-source XTCP/STCP private proxies
frp-client visitors, fallback, hosts entry and Git rewrite
migrate-client-to-frp cleanup behavior
```

关键断言包括：

```text
frp-server output contains auth.method = "token"
frp-server output does not contain gitlab.internal
frp-source renders gitlab-web/gitlab-ssh/machine-ssh xtcp+stcp
frp-client renders fallbackTo stcp visitors
frp-client writes 127.0.0.1 gitlab.internal
frp-client writes url.ssh://git@gitlab.internal:2222/.insteadOf
```

这里特意断言 `frp-server` 不包含 `gitlab.internal`，是为了保护架构边界：公网 `frps` 不应该变成 GitLab public proxy。

## 6. migrate-client-to-frp.sh 机制

迁移脚本用于开发者机器从旧 `handshake-client` 切到新 `frp-client`：

```bash
scripts/migrate-client-to-frp.sh
```

执行流程：

```text
unset old handshake rewrite
  -> unset old direct rewrite
  -> remove Include ~/.ssh/handshake_config from ~/.ssh/config
  -> rm ~/.ssh/handshake_config
  -> cargo uninstall handshake-client when cargo exists
  -> cd frp-client
  -> bash install.sh
```

它使用的旧 rewrite 默认值：

```text
DIRECT_GITLAB_SSH_PREFIX=ssh://git@10.10.0.216:2222/
HANDSHAKE_GITLAB_SSH_PREFIX=ssh://git@gitlab-via-handshake/
```

迁移后由 `frp-client/install.sh` 写入新的 rewrite：

```text
ssh://git@10.10.0.216:2222/
  -> ssh://git@gitlab.internal:2222/
```

`remove_ssh_include` 用 `awk` 删除精确 Include 行，同时兼容 legacy 的 `Include ~/.ssh/handshake_config`。

## 7. destroy.sh 机制

`destroy.sh` 是强破坏脚本，必须带确认：

```bash
ROLE=client DESTROY_CONFIRM=delete-handshake ./scripts/destroy.sh
ROLE=all DESTROY_CONFIRM=delete-handshake ./scripts/destroy.sh
```

支持角色：

```text
gitlab
server
source
client
all
```

确认变量 `DESTROY_CONFIRM=delete-handshake` 是硬门槛。没有它即使 `DRY_RUN=1` 也会失败并输出用法，防止误删。

各角色行为：

```text
gitlab -> docker compose down --volumes, rm config/logs/data/backups/.env
server -> disable handshake-add-key.service, delete /etc/handshake-server, /opt/handshake, token file, gitproxy user
source -> disable handshake-source-tunnel.service, remove unit and .env
client -> cargo run -- disable, remove handshake_config and .env
all    -> client, source, server, gitlab in order
```

`ROLE=gitlab` 会删除真实数据卷，必须先确认备份。

## 8. DRY_RUN 设计

多数脚本实现了统一的 `run` 或 `run_shell` 包装：

```text
DRY_RUN=1 -> print command
otherwise -> execute command
```

这让 smoke test 可以断言危险命令会被正确构造，而不会真的改系统用户、systemd、Docker 或 Git global config。

## 9. 脚本边界

`scripts/` 不保存真实 secret，也不应该硬编码生产 token。所有敏感值应该来自各角色目录的 `.env` 或运行时环境变量。

跨目录脚本会改变用户级或系统级状态，尤其是：

```text
git config --global
/etc/hosts
/etc/systemd/system
/etc/handshake-server
/opt/handshake
GitLab data volumes
```

真实执行前建议先跑对应 `DRY_RUN=1`，再跑 `scripts/verify.sh` 确认仓库级测试仍通过。
