# One-Click Role Install With Env Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each project role directory independently installable by copying `env.example` to `.env`, editing values, and running one script.

**Architecture:** Use one role directory per machine responsibility: `gitlab/` for the internal GitLab host, `handshake-server/` for the Aliyun jump host and key-registration service, `handshake-source/` for the reverse SSH tunnel from the GitLab host to Aliyun, and `handshake-client/` for developer-machine setup. Each role owns its own `env.example`, installer, status check, and README so users do not need to understand unrelated machines before running the local setup.

**Tech Stack:** Bash, Docker Compose, systemd, Python 3 standard library HTTP server, Rust CLI, OpenSSH, Git global config.

## Global Constraints

- Role choice is directory-based: users enter the relevant directory and run scripts there.
- Runtime configuration lives in `.env`; committed defaults and explanations live in `env.example`.
- Do not commit generated runtime data such as GitLab data, GitLab config, tunnel secrets, token files, or authorized keys.
- Install scripts must be idempotent: re-running should update files/services and print current status instead of failing on already-created users, directories, containers, or systemd units.
- Scripts must support `DRY_RUN=1` for testable command rendering where remote or privileged operations would otherwise run.
- Keep existing defaults unless they conflict with the project goal: GitLab host `10.10.0.216`, GitLab HTTP port `8929`, GitLab SSH port `2222`, Aliyun published GitLab SSH port `12222`, key server port `8787`, jump user `gitproxy`.
- The Aliyun server installer must create and own the `gitproxy` jump user setup; users should not need to create `gitproxy` manually before running `handshake-server/install.sh`.

---

## File Structure

- Create `gitlab/env.example`: GitLab image, host IP, HTTP/SSH ports, backup retention, memory tuning.
- Create `gitlab/install.sh`: Docker/Compose check, `.env` bootstrap, GitLab Compose startup, health/status output.
- Create `gitlab/status.sh`: local container and endpoint status check.
- Modify `gitlab/docker-compose.yml`: read values from `.env` with shell-compatible defaults.
- Modify `gitlab/backup.sh`, `gitlab/restore.sh`, `gitlab/set-user-password.sh`: source `.env` and use configured host/ports in output.
- Create `handshake-server/env.example`: jump user, add-key bind/port, token file, authorized keys path, allowed remote GitLab ports.
- Create `handshake-server/install.sh`: package checks, jump user setup, SSH forwarding policy notes/checks, add-key service installation.
- Create `handshake-server/status.sh`: health check for add-key service and jump user files.
- Create `handshake-server/systemd/handshake-add-key.service`: system service for `server/add_key_server.py`.
- Replace `handshake-server/README.md`: Aliyun jump-host setup, token creation, health check, client registration.
- Archive or remove hsd-specific server docs from the default flow: `handshake-server/init.md` and `handshake-server/docker-compose.yml` should no longer be the server entrypoint.
- Create `handshake-source/env.example`: Aliyun host/user, identity file, local GitLab ports, remote published ports, keepalive settings.
- Create `handshake-source/install.sh`: `.env` bootstrap, SSH reachability check, systemd service installation, tunnel start.
- Create `handshake-source/status.sh`: systemd and remote-port check.
- Modify `handshake-source/hsd.sh`: source `.env` consistently, keep `tunnel` and systemd commands, de-emphasize unrelated hsd API commands or move them out of the primary README.
- Modify `handshake-source/systemd/hsd-tunnel.service`: keep generic user service with environment loaded from role directory.
- Modify `handshake-source/systemd/hsd-tunnel.system.service`: avoid hard-coded `/home/linkmore` by generating the deployed unit from `.env` in `install.sh`.
- Create `handshake-client/env.example`: key server URL, token, public key path, SSH host/user, identity file, remote GitLab SSH port.
- Create `handshake-client/install.sh`: read `.env` and run `cargo run -- setup ...`.
- Modify `handshake-client/README.md`: directory-local client setup instructions.
- Modify root `readme.md`: end-to-end role order and quick-start matrix.
- Modify `.gitignore`: ignore `.env`, token files, generated systemd units, GitLab runtime directories, and local build/runtime artifacts.
- Modify tests: `handshake-source/tests/hsd_test.sh`, add shell smoke tests for role installers, keep Rust and Python unit tests.

