# FRP GitLab Internal Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current SSH reverse-tunnel access path with a private frp visitor path so developers use `http://gitlab.internal:8929` and `ssh://git@gitlab.internal:2222/...` without exposing GitLab Web or SSH on a public address.

**Architecture:** Keep `gitlab/` as the internal GitLab deployment. Add three frp roles: `frp-server/` runs low-pressure `frps` on Aliyun for control, NAT coordination, and fallback only; `frp-source/` runs `frpc` on the internal GitLab host and exposes GitLab Web/SSH as `xtcp` plus `stcp` fallback proxies; `frp-client/` runs `frpc` visitors on each developer machine, binds local loopback ports, writes `gitlab.internal -> 127.0.0.1`, and configures Git URL rewrite once. In the best case XTCP carries business traffic peer-to-peer; when hole punching fails, STCP fallback preserves availability through frps.

**Tech Stack:** GitLab CE Docker Compose, frp v0.68+ TOML configs, Bash installers, systemd on Linux servers, launchd/systemd/manual fallback on developer machines, OpenSSH/Git config.

## Global Constraints

- Do not expose GitLab Web or GitLab SSH as public `frps` TCP/HTTP/HTTPS proxies.
- Public Aliyun server should expose only frp control and required frp transport ports.
- Developers must access Web at `http://gitlab.internal:8929`.
- Developers must access Git SSH through `ssh://git@gitlab.internal:2222/<group>/<repo>.git`.
- `gitlab.internal` must resolve locally to `127.0.0.1`; do not require company DNS.
- XTCP must be configured with STCP fallback, because XTCP availability depends on NAT type.
- Preserve current GitLab service ports: Web `8929`, SSH `2222`.
- Preserve easy rollback to current Handshake path until frp is verified.
- Do not store real frp tokens or secrets in committed files.

---

## File Structure

- Create `frp-server/env.example`: Aliyun frps runtime variables and generated secret placeholders.
- Create `frp-server/frps.toml.template`: frps control/auth configuration; no public GitLab proxy.
- Create `frp-server/install.sh`: install frp binary, render config, install `frps.service`.
- Create `frp-server/status.sh`: show service health and listening ports.
- Create `frp-source/env.example`: internal GitLab host frpc variables for Web/SSH xtcp and stcp proxies.
- Create `frp-source/frpc.toml.template`: source-side xtcp/stcp proxy definitions.
- Create `frp-source/install.sh`: install frpc and `frp-source.service`.
- Create `frp-source/status.sh`: show frpc service and local GitLab health.
- Create `frp-client/env.example`: developer machine frpc visitor variables, local host name, local ports, and Git rewrite settings.
- Create `frp-client/frpc.toml.template`: visitor config binding `127.0.0.1:8929` and `127.0.0.1:2222`, with XTCP visitors falling back to STCP visitors.
- Create `frp-client/install.sh`: install frpc, render config, install user service where possible, add hosts entry, configure Git rewrite.
- Create `frp-client/status.sh`: verify hosts entry, local visitor ports, frpc service, Web health, and Git SSH handshake.
- Modify `scripts/verify.sh`: include frp shell syntax and smoke tests.
- Create `scripts/test_frp_installers.sh`: dry-run tests for templates and installers.
- Modify `readme.md`: document the frp-first architecture and keep Handshake rollback notes.
- Modify `doc.md`: add migration rationale, traffic paths, security boundaries, and rollback.

## Task 1: Add FRP Server Role

**Files:**
- Create: `frp-server/env.example`
- Create: `frp-server/frps.toml.template`
- Create: `frp-server/install.sh`
- Create: `frp-server/status.sh`

**Interfaces:**
- Consumes: none.
- Produces: `/etc/frp/frps.toml`, `frps.service`, public frps endpoint `${FRP_SERVER_ADDR}:${FRP_BIND_PORT}`.

- [ ] **Step 1: Write the failing smoke test**

