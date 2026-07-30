#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/tunnel.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected '$needle' in: $haystack"
}

[[ -x "$SCRIPT" ]] || fail "tunnel.sh is missing or not executable"

help_output="$("$SCRIPT" help)"
assert_contains "$help_output" "Usage:"
assert_contains "$help_output" "tunnel"
assert_contains "$help_output" "check"

tunnel_output="$(DRY_RUN=1 HANDSHAKE_SERVER_HOST=203.0.113.10 HANDSHAKE_SERVER_USER=admin "$SCRIPT" tunnel)"
assert_contains "$tunnel_output" "ssh -N"
assert_contains "$tunnel_output" "-R 127.0.0.1:18080:127.0.0.1:8929"
assert_contains "$tunnel_output" "-R 127.0.0.1:12222:127.0.0.1:2222"
assert_contains "$tunnel_output" "admin@203.0.113.10"
assert_contains "$tunnel_output" "ServerAliveInterval=30"
assert_contains "$tunnel_output" "ExitOnForwardFailure=yes"

check_output="$(DRY_RUN=1 HANDSHAKE_SERVER_HOST=203.0.113.10 HANDSHAKE_SERVER_USER=admin "$SCRIPT" check)"
assert_contains "$check_output" "BatchMode=yes"
assert_contains "$check_output" "ConnectTimeout=10"

set +e
missing_host_output="$(DRY_RUN=1 HANDSHAKE_SERVER_HOST= "$SCRIPT" tunnel 2>&1)"
missing_host_status=$?
set -e

[[ "$missing_host_status" -ne 0 ]] || fail "tunnel should fail without HANDSHAKE_SERVER_HOST"
assert_contains "$missing_host_output" "HANDSHAKE_SERVER_HOST is required"

echo "PASS: tunnel.sh tests"