---

### Task 1: Normalize Env And Ignore Rules

**Files:**
- Modify: `.gitignore`
- Create: `gitlab/env.example`
- Create: `handshake-server/env.example`
- Create: `handshake-source/env.example`
- Create: `handshake-client/env.example`

**Interfaces:**
- Consumes: Existing hard-coded defaults from `gitlab/docker-compose.yml`, `handshake-source/hsd.sh`, `handshake-client/src/ssh_config.rs`, and `handshake-server/server/add_key_server.py`.
- Produces: Role-level `.env` variable names consumed by later install scripts.

- [ ] **Step 1: Write env file content**

Create `gitlab/env.example`:

```bash
GITLAB_IMAGE=gitlab/gitlab-ce:latest
GITLAB_HOST_IP=10.10.0.216
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2222
GITLAB_CONTAINER=gitlab
GITLAB_BACKUP_KEEP_SECONDS=604800
GITLAB_MEMORY_RESERVATION=24g
```

Create `handshake-server/env.example`:

```bash
HANDSHAKE_SERVER_BIND=127.0.0.1
HANDSHAKE_KEY_SERVER_PORT=8787
HANDSHAKE_JUMP_USER=gitproxy
HANDSHAKE_TOKEN_FILE=/etc/handshake-client/tokens
HANDSHAKE_AUTHORIZED_KEYS=/home/gitproxy/.ssh/authorized_keys
HANDSHAKE_ALLOWED_GITLAB_SSH_HOST=127.0.0.1
HANDSHAKE_ALLOWED_GITLAB_SSH_PORT=12222
HANDSHAKE_AUTHORIZED_KEYS_OPTIONS=restrict,port-forwarding,permitopen="127.0.0.1:12222"
```

Create `handshake-source/env.example`:

```bash
HSD_REMOTE_HOST=106.14.219.191
HSD_REMOTE_USER=root
HSD_REMOTE_DIR=~/handshake
HSD_SSH_IDENTITY_FILE=
HSD_SSH_SERVER_ALIVE_INTERVAL=30
HSD_SSH_SERVER_ALIVE_COUNT_MAX=3
HSD_GITLAB_LOCAL_HTTP_PORT=8929
HSD_GITLAB_LOCAL_SSH_PORT=2222
HSD_GITLAB_REMOTE_HTTP_PORT=18080
HSD_GITLAB_REMOTE_SSH_PORT=12222
HSD_DRY_RUN=0
```

Create `handshake-client/env.example`:

```bash
HANDSHAKE_KEY_SERVER_URL=http://106.14.219.191:8787
HANDSHAKE_INVITE_TOKEN=
HANDSHAKE_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub
HANDSHAKE_SSH_CONFIG_PATH=~/.ssh/config
HANDSHAKE_INCLUDE_PATH=~/.ssh/handshake_config
HANDSHAKE_HOST=106.14.219.191
HANDSHAKE_USER=gitproxy
HANDSHAKE_IDENTITY_FILE=~/.ssh/id_ed25519
HANDSHAKE_GITLAB_REMOTE_SSH_PORT=12222
```

- [ ] **Step 2: Update ignore rules**

Add these lines to `.gitignore`:

```gitignore
.env
**/.env
handshake-server/systemd/generated/
handshake-server/tokens
gitlab/backups
gitlab/config
gitlab/logs
gitlab/data
handshake-server/data
handshake-client/target/
**/__pycache__/
.DS_Store
```

- [ ] **Step 3: Verify env examples are committed and runtime env is ignored**

Run:

```bash
git check-ignore gitlab/.env handshake-server/.env handshake-source/.env handshake-client/.env
git status --short
```

Expected:

```text
gitlab/.env
handshake-server/.env
handshake-source/.env
handshake-client/.env
```

`git status --short` should show the four `env.example` files and `.gitignore` changes, not any `.env` file.

