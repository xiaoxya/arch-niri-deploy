#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_NAME="arch-niri-deploy"
LOG_FILE="${LOG_FILE:-/tmp/${PROJECT_NAME}-$(date +%Y%m%d-%H%M%S).log}"

init_log() {
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

die() {
  local message=${1:-"发生未知错误"}
  printf '\n错误：%s\n日志：%s\n' "$message" "$LOG_FILE" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  local line=${BASH_LINENO[0]:-unknown}
  printf '\n命令在第 %s 行失败（退出码 %s）。日志：%s\n' "$line" "$exit_code" "$LOG_FILE" >&2
  exit "$exit_code"
}

trap on_error ERR

require_command() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || die "缺少命令：${command_name}"
  done
}

require_root() {
  (( EUID == 0 )) || die "此步骤必须以 root 身份运行。"
}

require_non_root() {
  (( EUID != 0 )) || die "请以普通用户运行；脚本会在需要时调用 sudo。"
}

require_arch() {
  [[ -r /etc/arch-release ]] || die "仅支持 Arch Linux。"
}

require_uefi() {
  [[ -d /sys/firmware/efi/efivars ]] || die "当前不是 UEFI 启动模式。请关闭 Legacy/CSM 后重试。"
}

check_network() {
  getent ahosts archlinux.org >/dev/null 2>&1 || die "无法解析 archlinux.org，请先连接网络。"
}

is_valid_hostname() {
  [[ $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

is_valid_username() {
  [[ $1 =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]
}

backup_path() {
  local path=$1
  local backup
  [[ -e $path || -L $path ]] || return 0
  backup="${path}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a -- "$path" "$backup"
  printf '已备份：%s -> %s\n' "$path" "$backup"
}

copy_tree() {
  local source_dir=$1
  local target_dir=$2
  install -d -m 0755 "$target_dir"
  cp -a -- "$source_dir"/. "$target_dir"/
}

confirm() {
  local prompt=${1:-"继续？"}
  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ $answer =~ ^[Yy]$ ]]
}
