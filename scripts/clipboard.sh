#!/usr/bin/env bash
set -Eeuo pipefail

for command_name in cliphist fuzzel wl-copy; do
  command -v "$command_name" >/dev/null 2>&1 || {
    notify-send -u critical "剪贴板" "缺少命令：${command_name}"
    exit 1
  }
done

selection=$(cliphist list | fuzzel --dmenu --prompt='剪贴板 ❯ ' --width=70) || exit 0
[[ -n $selection ]] || exit 0
cliphist decode <<<"$selection" | wl-copy
notify-send -t 1500 "剪贴板" "已复制所选历史记录。"