- [ ] **Step 4: Commit**

```bash
git add .gitignore gitlab/env.example handshake-server/env.example handshake-source/env.example handshake-client/env.example
git commit -m "chore: add role env examples"
```

---

### Task 2: Make GitLab Directory One-Click Installable

**Files:**
- Modify: `gitlab/docker-compose.yml`
- Create: `gitlab/install.sh`
- Create: `gitlab/status.sh`
- Modify: `gitlab/backup.sh`
- Modify: `gitlab/restore.sh`
- Modify: `gitlab/set-user-password.sh`

**Interfaces:**
- Consumes: `gitlab/.env` with variables from `gitlab/env.example`.
- Produces: A running GitLab container reachable at `http://${GITLAB_HOST_IP}:${GITLAB_HTTP_PORT}` and SSH port `${GITLAB_SSH_PORT}`.

- [ ] **Step 1: Update Compose to read env variables**

In `gitlab/docker-compose.yml`, replace hard-coded image, container, external URL, SSH port, exposed ports, backup retention, and memory reservation with these variable forms:

```yaml
services:
  gitlab:
    image: ${GITLAB_IMAGE:-gitlab/gitlab-ce:latest}
    container_name: ${GITLAB_CONTAINER:-gitlab}
    restart: always
    hostname: gitlab.local
    privileged: false
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${GITLAB_HOST_IP:-10.10.0.216}:${GITLAB_HTTP_PORT:-8929}'
        nginx['listen_port'] = 80
        nginx['listen_https'] = false
        gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT:-2222}
        gitlab_rails['backup_keep_time'] = ${GITLAB_BACKUP_KEEP_SECONDS:-604800}
        puma['worker_processes'] = 4
        sidekiq['max_concurrency'] = 20
        postgresql['shared_buffers'] = "2GB"
        postgresql['effective_cache_size'] = "8GB"
        prometheus_monitoring['enable'] = true
    ports:
      - "${GITLAB_HTTP_PORT:-8929}:80"
      - "${GITLAB_SSH_PORT:-2222}:22"
    volumes:
      - ./config:/etc/gitlab
      - ./logs:/var/log/gitlab
      - ./data:/var/opt/gitlab
    shm_size: "256m"
    mem_reservation: ${GITLAB_MEMORY_RESERVATION:-24g}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/-/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 300s
```

- [ ] **Step 2: Create installer**

Create `gitlab/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  cp env.example .env
  echo "Created gitlab/.env from env.example"
fi

set -a
source .env
set +a

if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
fi

if ! docker compose version >/dev/null 2>&1; then
  sudo apt-get install -y docker-compose-v2
fi

mkdir -p config logs data backups
docker compose up -d
docker compose ps

echo "GitLab HTTP: http://${GITLAB_HOST_IP}:${GITLAB_HTTP_PORT}"
echo "GitLab SSH:  ssh://git@${GITLAB_HOST_IP}:${GITLAB_SSH_PORT}/<group>/<repo>.git"
echo "Status:      ./status.sh"
```

- [ ] **Step 3: Create status script**

Create `gitlab/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -a
[[ -f .env ]] && source .env
set +a

GITLAB_CONTAINER="${GITLAB_CONTAINER:-gitlab}"
GITLAB_HOST_IP="${GITLAB_HOST_IP:-10.10.0.216}"
GITLAB_HTTP_PORT="${GITLAB_HTTP_PORT:-8929}"
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"

docker compose ps
docker exec "$GITLAB_CONTAINER" gitlab-ctl status
curl -fsS "http://127.0.0.1:${GITLAB_HTTP_PORT}/-/health" || true
echo "Configured HTTP URL: http://${GITLAB_HOST_IP}:${GITLAB_HTTP_PORT}"
echo "Configured SSH port: ${GITLAB_SSH_PORT}"
```

- [ ] **Step 4: Update helper scripts to source `.env`**

At the top of `backup.sh`, `restore.sh`, and `set-user-password.sh`, after `GITLAB_DIR` is set, add:

