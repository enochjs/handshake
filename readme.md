# Handshake GitLab SSH Tunnel

This repository installs a clean three-hop access path for an internal GitLab:

```text
developer client -> Aliyun handshake server -> internal GitLab source host -> GitLab Docker
```

The goal is operational simplicity: clone this repository on the relevant machine, enter that machine's role directory, copy `env.example` to `.env`, adjust values, and run `./install.sh`.

## Install Order

| Machine | Directory | Command |
| --- | --- | --- |
| Internal GitLab host | `gitlab/` | `cp env.example .env && vim .env && ./install.sh` |
| Aliyun jump host | `handshake-server/` | `cp env.example .env && vim .env && ./install.sh` |
| Internal GitLab host | `handshake-source/` | `cp env.example .env && vim .env && ./install.sh` |
| Developer machine | `handshake-client/` | `cp env.example .env && vim .env && ./install.sh` |

## Role Responsibilities

### `gitlab/`

Runs GitLab CE with Docker Compose on the internal GitLab host.

Defaults:

- HTTP: `10.10.0.216:8929`
- SSH: `10.10.0.216:2222`

### `handshake-server/`

Runs on Aliyun. It creates the `gitproxy` jump user, starts the SSH public-key registration service, and stores invited developer keys in `/home/gitproxy/.ssh/authorized_keys`.

Defaults:

- key registration service: `127.0.0.1:8787`
- reverse GitLab SSH endpoint on Aliyun loopback: `127.0.0.1:12222`

### `handshake-source/`

Runs on the internal GitLab host. It creates a reverse SSH tunnel to Aliyun:

```text
local 127.0.0.1:8929 -> Aliyun 127.0.0.1:18080
local 127.0.0.1:2222 -> Aliyun 127.0.0.1:12222
```

### `handshake-client/`

Runs on each developer machine. It registers the developer's SSH public key, writes a managed SSH config include, and enables Git URL rewrite so existing GitLab SSH URLs can route through the handshake path.

Daily commands:

```bash
cd handshake-client
cargo run -- status
cargo run -- enable
cargo run -- disable
```

## Verify Locally

```bash
scripts/verify.sh
```

This checks shell syntax, installer dry-run behavior, the Python key-registration server tests, the source tunnel tests, and Rust client tests.

## Full Delete

Use `scripts/destroy.sh` only when you want to remove a role completely. It deletes services, runtime `.env` files, generated data, and for the Aliyun server role it also removes the `gitproxy` user.

Dry-run first:

```bash
ROLE=server DRY_RUN=1 DESTROY_CONFIRM=delete-handshake ./scripts/destroy.sh
```

Run the deletion:

```bash
ROLE=server DESTROY_CONFIRM=delete-handshake ./scripts/destroy.sh
```

Supported roles:

- `gitlab`: removes the GitLab container, volumes, `gitlab/config`, `gitlab/logs`, `gitlab/data`, `gitlab/backups`, and `gitlab/.env`
- `server`: removes `handshake-add-key.service`, `/etc/handshake-server`, `/opt/handshake`, token files, local `.env`, and the `gitproxy` user
- `source`: removes `handshake-source-tunnel.service` and local `.env`
- `client`: disables Git rewrite and removes the managed SSH include plus local `.env`
- `all`: runs `client`, `source`, `server`, then `gitlab`
