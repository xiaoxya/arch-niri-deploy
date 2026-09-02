#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BOLD=$'\033[1m'
  readonly C_BLUE=$'\033[34m'
  readonly C_GREEN=$'\033[32m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_RED=$'\033[31m'
else
  readonly C_RESET='' C_BOLD='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED=''
fi

banner() {
  printf '\n%s%s%s\n' "$C_BOLD$C_BLUE" "$1" "$C_RESET"
  printf '%s\n' '────────────────────────────────────────────────────────'
}

info() { printf '%sℹ%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

PROGRESS_CURRENT=0
PROGRESS_TOTAL=0
readonly PROGRESS_WIDTH=28

progress_render() {
  local percent=$1 label=$2
  local filled empty done_bar empty_bar
  filled=$((percent * PROGRESS_WIDTH / 100))
  empty=$((PROGRESS_WIDTH - filled))
  printf -v done_bar '%*s' "$filled" ''
  printf -v empty_bar '%*s' "$empty" ''
  done_bar=${done_bar// /#}
  empty_bar=${empty_bar// /-}
  printf '%s进度%s [%s%s] %3d%% (%d/%d) %s\n' \
    "$C_BLUE" "$C_RESET" "$done_bar" "$empty_bar" "$percent" \
    "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$label"
}

progress_init() {
  local total=$1
  (( total > 0 )) || { error "进度总步骤必须大于 0。"; return 1; }
  PROGRESS_CURRENT=0
  PROGRESS_TOTAL=$total
  progress_render 0 "准备开始"
}

progress_step() {
  local label=$1 percent
  (( PROGRESS_TOTAL > 0 )) || { error "尚未初始化进度。"; return 1; }
  if (( PROGRESS_CURRENT < PROGRESS_TOTAL )); then
    ((PROGRESS_CURRENT += 1))
  fi
  percent=$(((PROGRESS_CURRENT - 1) * 100 / PROGRESS_TOTAL))
  progress_render "$percent" "$label"
}

progress_done() {
  local label=${1:-"全部完成"}
  (( PROGRESS_TOTAL > 0 )) || return 0
  PROGRESS_CURRENT=$PROGRESS_TOTAL
  progress_render 100 "$label"
}

prompt_default() {
  local prompt=$1
  local default_value=$2
  local result
  read -r -p "${prompt} [${default_value}]: " result
  printf '%s' "${result:-$default_value}"
}

choose_many() {
  local title=$1
  shift
  local -a options=("$@")
  local answer index
  printf '\n%s\n' "$title"
  for index in "${!options[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${options[$index]}"
  done
  printf '输入编号（空格分隔），直接回车跳过：'
  read -r answer
  printf '%s' "$answer"
}