```bash
if [[ -f "${GITLAB_DIR}/.env" ]]; then
  set -a
  source "${GITLAB_DIR}/.env"
  set +a
fi
```

Use `${GITLAB_HOST_IP:-10.10.0.216}` and `${GITLAB_HTTP_PORT:-8929}` in printed login/recovery URLs.

- [ ] **Step 5: Verify**

Run:

```bash
bash -n gitlab/install.sh gitlab/status.sh gitlab/backup.sh gitlab/restore.sh gitlab/set-user-password.sh
docker compose -f gitlab/docker-compose.yml config >/tmp/handshake-gitlab-compose.out
```

Expected: no syntax errors and `docker compose config` exits 0.

- [ ] **Step 6: Commit**

```bash
git add gitlab/docker-compose.yml gitlab/install.sh gitlab/status.sh gitlab/backup.sh gitlab/restore.sh gitlab/set-user-password.sh
git commit -m "feat: add one-click gitlab role install"
```

---

### Task 3: Rebuild Handshake Server As Aliyun Jump-Host Installer

**Files:**
- Create: `handshake-server/install.sh`
- Create: `handshake-server/status.sh`
- Create: `handshake-server/systemd/handshake-add-key.service`
- Modify: `handshake-server/server/add_key_server.py`
- Replace: `handshake-server/README.md`
- Move or remove from main path: `handshake-server/init.md`, `handshake-server/docker-compose.yml`

**Interfaces:**
- Consumes: `handshake-server/.env`.
- Produces: `handshake-add-key.service` listening on `${HANDSHAKE_SERVER_BIND}:${HANDSHAKE_KEY_SERVER_PORT}` and an Aliyun SSH jump user `${HANDSHAKE_JUMP_USER}` whose authorized keys restrict clients to the GitLab SSH reverse tunnel port.

- [ ] **Step 1: Align add-key server env names**

Keep backward compatibility in `add_key_server.py` by reading the new names first and old names second:

```python
DEFAULT_BIND = "127.0.0.1"
DEFAULT_PORT = 8787
DEFAULT_TOKEN_FILE = "/etc/handshake-client/tokens"
DEFAULT_AUTHORIZED_KEYS = "/home/gitproxy/.ssh/authorized_keys"
DEFAULT_OPTIONS = 'restrict,port-forwarding,permitopen="127.0.0.1:12222"'

def env_value(primary, fallback, default):
    return os.environ.get(primary, os.environ.get(fallback, default))
```

Use:

```python
token_path = pathlib.Path(env_value("HANDSHAKE_TOKEN_FILE", "ADD_KEY_TOKEN_FILE", DEFAULT_TOKEN_FILE))
authorized_keys_path = pathlib.Path(env_value("HANDSHAKE_AUTHORIZED_KEYS", "ADD_KEY_AUTHORIZED_KEYS", DEFAULT_AUTHORIZED_KEYS))
authorized_keys_options = env_value("HANDSHAKE_AUTHORIZED_KEYS_OPTIONS", "ADD_KEY_AUTHORIZED_KEYS_OPTIONS", DEFAULT_OPTIONS)
```

Use `HANDSHAKE_SERVER_BIND` and `HANDSHAKE_KEY_SERVER_PORT` as parser defaults.

- [ ] **Step 2: Create systemd unit template**

Create `handshake-server/systemd/handshake-add-key.service`:

```ini
[Unit]
Description=Handshake SSH public key registration server
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/handshake-server/handshake-server.env
ExecStart=/usr/bin/python3 /opt/handshake/handshake-server/server/add_key_server.py
Restart=always
RestartSec=3
User=root
Group=root

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Create installer with Aliyun `gitproxy` user setup**

Create `handshake-server/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  cp env.example .env
  echo "Created handshake-server/.env from env.example"
fi

set -a
source .env
set +a

HANDSHAKE_JUMP_USER="${HANDSHAKE_JUMP_USER:-gitproxy}"
HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE:-/etc/handshake-client/tokens}"
HANDSHAKE_AUTHORIZED_KEYS="${HANDSHAKE_AUTHORIZED_KEYS:-/home/${HANDSHAKE_JUMP_USER}/.ssh/authorized_keys}"

