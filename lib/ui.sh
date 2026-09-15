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

section() {
  printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
}

info() { printf '%sℹ%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

# 交互函数经常在命令替换中运行，普通 stdout 会被捕获，stderr 又会先经过
# 后台日志管道。整块同步写入 /dev/tty，可避免菜单内容与输入提示交错；
# 同时直接追加日志，保持故障记录完整。
tty_log_block() {
  local content=$1
  printf '%s' "$content" >/dev/tty
  if [[ -n ${LOG_FILE:-} && -e ${LOG_FILE:-} ]]; then
    printf '%s' "$content" >> "$LOG_FILE"
  fi
}

PROGRESS_CURRENT=0
PROGRESS_TOTAL=0
PROGRESS_STARTED=0
PROGRESS_STEP_STARTED=0
PROGRESS_STEP_LABEL=''
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
  PROGRESS_STARTED=$SECONDS
  PROGRESS_STEP_STARTED=$SECONDS
  PROGRESS_STEP_LABEL=''
  progress_render 0 "准备开始"
}

progress_step() {
  local label=$1 percent
  (( PROGRESS_TOTAL > 0 )) || { error "尚未初始化进度。"; return 1; }
  if [[ -n $PROGRESS_STEP_LABEL ]]; then
    info "上一阶段耗时 $((SECONDS - PROGRESS_STEP_STARTED)) 秒：$PROGRESS_STEP_LABEL"
  fi
  PROGRESS_STEP_STARTED=$SECONDS
  PROGRESS_STEP_LABEL=$label
  if (( PROGRESS_CURRENT < PROGRESS_TOTAL )); then
    ((PROGRESS_CURRENT += 1))
  fi
  percent=$(((PROGRESS_CURRENT - 1) * 100 / PROGRESS_TOTAL))
  progress_render "$percent" "$label"
}

progress_done() {
  local label=${1:-"全部完成"}
  (( PROGRESS_TOTAL > 0 )) || return 0
  if [[ -n $PROGRESS_STEP_LABEL ]]; then
    info "上一阶段耗时 $((SECONDS - PROGRESS_STEP_STARTED)) 秒：$PROGRESS_STEP_LABEL"
    PROGRESS_STEP_LABEL=''
  fi
  PROGRESS_CURRENT=$PROGRESS_TOTAL
  progress_render 100 "$label"
  info "安装阶段总耗时 $((SECONDS - PROGRESS_STARTED)) 秒。"
}

prompt_default() {
  local prompt=$1
  local default_value=$2
  local result
  printf '%s [%s]: ' "$prompt" "$default_value" >/dev/tty
  IFS= read -r result </dev/tty
  printf '%s' "${result:-$default_value}"
}

choose_one() {
  local title=$1 default_index=$2
  shift 2
  local -a options=("$@")
  local answer index menu line
  ((${#options[@]} > 0)) || { error "选择列表不能为空。"; return 1; }
  printf -v menu '\n%s\n' "$title"
  for index in "${!options[@]}"; do
    if (( index + 1 == default_index )); then
      printf -v line '  %d) %s（默认）\n' "$((index + 1))" "${options[$index]}"
    else
      printf -v line '  %d) %s\n' "$((index + 1))" "${options[$index]}"
    fi
    menu+=$line
  done
  tty_log_block "$menu"
  while true; do
    printf '请选择 [%s]：' "$default_index" >/dev/tty
    IFS= read -r answer </dev/tty
    answer=${answer:-$default_index}
    if [[ $answer =~ ^[0-9]+$ ]] \
      && (( answer >= 1 && answer <= ${#options[@]} )); then
      printf '%s' "$answer"
      return 0
    fi
    printf -v line '%s!%s 无效选择，请输入 1 到 %d 之间的编号。\n' \
      "$C_YELLOW" "$C_RESET" "${#options[@]}"
    tty_log_block "$line"
  done
}

summary_row() {
  printf '  %-18s %s\n' "$1" "$2"
}

choose_many() {
  local title=$1
  shift
  local -a options=("$@")
  local answer index menu line
  printf -v menu '\n%s\n' "$title"
  for index in "${!options[@]}"; do
    printf -v line '  %d) %s\n' "$((index + 1))" "${options[$index]}"
    menu+=$line
  done
  tty_log_block "$menu"
  printf '输入编号（空格分隔），直接回车跳过：' >/dev/tty
  IFS= read -r answer </dev/tty
  printf '%s' "$answer"
}
