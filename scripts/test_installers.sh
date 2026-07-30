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

assert_contains handshake-server/install.sh "useradd --create-home"
assert_contains handshake-server/install.sh "HANDSHAKE_JUMP_USER"
assert_contains handshake-server/env.example "HANDSHAKE_JUMP_USER=gitproxy"
assert_contains handshake-source/tunnel.sh "127.0.0.1:\${HANDSHAKE_REMOTE_GITLAB_SSH_PORT}:127.0.0.1:\${GITLAB_LOCAL_SSH_PORT}"
assert_contains handshake-client/install.sh "cargo run -- setup"

server_dry_run="$(DRY_RUN=1 bash handshake-server/install.sh)"
[[ "$server_dry_run" == *"useradd --create-home --shell /bin/bash gitproxy"* ]] || fail "server dry-run did not create gitproxy"
[[ "$server_dry_run" == *"systemctl enable --now handshake-add-key.service"* ]] || fail "server dry-run did not enable add-key service"

source_dry_run="$(DRY_RUN=1 bash handshake-source/tunnel.sh tunnel)"
[[ "$source_dry_run" == *"-R 127.0.0.1:12222:127.0.0.1:2222"* ]] || fail "source tunnel dry-run missing SSH reverse forward"
[[ "$source_dry_run" == *"-R 127.0.0.1:18080:127.0.0.1:8929"* ]] || fail "source tunnel dry-run missing HTTP reverse forward"

client_dry_run="$(DRY_RUN=1 HANDSHAKE_INVITE_TOKEN=test-token bash handshake-client/install.sh)"
[[ "$client_dry_run" == *"cargo run -- setup"* ]] || fail "client dry-run missing cargo setup"
[[ "$client_dry_run" == *"--handshake-user gitproxy"* ]] || fail "client dry-run missing gitproxy user"

echo "PASS: installer smoke tests"