sudo apt-get update
sudo apt-get install -y python3 openssh-server curl

if ! id "$HANDSHAKE_JUMP_USER" >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash "$HANDSHAKE_JUMP_USER"
fi

sudo passwd -l "$HANDSHAKE_JUMP_USER" >/dev/null 2>&1 || true
sudo install -d -m 700 -o "$HANDSHAKE_JUMP_USER" -g "$HANDSHAKE_JUMP_USER" "/home/${HANDSHAKE_JUMP_USER}/.ssh"
sudo touch "$HANDSHAKE_AUTHORIZED_KEYS"
sudo chown "$HANDSHAKE_JUMP_USER:$HANDSHAKE_JUMP_USER" "$HANDSHAKE_AUTHORIZED_KEYS"
sudo chmod 600 "$HANDSHAKE_AUTHORIZED_KEYS"

sudo install -d -m 755 /opt/handshake
sudo rsync -a --delete "$SCRIPT_DIR/../" /opt/handshake/
sudo install -d -m 755 /etc/handshake-server
sudo install -d -m 700 "$(dirname "$HANDSHAKE_TOKEN_FILE")"
sudo touch "$HANDSHAKE_TOKEN_FILE"
sudo chmod 600 "$HANDSHAKE_TOKEN_FILE"

sudo cp .env /etc/handshake-server/handshake-server.env
sudo cp systemd/handshake-add-key.service /etc/systemd/system/handshake-add-key.service
sudo systemctl daemon-reload
sudo systemctl enable --now handshake-add-key.service

echo "Add invite token:"
echo "  echo '<token>' | sudo tee -a ${HANDSHAKE_TOKEN_FILE}"
echo "Jump user:"
echo "  ${HANDSHAKE_JUMP_USER} has been created on this Aliyun host"
echo "Health:"
echo "  curl -fsS http://${HANDSHAKE_SERVER_BIND:-127.0.0.1}:${HANDSHAKE_KEY_SERVER_PORT:-8787}/healthz"
```

- [ ] **Step 4: Verify SSH daemon settings for jump/reverse forwarding**

In `handshake-server/install.sh`, after package installation, add an explicit check that warns if the Aliyun SSH daemon does not allow the source host's reverse tunnel:

```bash
SSHD_CONFIG=/etc/ssh/sshd_config
if sudo sshd -T | grep -qi '^allowtcpforwarding no'; then
  echo "Error: sshd has AllowTcpForwarding=no. Set AllowTcpForwarding yes in ${SSHD_CONFIG}."
  exit 1
fi
if sudo sshd -T | grep -qi '^gatewayports yes'; then
  echo "GatewayPorts=yes is enabled. Reverse GitLab ports should still bind to 127.0.0.1 in handshake-source/.env."
fi
```

Do not automatically expose GitLab reverse ports on public interfaces. The source tunnel command binds remote ports to `127.0.0.1`, and the client reaches them through `ProxyJump`.

- [ ] **Step 5: Create status script**

Create `handshake-server/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -a
[[ -f .env ]] && source .env
set +a

HANDSHAKE_SERVER_BIND="${HANDSHAKE_SERVER_BIND:-127.0.0.1}"
HANDSHAKE_KEY_SERVER_PORT="${HANDSHAKE_KEY_SERVER_PORT:-8787}"
HANDSHAKE_JUMP_USER="${HANDSHAKE_JUMP_USER:-gitproxy}"
HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE:-/etc/handshake-client/tokens}"
HANDSHAKE_AUTHORIZED_KEYS="${HANDSHAKE_AUTHORIZED_KEYS:-/home/${HANDSHAKE_JUMP_USER}/.ssh/authorized_keys}"