Add this initial block to `scripts/test_frp_installers.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_executable() {
  [[ -x "$1" ]] || fail "not executable: $1"
}

assert_contains_text() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected '$needle' in output"
}

assert_file frp-server/env.example
assert_file frp-server/frps.toml.template
assert_executable frp-server/install.sh
assert_executable frp-server/status.sh

server_dry_run="$(DRY_RUN=1 FRP_AUTH_TOKEN=test-token bash frp-server/install.sh)"
assert_contains_text "$server_dry_run" "frps.toml"
assert_contains_text "$server_dry_run" "bindPort = 7000"
assert_contains_text "$server_dry_run" "auth.method = \"token\""
assert_contains_text "$server_dry_run" "systemctl enable --now frps.service"

echo "PASS: frp installer smoke tests"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test_frp_installers.sh`

Expected: FAIL with `missing file: frp-server/env.example`.

- [ ] **Step 3: Create server config files**

Create `frp-server/env.example`:

```bash
FRP_VERSION=0.68.0
FRP_SERVER_BIND_ADDR=0.0.0.0
FRP_BIND_PORT=7000
FRP_AUTH_TOKEN=
FRP_CONFIG_PATH=/etc/frp/frps.toml
FRP_BINARY_PATH=/usr/local/bin/frps
FRP_LOG_LEVEL=info
FRP_LOG_MAX_DAYS=7
```

Create `frp-server/frps.toml.template`:

```toml
bindAddr = "${FRP_SERVER_BIND_ADDR}"
bindPort = ${FRP_BIND_PORT}

auth.method = "token"
auth.token = "${FRP_AUTH_TOKEN}"

log.level = "${FRP_LOG_LEVEL}"
log.maxDays = ${FRP_LOG_MAX_DAYS}
```

- [ ] **Step 4: Create server installer**

Create `frp-server/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
[[ -f .env ]] && set -a && source .env && set +a
[[ -f .env || "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]] || { cp env.example .env; echo "Created frp-server/.env; set FRP_AUTH_TOKEN and rerun."; exit 1; }
[[ -f .env ]] || set -a && source env.example && set +a

FRP_VERSION="${FRP_VERSION:-0.68.0}"
FRP_SERVER_BIND_ADDR="${FRP_SERVER_BIND_ADDR:-0.0.0.0}"
FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:-}"
FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-/etc/frp/frps.toml}"
FRP_BINARY_PATH="${FRP_BINARY_PATH:-/usr/local/bin/frps}"
FRP_LOG_LEVEL="${FRP_LOG_LEVEL:-info}"
FRP_LOG_MAX_DAYS="${FRP_LOG_MAX_DAYS:-7}"

[[ -n "$FRP_AUTH_TOKEN" ]] || { echo "FRP_AUTH_TOKEN is required"; exit 1; }

print_cmd() { printf '%q ' "$@"; printf '\n'; }
run() {
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    print_cmd "$@"
  else
    "$@"
  fi
}

render_config() {
  sed \
    -e "s|\${FRP_SERVER_BIND_ADDR}|${FRP_SERVER_BIND_ADDR}|g" \
    -e "s|\${FRP_BIND_PORT}|${FRP_BIND_PORT}|g" \
    -e "s|\${FRP_AUTH_TOKEN}|${FRP_AUTH_TOKEN}|g" \
    -e "s|\${FRP_LOG_LEVEL}|${FRP_LOG_LEVEL}|g" \
    -e "s|\${FRP_LOG_MAX_DAYS}|${FRP_LOG_MAX_DAYS}|g" \
    frps.toml.template
}

run sudo install -d -m 755 "$(dirname "$FRP_CONFIG_PATH")"
if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  echo "Would render $FRP_CONFIG_PATH"
  render_config
else
  render_config | sudo tee "$FRP_CONFIG_PATH" >/dev/null
  sudo chmod 600 "$FRP_CONFIG_PATH"
fi

run sudo tee /etc/systemd/system/frps.service
run sudo systemctl daemon-reload
run sudo systemctl enable --now frps.service
run sudo systemctl --no-pager --full status frps.service
```

