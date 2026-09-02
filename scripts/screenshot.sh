#!/usr/bin/env bash
set -Eeuo pipefail

require() {
  command -v "$1" >/dev/null 2>&1 || {
    notify-send -u critical "截图失败" "缺少命令：$1"
    exit 1
  }
}

mode=${1:-area}
output_dir=${XDG_PICTURES_DIR:-"$HOME/Pictures"}/Screenshots
timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
output_file="${output_dir}/Screenshot_${timestamp}.png"
temp_file=$(mktemp --suffix=.png)
trap 'rm -f -- "$temp_file"' EXIT
mkdir -p "$output_dir"

require grim
require satty
require wl-copy

case $mode in
  area)
    require slurp
    geometry=$(slurp) || exit 0
    grim -g "$geometry" "$temp_file"
    ;;
  full)
    grim "$temp_file"
    ;;
  window)
    require niri
    niri msg action screenshot-window
    notify-send "截图" "窗口截图已由 Niri 保存。"
    exit 0
    ;;
  *)
    printf '用法：%s [area|full|window]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

satty --filename "$temp_file" --output-filename "$output_file"
[[ -f $output_file ]] && notify-send "截图已保存" "$output_file"
