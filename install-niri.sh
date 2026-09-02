#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"
# shellcheck source=lib/gpu.sh
source "$SCRIPT_DIR/lib/gpu.sh"
# shellcheck source=lib/btrfs.sh
source "$SCRIPT_DIR/lib/btrfs.sh"
# shellcheck source=lib/snapshot.sh
source "$SCRIPT_DIR/lib/snapshot.sh"

deploy_user_configs() {
  local marker="$HOME/.config/.arch-niri-deploy"
  local item
  if [[ ! -e $marker ]]; then
    for item in niri waybar fuzzel kitty swaync swaylock swayidle fish starship.toml \
      xdg-desktop-portal satty; do
      backup_path "$HOME/.config/$item"
    done
  fi

  install -d "$HOME/.config" "$HOME/.local/bin" "$HOME/Pictures/Screenshots"
  for item in niri waybar fuzzel kitty swaync swaylock swayidle fish xdg-desktop-portal satty; do
    copy_tree "$SCRIPT_DIR/config/$item" "$HOME/.config/$item"
  done
  install -m 0644 "$SCRIPT_DIR/config/starship.toml" "$HOME/.config/starship.toml"
  install -m 0755 "$SCRIPT_DIR/scripts/"*.sh "$HOME/.local/bin/"
  printf 'managed-by=arch-niri-deploy\n' > "$marker"
}

configure_greetd() {
  sudo install -d -m 0755 /etc/greetd
  sudo install -m 0644 /dev/null /etc/greetd/config.toml
  {
    printf '[terminal]\nvt = 1\n\n'
    printf '[default_session]\n'
    printf 'command = "tuigreet --time --remember --remember-session --sessions /usr/share/wayland-sessions --cmd niri-session"\n'
    printf 'user = "greeter"\n'
  } | sudo tee /etc/greetd/config.toml >/dev/null
  sudo systemctl enable greetd
}

configure_services() {
  sudo systemctl enable --now NetworkManager
  sudo systemctl enable bluetooth
  systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service || \
    warn "用户音频服务将在下次登录时由 systemd 启动。"
}

main() {
  init_log
  banner "Niri 桌面环境安装"
  require_non_root
  require_arch
  require_command sudo pacman lspci systemctl getent
  check_network
  sudo -v
  verify_btrfs_layout /

  progress_init 8
  progress_step "创建 Niri 安装前快照"
  create_snapshot "Before Niri desktop installation"
  progress_step "配置中科大 USTC 软件镜像"
  configure_ustc_mirror
  progress_step "更新 Arch Linux 系统"
  sudo pacman -Syu --noconfirm
  progress_step "识别并安装显卡驱动"
  install_gpu_drivers
  progress_step "安装 Niri 与 Wayland 桌面组件"
  pacman_install "${NIRI_PACKAGES[@]}"

  progress_step "部署 Niri 和桌面组件配置"
  deploy_user_configs
  progress_step "配置 greetd、网络、蓝牙与音频服务"
  configure_greetd
  configure_services

  if confirm "是否把 Fish 设置为当前用户的默认 Shell？"; then
    chsh -s /usr/bin/fish
  fi

  if command -v niri >/dev/null 2>&1; then
    niri validate
  fi
  progress_step "校验 Niri 并创建安装后快照"
  create_snapshot "After Niri desktop installation"
  progress_done "Niri 桌面环境安装完成"

  banner "Niri 安装完成"
  ok "配置已部署到 $HOME/.config，脚本已部署到 $HOME/.local/bin。"
  info "重启后 greetd 会显示 Niri 会话。快捷键：Super+T 终端，Super+D 启动器。"
  (( GPU_NEEDS_LEGACY_NVIDIA )) && warn "在安装兼容的 NVIDIA legacy 驱动前，请勿进入 Niri。"
}

main "$@"