Create `frp-server/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

systemctl --no-pager --full status frps.service
ss -lntup | grep -E '(:7000)\b' || true
```

Make scripts executable:

```bash
chmod +x frp-server/install.sh frp-server/status.sh scripts/test_frp_installers.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash scripts/test_frp_installers.sh`

Expected: PASS with `PASS: frp installer smoke tests`.

- [ ] **Step 6: Commit**

```bash
git add frp-server scripts/test_frp_installers.sh
git commit -m "feat: add frp server role"
```

## Task 2: Add FRP Source Role

**Files:**
- Create: `frp-source/env.example`
- Create: `frp-source/frpc.toml.template`
- Create: `frp-source/install.sh`
- Create: `frp-source/status.sh`
- Modify: `scripts/test_frp_installers.sh`

**Interfaces:**
- Consumes: frps endpoint `${FRP_SERVER_ADDR}:${FRP_SERVER_PORT}` and `${FRP_AUTH_TOKEN}` from Task 1.
- Produces: source proxies `gitlab-web-xtcp`, `gitlab-web-stcp`, `gitlab-ssh-xtcp`, `gitlab-ssh-stcp`.

- [ ] **Step 1: Extend the failing smoke test**

Append before the final PASS line in `scripts/test_frp_installers.sh`:

```bash
assert_file frp-source/env.example
assert_file frp-source/frpc.toml.template
assert_executable frp-source/install.sh
assert_executable frp-source/status.sh

source_dry_run="$(
  DRY_RUN=1 \
  FRP_SERVER_ADDR=frps.example.com \
  FRP_AUTH_TOKEN=test-token \
  FRP_SECRET_KEY=test-secret \
  bash frp-source/install.sh
)"
assert_contains_text "$source_dry_run" "serverAddr = \"frps.example.com\""
assert_contains_text "$source_dry_run" "name = \"gitlab-web-xtcp\""
assert_contains_text "$source_dry_run" "type = \"xtcp\""
assert_contains_text "$source_dry_run" "name = \"gitlab-web-stcp\""
assert_contains_text "$source_dry_run" "localPort = 8929"
assert_contains_text "$source_dry_run" "localPort = 2222"
assert_contains_text "$source_dry_run" "systemctl enable --now frp-source.service"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test_frp_installers.sh`

Expected: FAIL with `missing file: frp-source/env.example`.

- [ ] **Step 3: Create source config files**

Create `frp-source/env.example`:

```bash
FRP_VERSION=0.68.0
FRP_SERVER_ADDR=
FRP_SERVER_PORT=7000
FRP_AUTH_TOKEN=
FRP_SECRET_KEY=
GITLAB_LOCAL_HOST=127.0.0.1
GITLAB_WEB_PORT=8929
GITLAB_SSH_PORT=2222
FRP_CONFIG_PATH=/etc/frp/frpc-source.toml
FRP_BINARY_PATH=/usr/local/bin/frpc
```

Create `frp-source/frpc.toml.template`:

```toml
serverAddr = "${FRP_SERVER_ADDR}"
serverPort = ${FRP_SERVER_PORT}

auth.method = "token"
auth.token = "${FRP_AUTH_TOKEN}"

[[proxies]]
name = "gitlab-web-xtcp"
type = "xtcp"
secretKey = "${FRP_SECRET_KEY}"
localIP = "${GITLAB_LOCAL_HOST}"
localPort = ${GITLAB_WEB_PORT}

[[proxies]]
name = "gitlab-web-stcp"
type = "stcp"
secretKey = "${FRP_SECRET_KEY}"
localIP = "${GITLAB_LOCAL_HOST}"
localPort = ${GITLAB_WEB_PORT}

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

- [ ] **Step 4: Create source installer**

Create `frp-source/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
[[ -f .env ]] && set -a && source .env && set +a
[[ -f .env || "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]] || { cp env.example .env; echo "Created frp-source/.env; fill it and rerun."; exit 1; }
[[ -f .env ]] || set -a && source env.example && set +a

FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:-}"
FRP_SECRET_KEY="${FRP_SECRET_KEY:-}"
GITLAB_LOCAL_HOST="${GITLAB_LOCAL_HOST:-127.0.0.1}"
GITLAB_WEB_PORT="${GITLAB_WEB_PORT:-8929}"
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"
FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-/etc/frp/frpc-source.toml}"