systemctl --no-pager --full status handshake-add-key.service || true
curl -fsS "http://${HANDSHAKE_SERVER_BIND}:${HANDSHAKE_KEY_SERVER_PORT}/healthz"
id "$HANDSHAKE_JUMP_USER"
getent passwd "$HANDSHAKE_JUMP_USER"
sudo test -d "/home/${HANDSHAKE_JUMP_USER}/.ssh"
sudo test -f "$HANDSHAKE_TOKEN_FILE"
sudo test -f "$HANDSHAKE_AUTHORIZED_KEYS"
```

- [ ] **Step 6: Replace README**

Write `handshake-server/README.md` with these sections:

```markdown
# Handshake Server

Aliyun jump-host role for exposing the internal GitLab SSH reverse tunnel to registered developers.

## Install

```bash
cp env.example .env
vim .env
./install.sh
```

The installer creates the Aliyun jump user `gitproxy` by default. Override `HANDSHAKE_JUMP_USER` in `.env` only if the jump user must have another name.

## Add Invite Token

```bash
echo 'invite-token-1' | sudo tee -a /etc/handshake-client/tokens
```

## Check

```bash
./status.sh
curl -fsS http://127.0.0.1:8787/healthz
```

## Client Setup

Give the developer one invite token and the key server URL.
```

- [ ] **Step 7: Verify**

Run:

```bash
python3 handshake-server/server/add_key_server_test.py
bash -n handshake-server/install.sh handshake-server/status.sh
```

Expected: Python tests pass and shell syntax checks pass. The installer source includes `useradd --create-home` for `${HANDSHAKE_JUMP_USER:-gitproxy}`.

- [ ] **Step 8: Commit**

```bash
git add handshake-server
git commit -m "feat: add aliyun handshake server installer"
```

---

### Task 4: Make Source Tunnel Directory One-Click Installable

**Files:**
- Modify: `handshake-source/hsd.sh`
- Create: `handshake-source/install.sh`
- Create: `handshake-source/status.sh`
- Modify: `handshake-source/systemd/hsd-tunnel.service`
- Modify: `handshake-source/systemd/hsd-tunnel.system.service`
- Modify: `handshake-source/tests/hsd_test.sh`

**Interfaces:**
- Consumes: `handshake-source/.env`.
- Produces: A running reverse SSH tunnel from local GitLab ports to Aliyun loopback ports.

- [ ] **Step 1: Keep `hsd.sh tunnel` as the tunnel engine**

Preserve the existing `cmd_tunnel` behavior:

```bash
ssh -N \
  -o "ServerAliveInterval=$HSD_SSH_SERVER_ALIVE_INTERVAL" \
  -o "ServerAliveCountMax=$HSD_SSH_SERVER_ALIVE_COUNT_MAX" \
  -o "ExitOnForwardFailure=yes" \
  -R "127.0.0.1:${HSD_GITLAB_REMOTE_HTTP_PORT}:127.0.0.1:${HSD_GITLAB_LOCAL_HTTP_PORT}" \
  -R "127.0.0.1:${HSD_GITLAB_REMOTE_SSH_PORT}:127.0.0.1:${HSD_GITLAB_LOCAL_SSH_PORT}" \
  "$HSD_REMOTE_USER@$HSD_REMOTE_HOST"
```

Ensure `.env` values are loaded before defaults and explicit process environment values still override `.env`.

- [ ] **Step 2: Create installer**

Create `handshake-source/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  cp env.example .env
  echo "Created handshake-source/.env from env.example"
fi

set -a
source .env
set +a

[[ -n "${HSD_REMOTE_HOST:-}" ]] || { echo "HSD_REMOTE_HOST is required in handshake-source/.env"; exit 1; }

sudo apt-get update
sudo apt-get install -y openssh-client curl systemd

ssh -o BatchMode=yes -o ConnectTimeout=10 "${HSD_REMOTE_USER:-root}@${HSD_REMOTE_HOST}" true

./hsd.sh tunnel-install
./hsd.sh tunnel-start
./status.sh
```

- [ ] **Step 3: Create status script**

Create `handshake-source/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set -a
[[ -f .env ]] && source .env
set +a

if systemctl cat hsd-tunnel.service >/dev/null 2>&1; then
  systemctl --no-pager --full status hsd-tunnel.service || true
