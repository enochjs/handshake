#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/gitlab/set-user-password.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected '$needle' in output: $haystack"
}

[[ -x "$SCRIPT" ]] || fail "set-user-password.sh is not executable"

help_output="$("$SCRIPT" --help)"
assert_contains "$help_output" "set password"
assert_contains "$help_output" "--create"
assert_contains "$help_output" "--email"

set_output="$(DRY_RUN=1 "$SCRIPT" root 'Enochjs@pwd123')"
assert_contains "$set_output" "CREATE_USER=0"
assert_contains "$set_output" "TARGET_USERNAME=root"
assert_contains "$set_output" "TARGET_PASSWORD=Enochjs@pwd123"
assert_contains "$set_output" "gitlab-rails runner"

create_output="$(DRY_RUN=1 "$SCRIPT" --create fenghe 'Enochjs@pwd123' --email fenghe@example.com --name 'Feng He')"
assert_contains "$create_output" "CREATE_USER=1"
assert_contains "$create_output" "TARGET_USERNAME=fenghe"
assert_contains "$create_output" "TARGET_EMAIL=fenghe@example.com"
assert_contains "$create_output" "TARGET_NAME=Feng\\ He"

echo "PASS: gitlab user helper tests"