[[ -n "$FRP_SERVER_ADDR" ]] || { echo "FRP_SERVER_ADDR is required"; exit 1; }
[[ -n "$FRP_AUTH_TOKEN" ]] || { echo "FRP_AUTH_TOKEN is required"; exit 1; }
[[ -n "$FRP_SECRET_KEY" ]] || { echo "FRP_SECRET_KEY is required"; exit 1; }

print_cmd() { printf '%q ' "$@"; printf '\n'; }
run() {
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    print_cmd "$@"
  else
    "$@"
  fi
}

render_config() {
  sed \
    -e "s|\${FRP_SERVER_ADDR}|${FRP_SERVER_ADDR}|g" \
    -e "s|\${FRP_SERVER_PORT}|${FRP_SERVER_PORT}|g" \
    -e "s|\${FRP_AUTH_TOKEN}|${FRP_AUTH_TOKEN}|g" \
    -e "s|\${FRP_SECRET_KEY}|${FRP_SECRET_KEY}|g" \
    -e "s|\${GITLAB_LOCAL_HOST}|${GITLAB_LOCAL_HOST}|g" \
    -e "s|\${GITLAB_WEB_PORT}|${GITLAB_WEB_PORT}|g" \
    -e "s|\${GITLAB_SSH_PORT}|${GITLAB_SSH_PORT}|g" \
    frpc.toml.template
}

run sudo install -d -m 755 "$(dirname "$FRP_CONFIG_PATH")"
if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  echo "Would render $FRP_CONFIG_PATH"
  render_config
else
  render_config | sudo tee "$FRP_CONFIG_PATH" >/dev/null
  sudo chmod 600 "$FRP_CONFIG_PATH"
fi

run sudo tee /etc/systemd/system/frp-source.service
run sudo systemctl daemon-reload
run sudo systemctl enable --now frp-source.service
run sudo systemctl --no-pager --full status frp-source.service
```

Create `frp-source/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

systemctl --no-pager --full status frp-source.service
curl -fsS "http://127.0.0.1:${GITLAB_WEB_PORT:-8929}/-/health" || true
nc -z 127.0.0.1 "${GITLAB_SSH_PORT:-2222}" || true
```

Make scripts executable:

```bash
chmod +x frp-source/install.sh frp-source/status.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash scripts/test_frp_installers.sh`

Expected: PASS with `PASS: frp installer smoke tests`.

- [ ] **Step 6: Commit**

```bash
git add frp-source scripts/test_frp_installers.sh
git commit -m "feat: add frp source role"
```

## Task 3: Add FRP Developer Client Role

**Files:**
- Create: `frp-client/env.example`
- Create: `frp-client/frpc.toml.template`
- Create: `frp-client/install.sh`
- Create: `frp-client/status.sh`
- Modify: `scripts/test_frp_installers.sh`

**Interfaces:**
- Consumes: source proxy names from Task 2.
- Produces: local visitor ports `127.0.0.1:8929` and `127.0.0.1:2222`, local hostname `gitlab.internal`, and Git rewrite from direct internal URL to frp-local URL.

- [ ] **Step 1: Extend the failing smoke test**

Append before the final PASS line in `scripts/test_frp_installers.sh`:

```bash
assert_file frp-client/env.example
assert_file frp-client/frpc.toml.template
assert_executable frp-client/install.sh
assert_executable frp-client/status.sh

