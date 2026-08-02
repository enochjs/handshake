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

assert_contains_text() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected '$needle' in output"
}

assert_not_contains_text() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "did not expect '$needle' in output"
}

assert_file frp-server/env.example
assert_file frp-server/docker-compose.yml
assert_file frp-server/frps.toml.template
assert_executable frp-server/install.sh
assert_executable frp-server/uninstall.sh
assert_executable frp-server/status.sh

server_dry_run="$(DRY_RUN=1 FRP_AUTH_TOKEN=test-token bash frp-server/install.sh)"
assert_contains_text "$server_dry_run" "frps.toml"
assert_contains_text "$server_dry_run" "fatedier/frps:v0.68.0"
assert_contains_text "$server_dry_run" "bindPort = 7000"
assert_contains_text "$server_dry_run" "auth.method = \"token\""
assert_contains_text "$server_dry_run" "docker compose up -d"
assert_not_contains_text "$server_dry_run" "gitlab.internal"

server_uninstall_dry_run="$(DRY_RUN=1 bash frp-server/uninstall.sh)"
assert_contains_text "$server_uninstall_dry_run" "docker compose down --remove-orphans"

assert_file frp-source/env.example
assert_file frp-source/docker-compose.yml
assert_file frp-source/frpc.toml.template
assert_executable frp-source/install.sh
assert_executable frp-source/uninstall.sh
assert_executable frp-source/status.sh

source_dry_run="$(
  DRY_RUN=1 \
  FRP_SERVER_ADDR=frps.example.com \
  FRP_AUTH_TOKEN=test-token \
  FRP_SECRET_KEY=test-secret \
  bash frp-source/install.sh
)"
assert_contains_text "$source_dry_run" "serverAddr = \"frps.example.com\""
assert_contains_text "$source_dry_run" "fatedier/frpc:v0.68.0"
assert_contains_text "$source_dry_run" "name = \"gitlab-web-xtcp\""
assert_contains_text "$source_dry_run" "type = \"xtcp\""
assert_contains_text "$source_dry_run" "name = \"gitlab-web-stcp\""
assert_contains_text "$source_dry_run" "localPort = 8929"
assert_contains_text "$source_dry_run" "localPort = 2222"
assert_contains_text "$source_dry_run" "docker compose up -d"

source_uninstall_dry_run="$(DRY_RUN=1 bash frp-source/uninstall.sh)"
assert_contains_text "$source_uninstall_dry_run" "docker compose down --remove-orphans"

assert_file frp-client/env.example
assert_file frp-client/frpc.toml.template
assert_executable frp-client/install.sh
assert_executable frp-client/status.sh
assert_executable scripts/migrate-client-to-frp.sh

client_dry_run="$(
  DRY_RUN=1 \
  FRP_SERVER_ADDR=frps.example.com \
  FRP_AUTH_TOKEN=test-token \
  FRP_SECRET_KEY=test-secret \
  FRP_SKIP_BINARY_INSTALL=1 \
  FRP_SERVICE_MANAGER=systemd \
  bash frp-client/install.sh
)"
assert_contains_text "$client_dry_run" "serverAddr = \"frps.example.com\""
assert_contains_text "$client_dry_run" "bindAddr = \"127.0.0.1\""
assert_contains_text "$client_dry_run" "bindPort = 8929"
assert_contains_text "$client_dry_run" "bindPort = 2222"
assert_contains_text "$client_dry_run" "fallbackTo = \"gitlab-web-stcp-visitor\""
assert_contains_text "$client_dry_run" "fallbackTo = \"gitlab-ssh-stcp-visitor\""
assert_contains_text "$client_dry_run" "127.0.0.1 gitlab.internal"
assert_contains_text "$client_dry_run" "git config --global url.ssh://git@gitlab.internal:2222/.insteadOf ssh://git@10.10.0.216:2222/"
assert_contains_text "$client_dry_run" "systemctl enable --now frp-client.service"

migrate_client_dry_run="$(
  DRY_RUN=1 \
  FRP_SERVER_ADDR=frps.example.com \
  FRP_AUTH_TOKEN=test-token \
  FRP_SECRET_KEY=test-secret \
  FRP_SKIP_BINARY_INSTALL=1 \
  FRP_SERVICE_MANAGER=systemd \
  HANDSHAKE_INCLUDE_PATH=/tmp/handshake_config \
  HANDSHAKE_SSH_CONFIG_PATH=/tmp/ssh_config \
  bash scripts/migrate-client-to-frp.sh
)"
assert_contains_text "$migrate_client_dry_run" "git config --global --unset-all url.ssh://git@gitlab-via-handshake/.insteadOf ssh://git@10.10.0.216:2222/"
assert_contains_text "$migrate_client_dry_run" "git config --global --unset-all url.ssh://git@10.10.0.216:2222/.insteadOf ssh://git@gitlab-via-handshake/"
assert_contains_text "$migrate_client_dry_run" "Remove Include /tmp/handshake_config from /tmp/ssh_config"
assert_contains_text "$migrate_client_dry_run" "rm -f /tmp/handshake_config"
assert_contains_text "$migrate_client_dry_run" "cargo uninstall handshake-client"
assert_contains_text "$migrate_client_dry_run" "bash install.sh"
assert_contains_text "$migrate_client_dry_run" "http://gitlab.internal:8929"

echo "PASS: frp installer smoke tests"