else
  systemctl --user --no-pager --full status hsd-tunnel.service || true
fi

echo "Local GitLab HTTP: 127.0.0.1:${HSD_GITLAB_LOCAL_HTTP_PORT:-8929}"
echo "Local GitLab SSH:  127.0.0.1:${HSD_GITLAB_LOCAL_SSH_PORT:-2222}"
echo "Remote HTTP:       127.0.0.1:${HSD_GITLAB_REMOTE_HTTP_PORT:-18080} on ${HSD_REMOTE_HOST:-unset}"
echo "Remote SSH:        127.0.0.1:${HSD_GITLAB_REMOTE_SSH_PORT:-12222} on ${HSD_REMOTE_HOST:-unset}"
```

- [ ] **Step 4: Fix dry-run test port drift**

In `handshake-source/tests/hsd_test.sh`, change the expected HTTP reverse mapping from:

```bash
assert_contains "$tunnel_output" "-R 127.0.0.1:18080:127.0.0.1:8080"
```

to:

```bash
assert_contains "$tunnel_output" "-R 127.0.0.1:18080:127.0.0.1:8929"
```

- [ ] **Step 5: Verify**

Run:

```bash
bash -n handshake-source/hsd.sh handshake-source/install.sh handshake-source/status.sh
handshake-source/tests/hsd_test.sh
```

Expected: syntax checks pass and `PASS: hsd.sh tests`.

- [ ] **Step 6: Commit**

```bash
git add handshake-source
git commit -m "feat: add one-click source tunnel install"
```

---

### Task 5: Add Client Directory Installer Around Rust Setup

**Files:**
- Create: `handshake-client/install.sh`
- Modify: `handshake-client/README.md`
- Optional modify: `handshake-client/src/main.rs` if direct `.env` support inside Rust is preferred later.

**Interfaces:**
- Consumes: `handshake-client/.env`.
- Produces: Registered developer key, managed SSH config include, and enabled Git rewrite to `gitlab-via-handshake`.

- [ ] **Step 1: Create installer**

Create `handshake-client/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  cp env.example .env
  echo "Created handshake-client/.env from env.example"
  echo "Edit HANDSHAKE_INVITE_TOKEN in handshake-client/.env, then rerun ./install.sh"
  exit 1
fi

set -a
source .env
set +a

[[ -n "${HANDSHAKE_INVITE_TOKEN:-}" ]] || { echo "HANDSHAKE_INVITE_TOKEN is required in handshake-client/.env"; exit 1; }

cargo run -- setup \
  --token "$HANDSHAKE_INVITE_TOKEN" \
  --server-url "${HANDSHAKE_KEY_SERVER_URL:-http://106.14.219.191:8787}" \
  --key "${HANDSHAKE_PUBLIC_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}" \
  --ssh-config "${HANDSHAKE_SSH_CONFIG_PATH:-$HOME/.ssh/config}" \
  --include-path "${HANDSHAKE_INCLUDE_PATH:-$HOME/.ssh/handshake_config}" \
  --handshake-host "${HANDSHAKE_HOST:-106.14.219.191}" \
  --handshake-user "${HANDSHAKE_USER:-gitproxy}" \
  --identity-file "${HANDSHAKE_IDENTITY_FILE:-~/.ssh/id_ed25519}" \
  --gitlab-local-port "${HANDSHAKE_GITLAB_REMOTE_SSH_PORT:-12222}"

cargo run -- status
ssh -T gitlab-via-handshake || true
```

- [ ] **Step 2: Update client README**

Add this quick start to `handshake-client/README.md`:

```markdown
## One-Click Install

```bash
cp env.example .env
vim .env
./install.sh
```