client_dry_run="$(
  DRY_RUN=1 \
  FRP_SERVER_ADDR=frps.example.com \
  FRP_AUTH_TOKEN=test-token \
  FRP_SECRET_KEY=test-secret \
  bash frp-client/install.sh
)"
assert_contains_text "$client_dry_run" "serverAddr = \"frps.example.com\""
assert_contains_text "$client_dry_run" "bindAddr = \"127.0.0.1\""
assert_contains_text "$client_dry_run" "bindPort = 8929"
assert_contains_text "$client_dry_run" "bindPort = 2222"
assert_contains_text "$client_dry_run" "fallbackTo = \"gitlab-web-stcp-visitor\""
assert_contains_text "$client_dry_run" "fallbackTo = \"gitlab-ssh-stcp-visitor\""
assert_contains_text "$client_dry_run" "127.0.0.1 gitlab.internal"
assert_contains_text "$client_dry_run" "git config --global url.ssh://git@gitlab.internal:2222/.insteadOf ssh://git@10.10.0.216:2222/"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test_frp_installers.sh`

Expected: FAIL with `missing file: frp-client/env.example`.

- [ ] **Step 3: Create client config files**

Create `frp-client/env.example`:

```bash
FRP_VERSION=0.68.0
FRP_SERVER_ADDR=
FRP_SERVER_PORT=7000
FRP_AUTH_TOKEN=
FRP_SECRET_KEY=
GITLAB_LOCAL_NAME=gitlab.internal
GITLAB_WEB_BIND_ADDR=127.0.0.1
GITLAB_WEB_BIND_PORT=8929
GITLAB_SSH_BIND_ADDR=127.0.0.1
GITLAB_SSH_BIND_PORT=2222
FRP_FALLBACK_TIMEOUT_MS=300
FRP_KEEP_TUNNEL_OPEN=true
DIRECT_GITLAB_SSH_PREFIX=ssh://git@10.10.0.216:2222/
FRP_GITLAB_SSH_PREFIX=ssh://git@gitlab.internal:2222/
FRP_CONFIG_PATH=/etc/frp/frpc-client.toml
```

Create `frp-client/frpc.toml.template`:

```toml
serverAddr = "${FRP_SERVER_ADDR}"
serverPort = ${FRP_SERVER_PORT}

auth.method = "token"
auth.token = "${FRP_AUTH_TOKEN}"

[[visitors]]
name = "gitlab-web-stcp-visitor"
type = "stcp"
serverName = "gitlab-web-stcp"
secretKey = "${FRP_SECRET_KEY}"
bindPort = -1

[[visitors]]
name = "gitlab-web-xtcp-visitor"
type = "xtcp"
serverName = "gitlab-web-xtcp"
secretKey = "${FRP_SECRET_KEY}"
bindAddr = "${GITLAB_WEB_BIND_ADDR}"
bindPort = ${GITLAB_WEB_BIND_PORT}
keepTunnelOpen = ${FRP_KEEP_TUNNEL_OPEN}
fallbackTo = "gitlab-web-stcp-visitor"
fallbackTimeoutMs = ${FRP_FALLBACK_TIMEOUT_MS}

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

- [ ] **Step 4: Create client installer**

