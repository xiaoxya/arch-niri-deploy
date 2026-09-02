#!/usr/bin/env bash
set -Eeuo pipefail

command -v fuzzel >/dev/null 2>&1 || exit 1

choice=$(printf '锁屏\n注销\n睡眠\n重启\n关机\n' | fuzzel --dmenu --prompt='电源 ❯ ') || exit 0

case $choice in
  锁屏) exec swaylock -f ;;
  注销) label='注销' ;;
  睡眠) label='睡眠' ;;
  重启) label='重启' ;;
  关机) label='关机' ;;
  *) exit 0 ;;
esac

confirmation=$(printf '取消\n确认%s\n' "$label" | fuzzel --dmenu --prompt='请确认 ❯ ') || exit 0
[[ $confirmation == "确认${label}" ]] || exit 0

case $choice in
  注销) exec niri msg action quit ;;
  睡眠) exec systemctl suspend ;;
  重启) exec systemctl reboot ;;
  关机) exec systemctl poweroff ;;
esac
