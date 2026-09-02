#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID == 0 )); then
  printf '请以普通用户运行；脚本会自行调用 sudo。\n' >&2
  exit 1
fi

sudo -v
if command -v snapper >/dev/null 2>&1 && [[ -f /etc/snapper/configs/root ]]; then
  sudo snapper -c root create --description "Before system update $(date +%F)" --cleanup-algorithm number
fi

sudo pacman -Syu

if command -v yay >/dev/null 2>&1; then
  yay -Sua
fi

if command -v flatpak >/dev/null 2>&1; then
  flatpak update -y
fi

if command -v snapper >/dev/null 2>&1 && [[ -f /etc/snapper/configs/root ]]; then
  sudo snapper -c root create --description "After system update $(date +%F)" --cleanup-algorithm number
fi

printf '系统更新完成。\n'