Create `frp-client/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
[[ -f .env ]] && set -a && source .env && set +a
[[ -f .env || "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]] || { cp env.example .env; echo "Created frp-client/.env; fill it and rerun."; exit 1; }
[[ -f .env ]] || set -a && source env.example && set +a

FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:-}"
FRP_SECRET_KEY="${FRP_SECRET_KEY:-}"
GITLAB_LOCAL_NAME="${GITLAB_LOCAL_NAME:-gitlab.internal}"
GITLAB_WEB_BIND_ADDR="${GITLAB_WEB_BIND_ADDR:-127.0.0.1}"
GITLAB_WEB_BIND_PORT="${GITLAB_WEB_BIND_PORT:-8929}"
GITLAB_SSH_BIND_ADDR="${GITLAB_SSH_BIND_ADDR:-127.0.0.1}"
GITLAB_SSH_BIND_PORT="${GITLAB_SSH_BIND_PORT:-2222}"
FRP_FALLBACK_TIMEOUT_MS="${FRP_FALLBACK_TIMEOUT_MS:-300}"
FRP_KEEP_TUNNEL_OPEN="${FRP_KEEP_TUNNEL_OPEN:-true}"
DIRECT_GITLAB_SSH_PREFIX="${DIRECT_GITLAB_SSH_PREFIX:-ssh://git@10.10.0.216:2222/}"
FRP_GITLAB_SSH_PREFIX="${FRP_GITLAB_SSH_PREFIX:-ssh://git@gitlab.internal:2222/}"
FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-/etc/frp/frpc-client.toml}"

[[ -n "$FRP_SERVER_ADDR" ]] || { echo "FRP_SERVER_ADDR is required"; exit 1; }
[[ -n "$FRP_AUTH_TOKEN" ]] || { echo "FRP_AUTH_TOKEN is required"; exit 1; }
[[ -n "$FRP_SECRET_KEY" ]] || { echo "FRP_SECRET_KEY is required"; exit 1; }

print_cmd() { printf '%q ' "$@"; printf '\n'; }
run() {
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    print_cmd "$@"
  else
    "$@"
  fi
}

render_config() {
  sed \
    -e "s|\${FRP_SERVER_ADDR}|${FRP_SERVER_ADDR}|g" \
    -e "s|\${FRP_SERVER_PORT}|${FRP_SERVER_PORT}|g" \
    -e "s|\${FRP_AUTH_TOKEN}|${FRP_AUTH_TOKEN}|g" \
    -e "s|\${FRP_SECRET_KEY}|${FRP_SECRET_KEY}|g" \
    -e "s|\${GITLAB_WEB_BIND_ADDR}|${GITLAB_WEB_BIND_ADDR}|g" \
    -e "s|\${GITLAB_WEB_BIND_PORT}|${GITLAB_WEB_BIND_PORT}|g" \
    -e "s|\${GITLAB_SSH_BIND_ADDR}|${GITLAB_SSH_BIND_ADDR}|g" \
    -e "s|\${GITLAB_SSH_BIND_PORT}|${GITLAB_SSH_BIND_PORT}|g" \
    -e "s|\${FRP_KEEP_TUNNEL_OPEN}|${FRP_KEEP_TUNNEL_OPEN}|g" \
    -e "s|\${FRP_FALLBACK_TIMEOUT_MS}|${FRP_FALLBACK_TIMEOUT_MS}|g" \
    frpc.toml.template
}

run sudo install -d -m 755 "$(dirname "$FRP_CONFIG_PATH")"
if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  echo "Would render $FRP_CONFIG_PATH"
  render_config
  echo "127.0.0.1 ${GITLAB_LOCAL_NAME}"
else
  render_config | sudo tee "$FRP_CONFIG_PATH" >/dev/null
  sudo chmod 600 "$FRP_CONFIG_PATH"
  if ! grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]].*\\b${GITLAB_LOCAL_NAME}\\b" /etc/hosts; then
    printf '127.0.0.1 %s\n' "$GITLAB_LOCAL_NAME" | sudo tee -a /etc/hosts >/dev/null
  fi
fi

run git config --global "url.${FRP_GITLAB_SSH_PREFIX}.insteadOf" "$DIRECT_GITLAB_SSH_PREFIX"
run sudo tee /etc/systemd/system/frp-client.service
run sudo systemctl daemon-reload
run sudo systemctl enable --now frp-client.service
```

