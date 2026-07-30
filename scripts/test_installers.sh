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

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    fail "expected '$needle' in $file"
  fi
}

assert_file gitlab/env.example
assert_file handshake-server/env.example
assert_file handshake-source/env.example
assert_file handshake-client/env.example

assert_executable gitlab/install.sh
assert_executable gitlab/status.sh
assert_executable handshake-server/install.sh
assert_executable handshake-server/status.sh
assert_executable handshake-source/install.sh
assert_executable handshake-source/status.sh
assert_executable handshake-source/tunnel.sh
assert_executable handshake-client/install.sh
assert_executable scripts/destroy.sh

assert_contains handshake-server/install.sh "useradd --create-home"
assert_contains handshake-server/install.sh "HANDSHAKE_JUMP_USER"
assert_contains handshake-server/env.example "HANDSHAKE_JUMP_USER=gitproxy"
assert_contains handshake-server/env.example "HANDSHAKE_SOURCE_PUBLIC_KEY="
assert_contains handshake-server/env.example "HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE="
assert_contains handshake-server/env.example "permitlisten=\"127.0.0.1:12222\""
assert_contains handshake-source/tunnel.sh "127.0.0.1:\${HANDSHAKE_REMOTE_GITLAB_SSH_PORT}:127.0.0.1:\${GITLAB_LOCAL_SSH_PORT}"
assert_contains handshake-client/install.sh "cargo run -- setup"

server_dry_run="$(DRY_RUN=1 bash handshake-server/install.sh)"
[[ "$server_dry_run" == *"useradd --create-home --shell /bin/bash gitproxy"* ]] || fail "server dry-run did not create gitproxy"
[[ "$server_dry_run" == *"systemctl enable --now handshake-add-key.service"* ]] || fail "server dry-run did not enable add-key service"
[[ "$server_dry_run" == *"Source tunnel key: not configured"* ]] || fail "server dry-run missing source key guidance"

server_source_key_dry_run="$(DRY_RUN=1 HANDSHAKE_SOURCE_PUBLIC_KEY='ssh-ed25519 AAAAsource source-host' bash handshake-server/install.sh)"
[[ "$server_source_key_dry_run" == *"permitlisten=\"127.0.0.1:12222\""* ]] || fail "server source key dry-run missing SSH permitlisten"
[[ "$server_source_key_dry_run" == *"permitlisten=\"127.0.0.1:18080\""* ]] || fail "server source key dry-run missing HTTP permitlisten"
[[ "$server_source_key_dry_run" == *"ssh-ed25519 AAAAsource source-tunnel"* ]] || fail "server source key dry-run missing normalized source key"

tmp_source_keys="$(mktemp)"
trap 'rm -f "$tmp_source_keys"' EXIT
printf '%s\n%s\n' \
  'ssh-ed25519 AAAAone source-one' \
  'ssh-ed25519 AAAAtwo source-two' >"$tmp_source_keys"
server_multi_key_dry_run="$(DRY_RUN=1 HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE="$tmp_source_keys" bash handshake-server/install.sh)"
[[ "$server_multi_key_dry_run" == *"ssh-ed25519 AAAAone source-tunnel"* ]] || fail "server multi-key dry-run missing first source key"
[[ "$server_multi_key_dry_run" == *"ssh-ed25519 AAAAtwo source-tunnel"* ]] || fail "server multi-key dry-run missing second source key"

source_dry_run="$(DRY_RUN=1 bash handshake-source/tunnel.sh tunnel)"
[[ "$source_dry_run" == *"-R 127.0.0.1:12222:127.0.0.1:2222"* ]] || fail "source tunnel dry-run missing SSH reverse forward"
[[ "$source_dry_run" == *"-R 127.0.0.1:18080:127.0.0.1:8929"* ]] || fail "source tunnel dry-run missing HTTP reverse forward"

client_dry_run="$(DRY_RUN=1 HANDSHAKE_INVITE_TOKEN=test-token bash handshake-client/install.sh)"
[[ "$client_dry_run" == *"cargo run -- setup"* ]] || fail "client dry-run missing cargo setup"
[[ "$client_dry_run" == *"--handshake-user gitproxy"* ]] || fail "client dry-run missing gitproxy user"

set +e
destroy_without_confirm="$(ROLE=client DRY_RUN=1 bash scripts/destroy.sh 2>&1)"
destroy_without_confirm_status=$?
set -e
[[ "$destroy_without_confirm_status" -ne 0 ]] || fail "destroy should require DESTROY_CONFIRM"
[[ "$destroy_without_confirm" == *"DESTROY_CONFIRM=delete-handshake"* ]] || fail "destroy missing confirmation guidance"

destroy_dry_run="$(ROLE=all DRY_RUN=1 DESTROY_CONFIRM=delete-handshake bash scripts/destroy.sh)"
[[ "$destroy_dry_run" == *"docker compose -f gitlab/docker-compose.yml down --volumes --remove-orphans"* ]] || fail "destroy dry-run missing GitLab compose removal"
[[ "$destroy_dry_run" == *"rm -rf gitlab/config gitlab/logs gitlab/data gitlab/backups gitlab/.env"* ]] || fail "destroy dry-run missing GitLab files"
[[ "$destroy_dry_run" == *"systemctl disable --now handshake-add-key.service"* ]] || fail "destroy dry-run missing server service removal"
[[ "$destroy_dry_run" == *"userdel -r gitproxy"* ]] || fail "destroy dry-run missing gitproxy deletion"
[[ "$destroy_dry_run" == *"systemctl disable --now handshake-source-tunnel.service"* ]] || fail "destroy dry-run missing source tunnel service removal"
[[ "$destroy_dry_run" == *"cargo run -- disable"* ]] || fail "destroy dry-run missing client rewrite disable"
[[ "$destroy_dry_run" == *"rm -f /root/.ssh/handshake_config"* || "$destroy_dry_run" == *"rm -f $HOME/.ssh/handshake_config"* ]] || fail "destroy dry-run missing client SSH include removal"

echo "PASS: installer smoke tests"
