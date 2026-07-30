# Handshake Client

Small Rust CLI for switching Git command-line access between direct 216 GitLab SSH and the Aliyun handshake path.

## One-Click Install

```bash
cp env.example .env
vim .env
./install.sh
```

Set `HANDSHAKE_INVITE_TOKEN` to the one-time token from the Aliyun handshake server operator.

The installer also installs the global command `git-hs`, which Git exposes as `git hs`.
By default, key registration goes through a temporary SSH tunnel from local `127.0.0.1:18787` to the handshake server's `127.0.0.1:8787`, so the registration port does not need to be exposed publicly.

## First-Time Setup

Ask the Aliyun jump-host operator for an invite token, then run `./install.sh`. To rerun setup after the command is installed:

```bash
git hs setup --token <invite-token>
```

By default, setup:

1. Reads `~/.ssh/id_ed25519.pub`.
2. Registers that public key with `http://106.14.219.191:8787/keys`.
3. Writes `~/.ssh/handshake_config`.
4. Ensures `~/.ssh/config` contains `Include ~/.ssh/handshake_config`.
5. Enables handshake Git rewrite mode.

Useful overrides:

```bash
git hs setup \
  --token <invite-token> \
  --server-url http://106.14.219.191:8787 \
  --key ~/.ssh/id_ed25519.pub \
  --handshake-user gitproxy
```

`HANDSHAKE_KEY_SERVER_URL` can also override the key-registration URL. Leave `HANDSHAKE_KEY_SERVER_TUNNEL=1` enabled when the URL points at `127.0.0.1:18787`; set it to `0` only if the key-registration service is directly reachable.

## Prerequisites

After setup, SSH config includes:

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

## Run

```bash
git hs status
git hs enable
git hs disable
```

## Add-Key Server

Run this on the Aliyun jump host under an account that can write the target jump user's `authorized_keys`:

```bash
python3 server/add_key_server.py --bind 127.0.0.1 --port 8787
```

Configuration is environment-based:

```bash
ADD_KEY_TOKEN_FILE=/etc/handshake-client/tokens
ADD_KEY_AUTHORIZED_KEYS=/home/gitproxy/.ssh/authorized_keys
ADD_KEY_AUTHORIZED_KEYS_OPTIONS='restrict,port-forwarding,permitopen="127.0.0.1:12222"'
```

Token file format is one invite token per line:

```text
invite-token-1
invite-token-2
```

Each successful registration consumes one token. The server rejects malformed public keys and avoids duplicate key insertion.

## Modes

Handshake mode writes:

```bash
git config --global url.ssh://git@gitlab-via-handshake/.insteadOf ssh://git@10.10.0.216:2222/
```

Direct mode writes:

```bash
git config --global url.ssh://git@10.10.0.216:2222/.insteadOf ssh://git@gitlab-via-handshake/
```

## Manual Rollback

Remove both client-owned rewrite rules:

```bash
git config --global --unset-all url.ssh://git@gitlab-via-handshake/.insteadOf ssh://git@10.10.0.216:2222/
git config --global --unset-all url.ssh://git@10.10.0.216:2222/.insteadOf ssh://git@gitlab-via-handshake/
```

## Verify

```bash
cargo test
cargo build
python3 server/add_key_server_test.py
```