Create `frp-client/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

grep -E '127\.0\.0\.1[[:space:]].*gitlab\.internal' /etc/hosts
curl -fsS "http://gitlab.internal:8929/-/health" || true
ssh -o BatchMode=yes -o ConnectTimeout=10 -T -p 2222 git@gitlab.internal || true
git config --global --get-all url.ssh://git@gitlab.internal:2222/.insteadOf || true
```

Make scripts executable:

```bash
chmod +x frp-client/install.sh frp-client/status.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash scripts/test_frp_installers.sh`

Expected: PASS with `PASS: frp installer smoke tests`.

- [ ] **Step 6: Commit**

```bash
git add frp-client scripts/test_frp_installers.sh
git commit -m "feat: add frp developer client role"
```

## Task 4: Integrate Verification

**Files:**
- Modify: `scripts/verify.sh`
- Modify: `scripts/test_frp_installers.sh`

**Interfaces:**
- Consumes: frp role scripts from Tasks 1-3.
- Produces: repository-level verification for frp migration.

- [ ] **Step 1: Write the failing verification change**

Modify `scripts/verify.sh` so the shell syntax block includes:

```bash
  frp-server/install.sh \
  frp-server/status.sh \
  frp-source/install.sh \
  frp-source/status.sh \
  frp-client/install.sh \
  frp-client/status.sh \
```

Add this command after `scripts/test_installers.sh`:

```bash
scripts/test_frp_installers.sh
```

- [ ] **Step 2: Run verification**

Run: `bash scripts/verify.sh`

Expected before implementation is complete: FAIL on missing/executable/config assertions if any frp role is incomplete.

- [ ] **Step 3: Fix syntax and smoke test issues**

For each failure, make the smallest edit needed:

```bash
bash -n frp-server/install.sh frp-source/install.sh frp-client/install.sh
bash scripts/test_frp_installers.sh
```

Expected: both commands pass.

- [ ] **Step 4: Run full verification**

Run: `bash scripts/verify.sh`

Expected: PASS with `PASS: repository verification`.

- [ ] **Step 5: Commit**

```bash
git add scripts/verify.sh scripts/test_frp_installers.sh
git commit -m "test: include frp roles in verification"
```

## Task 5: Document Migration and Rollback

**Files:**
- Modify: `readme.md`
- Modify: `doc.md`

**Interfaces:**
- Consumes: frp role names, ports, and commands from Tasks 1-4.
- Produces: operator-facing install order, developer workflow, traffic-path explanation, and rollback steps.

- [ ] **Step 1: Update `readme.md` install order**

Add this frp-first section near the top of `readme.md`:

```markdown
## Recommended FRP Access Path

Use this path when the public server is low-spec and should avoid carrying GitLab business traffic whenever XTCP hole punching succeeds.

```text
developer browser/git
  -> local gitlab.internal:8929 / gitlab.internal:2222
  -> local frpc visitor
  -> XTCP direct path to internal GitLab host when possible
  -> STCP fallback through frps when XTCP fails
  -> internal GitLab 127.0.0.1:8929 / 127.0.0.1:2222
```

Public Aliyun only runs `frps`; it must not expose GitLab Web or SSH as public proxy ports.

| Machine | Directory | Command |
| --- | --- | --- |
| Internal GitLab host | `gitlab/` | `cp env.example .env && vim .env && ./install.sh` |
| Aliyun frp host | `frp-server/` | `cp env.example .env && vim .env && ./install.sh` |
| Internal GitLab host | `frp-source/` | `cp env.example .env && vim .env && ./install.sh` |
| Developer machine | `frp-client/` | `cp env.example .env && vim .env && ./install.sh` |

Developer access:

```text
http://gitlab.internal:8929
ssh://git@gitlab.internal:2222/<group>/<repo>.git
```
```

- [ ] **Step 2: Update `doc.md` architecture notes**

Add this section to `doc.md`:

