# GitLab Role

Internal GitLab host role. This directory deploys GitLab CE with Docker Compose and keeps configuration in `.env`.

## Install

```bash
cp env.example .env
vim .env
./install.sh
```

## Check

```bash
./status.sh
```

## Helpers

```bash
./set-user-password.sh <username> [password]
./backup.sh
./restore.sh
```

Default access:

```text
HTTP: http://10.10.0.216:8929
SSH:  ssh://git@10.10.0.216:2222/<group>/<repo>.git
```