Set `HANDSHAKE_INVITE_TOKEN` to the one-time token from the Aliyun jump-host operator.
```

- [ ] **Step 3: Verify**

Run:

```bash
bash -n handshake-client/install.sh
cd handshake-client && cargo test
```

Expected: shell syntax passes and Rust tests pass.

- [ ] **Step 4: Commit**

```bash
git add handshake-client/install.sh handshake-client/README.md
git commit -m "feat: add client env installer"
```

---

### Task 6: Rewrite Root README Around Role-Based Quick Start

**Files:**
- Modify: `readme.md`
- Modify: `gitlab/README.md` if created during implementation
- Modify: `handshake-server/README.md`
- Modify: `handshake-source/README.md` if created during implementation
- Modify: `handshake-client/README.md`

**Interfaces:**
- Consumes: Role installers from Tasks 2-5.
- Produces: A copy-pasteable installation order for the full system.

- [ ] **Step 1: Replace root README with role matrix**

Use this structure:

```markdown
# Handshake GitLab SSH Tunnel

## What This Does

This repository installs a three-hop GitLab access path:

```text
developer client -> Aliyun handshake server -> internal GitLab source host -> GitLab Docker
```

## Install Order

| Machine | Directory | Command |
| --- | --- | --- |
| Internal GitLab host | `gitlab/` | `cp env.example .env && vim .env && ./install.sh` |
| Aliyun jump host | `handshake-server/` | `cp env.example .env && vim .env && ./install.sh` |
| Internal GitLab host | `handshake-source/` | `cp env.example .env && vim .env && ./install.sh` |
| Developer machine | `handshake-client/` | `cp env.example .env && vim .env && ./install.sh` |

## Default Ports

| Purpose | Default |
| --- | --- |
| GitLab HTTP on internal host | `10.10.0.216:8929` |
| GitLab SSH on internal host | `10.10.0.216:2222` |
| GitLab SSH published on Aliyun loopback | `127.0.0.1:12222` |
| Public-key registration server | `127.0.0.1:8787` or reverse-proxied public endpoint |

## Daily Use

```bash
cd handshake-client
cargo run -- status
cargo run -- enable
cargo run -- disable
```
```

- [ ] **Step 2: Verify docs mention real entrypoints**

Run:

```bash
rg -n "init.md|hsd 全节点|12037|12038|12039|8080|TODO|TBD" readme.md gitlab handshake-server handshake-source handshake-client -g '*.md'
```

Expected: no default-flow docs point users to hsd node setup, no stale `8080`, and no placeholder wording.

- [ ] **Step 3: Commit**

```bash
git add readme.md gitlab handshake-server handshake-source handshake-client
git commit -m "docs: document role-based one-click install"
```

---

### Task 7: End-To-End Verification

**Files:**
- Modify: `handshake-source/tests/hsd_test.sh`
- Create: `scripts/verify.sh`

**Interfaces:**
- Consumes: all role scripts.
- Produces: one local verification command for syntax, unit tests, and dry-run behavior.

- [ ] **Step 1: Create verification script**

Create `scripts/verify.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n gitlab/install.sh gitlab/status.sh gitlab/backup.sh gitlab/restore.sh gitlab/set-user-password.sh
bash -n handshake-server/install.sh handshake-server/status.sh
bash -n handshake-source/hsd.sh handshake-source/install.sh handshake-source/status.sh
bash -n handshake-client/install.sh

python3 handshake-server/server/add_key_server_test.py
handshake-source/tests/hsd_test.sh

(
  cd handshake-client
  cargo test
)

echo "PASS: repository verification"
```

- [ ] **Step 2: Run verification**

Run:

```bash
scripts/verify.sh
```

Expected:

```text
PASS: hsd.sh tests
PASS: repository verification
```

Rust test output should report all tests passed.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify.sh handshake-source/tests/hsd_test.sh
git commit -m "test: add one-click installer verification"
```

---

## Self-Review

- Spec coverage: The plan covers role-based entrypoints, env extraction, server/source/client/GitLab installers, README rewrite, and local verification.
- Placeholder scan: No `TBD`, `TODO`, or unspecified implementation steps remain.
- Type consistency: Env variable names introduced in Task 1 are reused by the role installers and docs in later tasks.
- Scope check: This is one cohesive installation-experience refactor. Each task is independently reviewable and leaves a working slice.