```markdown
## FRP Migration Plan

The frp path is designed for a low-spec public server. XTCP should carry Web and Git SSH traffic directly between the developer machine and the internal GitLab host when NAT traversal succeeds. STCP fallback keeps the service usable when XTCP fails, at the cost of temporarily sending business traffic through frps.

The public server must not publish GitLab Web or GitLab SSH ports. Developers resolve `gitlab.internal` locally to `127.0.0.1`, and their local frpc visitor binds Web on `127.0.0.1:8929` and SSH on `127.0.0.1:2222`.

Rollback remains available by stopping `frp-client.service` and re-enabling the existing Handshake path with `git hs enable`.
```

- [ ] **Step 3: Run documentation checks**

Run:

```bash
grep -R "gitlab.internal" readme.md doc.md frp-client
grep -R "fallbackTo" frp-client/frpc.toml.template
bash scripts/verify.sh
```

Expected: grep commands show the new host and fallback config; verification passes.

- [ ] **Step 4: Commit**

```bash
git add readme.md doc.md
git commit -m "docs: describe frp gitlab access path"
```

## Task 6: Manual Staging Validation

**Files:**
- No required repository changes.
- Optional modify after validation: `readme.md`, `doc.md`, or env examples if real deployment reveals mismatched defaults.

**Interfaces:**
- Consumes: all frp roles.
- Produces: validated migration checklist and go/no-go decision.

- [ ] **Step 1: Deploy frp server on Aliyun**

Run on Aliyun:

```bash
cd frp-server
cp env.example .env
vim .env
./install.sh
./status.sh
```

Expected:

```text
frps.service is active
only frp control/transport ports are publicly listening
no public GitLab Web/SSH port is listening
```

- [ ] **Step 2: Deploy frp source on internal GitLab host**

Run on internal GitLab host:

```bash
cd frp-source
cp env.example .env
vim .env
./install.sh
./status.sh
```

Expected:

```text
frp-source.service is active
http://127.0.0.1:8929/-/health responds
127.0.0.1:2222 accepts TCP connections
```

- [ ] **Step 3: Deploy frp client on one developer machine**

Run on developer machine:

```bash
cd frp-client
cp env.example .env
vim .env
./install.sh
./status.sh
```

Expected:

```text
/etc/hosts contains 127.0.0.1 gitlab.internal
http://gitlab.internal:8929 opens GitLab
ssh -T -p 2222 git@gitlab.internal reaches GitLab SSH
git remote URLs using ssh://git@10.10.0.216:2222/ are rewritten to ssh://git@gitlab.internal:2222/
```

- [ ] **Step 4: Validate server pressure**

Run one clone/pull test from the developer machine while watching Aliyun:

```bash
git clone ssh://git@gitlab.internal:2222/<group>/<repo>.git
```

On Aliyun:

```bash
iftop -i any
journalctl -u frps.service -f
```

Expected:

```text
When XTCP succeeds, Aliyun bandwidth stays low during clone/pull.
When XTCP fails, traffic falls back through frps and bandwidth increases, but Git operation still completes.
```

- [ ] **Step 5: Decide cutover**

If staging passes, update developer onboarding to use `frp-client/`. Keep Handshake installed for one release window as rollback.

- [ ] **Step 6: Commit any validation doc updates**

```bash
git add readme.md doc.md frp-server/env.example frp-source/env.example frp-client/env.example
git commit -m "docs: record frp staging validation"
```

## Self-Review

**Spec coverage:** The plan covers `gitlab.internal`, no company DNS, no public GitLab address, low public-server pressure, XTCP for most traffic, STCP fallback for reliability, GitLab Web and SSH, and rollback to Handshake.

**Placeholder scan:** No `TBD`, `TODO`, or undefined future work remains in the plan.

**Type consistency:** Proxy names match across source and client configs: `gitlab-web-xtcp`, `gitlab-web-stcp`, `gitlab-ssh-xtcp`, `gitlab-ssh-stcp`; visitor fallback names match the client template.
