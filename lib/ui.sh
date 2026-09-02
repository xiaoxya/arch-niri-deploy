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
