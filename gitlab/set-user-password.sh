#!/usr/bin/env bash
# Set a GitLab user's password, or create the user first with --create.

set -euo pipefail

GITLAB_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "${GITLAB_DIR}/.env" ]]; then
  set -a
  source "${GITLAB_DIR}/.env"
  set +a
fi

CONTAINER="${GITLAB_CONTAINER:-gitlab}"
GITLAB_HOST_IP="${GITLAB_HOST_IP:-10.10.0.216}"
GITLAB_HTTP_PORT="${GITLAB_HTTP_PORT:-8929}"
DRY_RUN="${DRY_RUN:-0}"

CREATE_USER=0
EMAIL=""
NAME=""
USERNAME=""
PASSWORD="12345678"

usage() {
  cat <<'EOF'
Usage:
  ./set-user-password.sh <username-or-email> [password]
  ./set-user-password.sh --create <username> [password] [--email email] [--name name]

Examples:
  ./set-user-password.sh root 'Enochjs@pwd123'
  ./set-user-password.sh --create fenghe 'Enochjs@pwd123' --email fenghe@example.com --name 'Feng He'

Modes:
  set password  Update an existing user's password.
  --create      Create the user if it does not exist, then set the password.
EOF
}

print_cmd() {
  local first=1
  local arg
  for arg in "$@"; do
    [[ "$first" -eq 1 ]] || printf ' '
    printf '%q' "$arg"
    first=0
  done
  printf '\n'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --create)
        CREATE_USER=1
        shift
        ;;
      --email)
        [[ $# -ge 2 ]] || { echo "错误: --email 需要值" >&2; exit 1; }
        EMAIL="$2"
        shift 2
        ;;
      --name)
        [[ $# -ge 2 ]] || { echo "错误: --name 需要值" >&2; exit 1; }
        NAME="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --*)
        echo "错误: 未知参数 $1" >&2
        usage >&2
        exit 1
        ;;
      *)
        if [[ -z "$USERNAME" ]]; then
          USERNAME="$1"
        elif [[ "$PASSWORD" == "12345678" ]]; then
          PASSWORD="$1"
        else
          echo "错误: 多余参数 $1" >&2
          usage >&2
          exit 1
        fi
        shift
        ;;
    esac
  done
}

parse_args "$@"

if [[ -z "$USERNAME" ]]; then
  usage >&2
  exit 1
fi

if [[ -z "$EMAIL" ]]; then
  EMAIL="${USERNAME}@local.handshake"
fi
if [[ -z "$NAME" ]]; then
  NAME="$USERNAME"
fi

RAILS_SCRIPT='
username = ENV.fetch("TARGET_USERNAME")
password = ENV.fetch("TARGET_PASSWORD")
email = ENV.fetch("TARGET_EMAIL")
name = ENV.fetch("TARGET_NAME")
create_user = ENV.fetch("CREATE_USER") == "1"

user = User.find_by_username(username) || User.find_by_email(username)

if user.nil?
  unless create_user
    puts "NOT_FOUND"
    exit
  end

  user = User.new(
    username: username,
    email: email,
    name: name,
    password: password,
    password_confirmation: password,
    password_automatically_set: false
  )
  user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
  action = "CREATED"
else
  user.password = user.password_confirmation = password
  user.password_automatically_set = false
  action = "UPDATED"
end

if user.save(validate: false)
  puts "#{action} username=#{user.username} email=#{user.email}"
else
  puts "SAVE_FAILED #{user.errors.full_messages.join("; ")}"
end
'

cmd=(
  docker exec
  -e "CREATE_USER=${CREATE_USER}"
  -e "TARGET_USERNAME=${USERNAME}"
  -e "TARGET_PASSWORD=${PASSWORD}"
  -e "TARGET_EMAIL=${EMAIL}"
  -e "TARGET_NAME=${NAME}"
  "$CONTAINER"
  gitlab-rails runner
  "$RAILS_SCRIPT"
)

if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  print_cmd "${cmd[@]}"
  exit 0
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "错误: 容器 '$CONTAINER' 未在运行"
  exit 1
fi

if [[ "$CREATE_USER" == "1" ]]; then
  echo "正在创建或更新 GitLab 用户 '$USERNAME'..."
else
  echo "正在设置 GitLab 用户 '$USERNAME' 的密码..."
fi

RESULT="$("${cmd[@]}")"

case "$RESULT" in
  NOT_FOUND)
    echo "错误: 找不到用户 '$USERNAME'。如需新增用户，请使用 --create。"
    exit 1
    ;;
  SAVE_FAILED*)
    echo "错误: 保存失败: ${RESULT#SAVE_FAILED }"
    exit 1
    ;;
  CREATED*|UPDATED*)
    echo "成功: $RESULT"
    echo "密码: $PASSWORD"
    echo "登录: http://${GITLAB_HOST_IP}:${GITLAB_HTTP_PORT}"
    ;;
  *)
    echo "未知结果: $RESULT"
    exit 1
    ;;
esac
