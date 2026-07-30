# Handshake Source

Internal GitLab host role. This machine opens a reverse SSH tunnel to the Aliyun handshake server so the jump host can reach local GitLab without exposing GitLab directly to the public internet.

## Install

```bash
cp env.example .env
vim .env
./install.sh
```

## Check

```bash
./status.sh
DRY_RUN=1 ./tunnel.sh tunnel
```

Default tunnel mapping:

```text
local 127.0.0.1:8929 -> Aliyun 127.0.0.1:18080
local 127.0.0.1:2222 -> Aliyun 127.0.0.1:12222
```
