# Handshake Server

Aliyun jump-host role. This machine receives the reverse SSH tunnel from the internal GitLab host and accepts developer SSH keys through a small token-protected registration service.

## Install

```bash
cp env.example .env
vim .env
./install.sh
```

The installer creates the Aliyun jump user `gitproxy` by default, locks password login for that user, initializes `/home/gitproxy/.ssh/authorized_keys`, and starts `handshake-add-key.service`.

## Source Tunnel Key

The internal GitLab source host also needs to log in to Aliyun as `gitproxy` to create the reverse SSH tunnel.

For one source host, put its public key in `.env`:

```bash
HANDSHAKE_SOURCE_PUBLIC_KEY='ssh-ed25519 AAAA... source-host'
```

For multiple source hosts, put one public key per line in a file:

```text
ssh-ed25519 AAAA... source-one
ssh-ed25519 BBBB... source-two
```

Then point `.env` at that file:

```bash
HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE=/etc/handshake-server/source-public-keys
```

`install.sh` writes these keys into `/home/gitproxy/.ssh/authorized_keys` with `permitlisten` for `127.0.0.1:12222` and `127.0.0.1:18080`.

## Add Invite Token

```bash
./create-token.sh
```

The command prints the new token. Give that value to one developer. Each successful client setup consumes one token.

To create a specific token manually:

```bash
HANDSHAKE_NEW_TOKEN='invite-token-1' ./create-token.sh
```

## Check

```bash
./status.sh
curl -fsS http://127.0.0.1:8787/healthz
```

## Client Handoff

Give the developer:

- one invite token
- the key server URL, for example `http://106.14.219.191:8787`
- the jump host address, for example `106.14.219.191`

The reverse GitLab SSH port stays bound on Aliyun loopback at `127.0.0.1:12222`; developers reach it through `ProxyJump`, not by exposing GitLab SSH publicly.
