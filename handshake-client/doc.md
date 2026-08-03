# handshake-client 原理与实现机制

## 1. 目录定位

`handshake-client/` 是旧 Handshake 链路的开发者客户端。它是一个 Rust CLI，安装后的二进制名为 `git-hs`，Git 会把它识别成 `git hs` 子命令。

它负责三件事：

1. 使用一次性 token 把开发者 SSH public key 注册到阿里云跳板用户。
2. 写入受控 SSH config，让 `gitlab-via-handshake` 通过 ProxyJump 访问阿里云 loopback 上的 GitLab SSH。
3. 通过 Git global URL rewrite 在 handshake 模式和直连模式之间切换。

## 2. 模块结构

源码位于 `src/`：

```text
main.rs          CLI 参数解析、命令分发、真实系统适配
setup.rs         setup 编排流程
key_register.rs 通过 curl 调用 key server
ssh_config.rs   渲染和写入 SSH include 配置
git_config.rs   git config --global 适配层
rewrite_rules.rs rewrite 常量和模式判断
toggle_service.rs enable/disable/status 业务服务
lib.rs          模块导出
```

`Cargo.toml` 定义二进制：

```toml
[[bin]]
name = "git-hs"
path = "src/main.rs"
```

项目没有第三方 Rust 依赖，外部能力来自系统命令 `git`、`curl`、`ssh` 和 `cargo`。

## 3. setup 主流程

`git hs setup --token <token>` 最终调用 `setup.rs` 的 `run_setup`：

```text
read public key
  -> POST key server /keys
  -> write managed SSH config
  -> ensure Include line in ~/.ssh/config
  -> enable handshake Git rewrite
```

真实环境适配在 `main.rs` 的 `RealSetupEnvironment`：

```text
read_public_key       -> fs::read_to_string
register_key          -> CurlKeyRegistrar
write_managed_config  -> ssh_config::write_managed_config
ensure_include        -> ssh_config::ensure_include
enable_handshake      -> ToggleService::enable
```

如果 key server 返回 403，setup 会输出“邀请 token 校验失败”的警告，但仍继续写 SSH 配置和 enable rewrite。这是为了让人工已处理 key 的场景仍能完成本地配置。

## 4. key 注册机制

`key_register.rs` 不直接引 HTTP 库，而是封装 `curl`：

```text
curl --fail -sS
  -X POST
  -H "Content-Type: application/json"
  -d '{"token":"...","public_key":"...","comment":"..."}'
  <server-url>/keys
```

JSON 由 `register_key_json` 手动转义生成，覆盖双引号、反斜杠、换行、回车和 tab。`curl --fail` 会让 4xx/5xx 转成非零退出码，错误信息再传回 setup。

默认 key server URL：

```text
http://106.14.219.191:8787
```

安装器里的默认 URL 是本地 tunnel 版本：

```text
http://127.0.0.1:18787
```

这样 key registration 服务可以只绑定阿里云 loopback，不必公网暴露。

## 5. 安装器机制

`install.sh` 负责一键安装，流程比 CLI setup 更完整：

```text
create .env when missing
  -> source .env and preserve explicit env overrides
  -> validate HANDSHAKE_INVITE_TOKEN
  -> optionally start key-server SSH tunnel
  -> cargo run -- setup ...
  -> cargo install --path . --force
  -> verify git-hs on PATH
  -> git-hs status
  -> verify ssh -G gitlab-via-handshake
  -> ssh -T gitlab-via-handshake
```

它会先把命令行环境变量保存到 `_env_...`，读取 `.env` 后再恢复显式传入的值。这样 `DRY_RUN=1` 或临时覆盖 token、路径、端口时不会被 `.env` 覆盖。

## 6. key server 临时隧道

安装器支持在注册 key 前自动创建一个临时本地隧道：

```text
ssh -o ExitOnForwardFailure=yes -N
  -L 18787:127.0.0.1:8787
  handshake
```

触发条件：

```text
HANDSHAKE_KEY_SERVER_TUNNEL=1
or HANDSHAKE_KEY_SERVER_URL points to localhost
```

安装器会检查 `http://127.0.0.1:18787/healthz`，确认隧道可用后再注册 key。脚本退出时会清理后台 SSH tunnel 进程。

## 7. SSH config 机制

`ssh_config.rs` 渲染一个受控 include 文件，默认路径：

```text
~/.ssh/handshake_config
```

内容形态：

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

`ensure_include` 会确保 `~/.ssh/config` 包含：

```text
Include ~/.ssh/handshake_config
```

如果已有 `Host` 或 `Match` 块，会把 Include 插到第一个块之前，避免 OpenSSH 的配置作用域意外影响 include 行。

## 8. Git rewrite 切换机制

`rewrite_rules.rs` 定义两个前缀：

```text
DIRECT_PREFIX=ssh://git@10.10.0.216:2222/
HANDSHAKE_PREFIX=ssh://git@gitlab-via-handshake/
```

开启 handshake：

```bash
git config --global \
  url.ssh://git@gitlab-via-handshake/.insteadOf \
  ssh://git@10.10.0.216:2222/
```

关闭 handshake：

```bash
git config --global \
  url.ssh://git@10.10.0.216:2222/.insteadOf \
  ssh://git@gitlab-via-handshake/
```

`toggle_service.rs` 会在 enable 时设置 handshake rewrite 并删除 direct rewrite；disable 时反过来。`status` 读取两边配置后判断：

```text
Handshake
Direct
Mixed
Unconfigured
```

`Mixed` 表示两组 rewrite 同时存在，需要执行 `enable` 或 `disable` 整理。

## 9. Web 命令机制

`git hs web` 是前台命令，会启动：

```bash
ssh -o ExitOnForwardFailure=yes -N \
  -L 8929:127.0.0.1:18080 \
  gitproxy@106.14.219.191
```

用户保持命令运行后访问：

```text
http://127.0.0.1:8929/
```

这个 Web 隧道没有注册为后台服务，是临时调试和访问用法。

## 10. refresh 命令

`git hs refresh` 执行：

```bash
cargo install --path <source-dir> --force
```

它只刷新本地 `git-hs` 二进制，不重新注册 key，也不重写 SSH config。适合源码更新后快速更新命令。

## 11. 测试边界

Rust 测试覆盖 CLI 解析、setup 顺序、curl 参数、SSH config 渲染和 rewrite 状态切换。仓库根验证通过 `scripts/verify.sh` 进入本目录运行：

```bash
cargo test
```

安装器自身由 `scripts/test_installers.sh` 的 dry-run 断言覆盖。
