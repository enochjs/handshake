# Handshake GitLab SSH Tunnel

This repository installs private access paths for an internal GitLab.

Recommended frp path:

```text
developer browser/git
  -> local gitlab.internal:8929 / gitlab.internal:2222
  -> local frpc visitor
  -> XTCP direct path to internal GitLab host when possible
  -> STCP fallback through frps when XTCP fails
  -> internal GitLab 127.0.0.1:8929 / 127.0.0.1:2222
```

Legacy Handshake rollback path:

```text
developer client -> Aliyun handshake server -> internal GitLab source host -> GitLab Docker
```

The frp path is preferred when the public server is low-spec and should avoid carrying GitLab business traffic whenever XTCP hole punching succeeds. Public Aliyun only runs `frps`; it must not expose GitLab Web or SSH as public proxy ports.

The goal is operational simplicity: clone this repository on the relevant machine, enter that machine's role directory, copy `env.example` to `.env`, adjust values, and run `./install.sh`.

## Recommended FRP Install Order

| Machine | Directory | Command |
| --- | --- | --- |
| Internal GitLab host | `gitlab/` | `cp env.example .env && vim .env && ./install.sh` |
| Aliyun frp host | `frp-server/` | `cp env.example .env && vim .env && ./install.sh` |
| Internal GitLab host | `frp-source/` | `cp env.example .env && vim .env && ./install.sh` |
| Developer machine | `frp-client/` | `cp env.example .env && vim .env && ./install.sh` |

Developer access after `frp-client/` setup:

```text
http://gitlab.internal:8929
ssh://git@gitlab.internal:2222/<group>/<repo>.git
```

To migrate an existing developer machine from `handshake-client` to `frp-client`, configure `frp-client/.env` first, then run:

```bash
scripts/migrate-client-to-frp.sh
```

The migration removes the old Handshake Git rewrite, removes the managed SSH include file, uninstalls the `git-hs` Cargo binary when Cargo is available, and then runs `frp-client/install.sh`.

## Legacy Handshake Install Order

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
git hs status
git hs enable
git hs disable
```

### `frp-server/`

Runs `frps` on Aliyun. It only provides frp control, NAT coordination, and STCP fallback; it does not publish GitLab Web or SSH as public ports.

The role is Docker Compose based. `install.sh` renders `generated/frps.toml` and runs `docker compose up -d`; `uninstall.sh` runs `docker compose down --remove-orphans`.

### `frp-source/`

Runs `frpc` on the internal GitLab host. It registers XTCP and STCP proxies for local GitLab Web `127.0.0.1:8929` and SSH `127.0.0.1:2222`.

The role is Docker Compose based and uses host networking so containerized `frpc` can reach the GitLab service on the host loopback address. `install.sh` renders `generated/frpc-source.toml` and runs `docker compose up -d`; `uninstall.sh` runs `docker compose down --remove-orphans`.

### `frp-client/`

Runs `frpc` visitors on each developer machine. It binds Web and SSH on loopback, adds `127.0.0.1 gitlab.internal` to hosts, and configures Git URL rewrite from the direct internal GitLab SSH prefix to `ssh://git@gitlab.internal:2222/`.

Existing Handshake clients should use `scripts/migrate-client-to-frp.sh` instead of running this role directly.

## Verify Locally

```bash
scripts/verify.sh
```

This checks shell syntax, installer dry-run behavior, frp role smoke tests, the Python key-registration server tests, the source tunnel tests, and Rust client tests.

## Full Delete

For frp roles, stop containers without deleting local secrets:

```bash
cd frp-server && ./uninstall.sh
cd frp-source && ./uninstall.sh
```

To remove generated config and `.env` as well:

```bash
cd frp-server && FRP_REMOVE_CONFIG=1 ./uninstall.sh
cd frp-source && FRP_REMOVE_CONFIG=1 ./uninstall.sh
```

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
