# Handshake Server

Aliyun jump-host role. This machine receives the reverse SSH tunnel from the internal GitLab host and accepts developer SSH keys through a small token-protected registration service.

## Install

```bash
cp env.example .env
vim .env
./install.sh
```

The installer creates the Aliyun jump user `gitproxy` by default, locks password login for that user, initializes `/home/gitproxy/.ssh/authorized_keys`, and starts `handshake-add-key.service`.

## Add Invite Token

```bash
echo 'invite-token-1' | sudo tee -a /etc/handshake-client/tokens
```

Each successful client setup consumes one token.

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
