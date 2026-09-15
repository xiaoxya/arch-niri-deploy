#!/usr/bin/env bash
set -Eeuo pipefail

configure_console_locale() {
  local root=$1 project_dir=$2
  install -Dm 0644 "$project_dir/config/console/getty-locale.conf" \
    "$root/etc/systemd/system/getty@.service.d/10-arch-niri-locale.conf"
  install -Dm 0644 "$project_dir/config/console/zz-arch-niri-console.sh" \
    "$root/etc/profile.d/zz-arch-niri-console.sh"
  install -Dm 0644 "$project_dir/config/console/arch-niri-console.fish" \
    "$root/etc/fish/conf.d/arch-niri-console.fish"
}
