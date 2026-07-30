#!/usr/bin/env bash
# 将指定 GitLab 用户密码设为简单默认值（绕过弱密码校验）
# 用法:
#   ./set-user-password.sh <用户名> [密码]
# 示例:
#   ./set-user-password.sh fenghe
#   ./set-user-password.sh fenghe 12345678

set -euo pipefail

USERNAME="${1:-}"
PASSWORD="${2:-12345678}"
CONTAINER="${GITLAB_CONTAINER:-gitlab}"

if [[ -z "$USERNAME" ]]; then
  echo "用法: $0 <用户名> [密码]"
  echo "示例: $0 fenghe"
  echo "      $0 fenghe 12345678"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "错误: 容器 '$CONTAINER' 未在运行"
  exit 1
fi

echo "正在设置用户 '$USERNAME' 的密码..."

RESULT="$(docker exec "$CONTAINER" gitlab-rails runner "
u = User.find_by_username('${USERNAME}') || User.find_by_email('${USERNAME}')
if u.nil?
  puts 'NOT_FOUND'
else
  u.password = u.password_confirmation = '${PASSWORD}'
  u.password_automatically_set = false
  if u.save(validate: false)
    puts \"OK username=#{u.username} email=#{u.email}\"
  else
    puts 'SAVE_FAILED'
  end
end
")"

case "$RESULT" in
  NOT_FOUND)
    echo "错误: 找不到用户 '$USERNAME'（可用用户名或邮箱）"
    exit 1
    ;;
  SAVE_FAILED)
    echo "错误: 保存失败"
    exit 1
    ;;
  OK*)
    echo "成功: $RESULT"
    echo "密码: $PASSWORD"
    echo "登录: http://10.10.0.216:8929"
    ;;
  *)
    echo "未知结果: $RESULT"
    exit 1
    ;;
esac
