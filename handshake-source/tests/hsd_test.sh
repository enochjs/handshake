#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/hsd.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected to find:\n%s\n\nIn output:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

[[ -x "$SCRIPT" ]] || fail "hsd.sh is missing or not executable"

help_output="$("$SCRIPT" help)"
assert_contains "$help_output" "Usage:"
assert_contains "$help_output" "tunnel"
assert_contains "$help_output" "api-tunnel"
assert_contains "$help_output" "tunnel-install"
assert_contains "$help_output" "tunnel-enable-boot"
assert_contains "$help_output" "sync"
assert_contains "$help_output" "wallet-primary"
assert_contains "$help_output" "name-rpc"
assert_contains "$help_output" "remote-restart"

tunnel_output="$(HSD_REMOTE_HOST=203.0.113.10 HSD_REMOTE_USER=admin HSD_SSH_IDENTITY_FILE= HSD_DRY_RUN=1 "$SCRIPT" tunnel)"
assert_contains "$tunnel_output" "ssh -N"
assert_contains "$tunnel_output" "-R 127.0.0.1:18080:127.0.0.1:8080"
assert_contains "$tunnel_output" "-R 127.0.0.1:12222:127.0.0.1:2222"
assert_contains "$tunnel_output" "admin@203.0.113.10"
assert_contains "$tunnel_output" "ServerAliveInterval=30"
assert_contains "$tunnel_output" "ExitOnForwardFailure=yes"

api_tunnel_output="$(HSD_REMOTE_HOST=203.0.113.10 HSD_REMOTE_USER=admin HSD_SSH_IDENTITY_FILE= HSD_DRY_RUN=1 "$SCRIPT" api-tunnel)"
assert_contains "$api_tunnel_output" "-L 12037:127.0.0.1:12037"
assert_contains "$api_tunnel_output" "admin@203.0.113.10"

tunnel_install_output="$(HSD_DRY_RUN=1 "$SCRIPT" tunnel-install)"
assert_contains "$tunnel_install_output" "systemctl --user enable"
assert_contains "$tunnel_install_output" "hsd-tunnel.service"

tunnel_boot_output="$(HSD_DRY_RUN=1 "$SCRIPT" tunnel-enable-boot)"
assert_contains "$tunnel_boot_output" "systemctl enable --now"
assert_contains "$tunnel_boot_output" "/etc/systemd/system/hsd-tunnel.service"

name_output="$(HSD_DRY_RUN=1 HSD_API_KEY=secret "$SCRIPT" name handshake)"
assert_contains "$name_output" "curl"
assert_contains "$name_output" "http://127.0.0.1:12037/name/handshake"
assert_contains "$name_output" "x:secret"

wallet_primary_output="$(HSD_DRY_RUN=1 HSD_API_KEY=secret "$SCRIPT" wallet-primary)"
assert_contains "$wallet_primary_output" "curl"
assert_contains "$wallet_primary_output" "http://127.0.0.1:12039/wallet/primary/"

sync_output="$(HSD_DRY_RUN=1 HSD_API_KEY=secret "$SCRIPT" sync)"
assert_contains "$sync_output" "curl"
assert_contains "$sync_output" "python3"

name_rpc_output="$(HSD_DRY_RUN=1 HSD_API_KEY=secret "$SCRIPT" name-rpc handshake)"
assert_contains "$name_rpc_output" "getnameinfo"
assert_contains "$name_rpc_output" "handshake"

set +e
missing_host_output="$(HSD_REMOTE_HOST= HSD_DRY_RUN=1 "$SCRIPT" remote-ps 2>&1)"
missing_host_status=$?
set -e

[[ "$missing_host_status" -ne 0 ]] || fail "remote-ps should fail without HSD_REMOTE_HOST"
assert_contains "$missing_host_output" "HSD_REMOTE_HOST is required"

printf 'PASS: hsd.sh tests\n'
