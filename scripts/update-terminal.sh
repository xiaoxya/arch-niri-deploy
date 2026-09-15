#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=${ARCH_NIRI_DEPLOY_DIR:-$(dirname -- "$SCRIPT_DIR")}
if [[ ! -f $PROJECT_DIR/lib/terminal.sh ]]; then
  PROJECT_DIR=/opt/arch-niri-deploy
fi
if [[ ! -f $PROJECT_DIR/lib/terminal.sh ]]; then
  printf '请从新版项目目录执行：bash scripts/update-terminal.sh\n' >&2
  exit 1
fi
# shellcheck source=../lib/common.sh
source "$PROJECT_DIR/lib/common.sh"
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/packages.sh
source "$PROJECT_DIR/lib/packages.sh"
# shellcheck source=../lib/terminal.sh
source "$PROJECT_DIR/lib/terminal.sh"

main() {
  local package
  local -a missing=()
  local -a required=("${SHORIN_TERMINAL_PACKAGES[@]}" ttf-firacode-nerd
    noto-fonts noto-fonts-cjk noto-fonts-emoji)
  require_non_root
  require_arch
  require_command sudo pacman
  init_log
  banner '更新 Fish 命令行美化'
  progress_init 4
  progress_step '检查终端工具和 Nerd Font'
  for package in "${required[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  if ((${#missing[@]})); then
    info "需补装：${missing[*]}；将使用当前软件源进行完整系统升级并补齐依赖。"
    sudo pacman -Syu --needed --noconfirm "${required[@]}"
  fi
  fc-cache -f
  progress_step '备份并更新 Fish、Starship 与 Kitty 配置'
  deploy_terminal_configs "$PROJECT_DIR"
  progress_step '设置默认 Fish'
  configure_default_shell
  progress_step '验证字体和提示符，并显示预览'
  verify_terminal_configs
  progress_done '终端美化更新完成'
  info '关闭并重新打开 Kitty 即可生效；无需重新安装 Niri。'
}

main "$@"
