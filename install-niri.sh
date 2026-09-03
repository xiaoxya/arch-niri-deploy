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
  local stack_marker="$HOME/.config/.arch-niri-deploy-shorin-stack-v1"
  local item
  if [[ ! -e $marker ]]; then
    for item in niri waybar fuzzel swaync swaylock swayidle xdg-desktop-portal satty; do
      backup_path "$HOME/.config/$item"
    done
  fi
  if [[ ! -e $stack_marker ]]; then
    for item in foot fish fontconfig fcitx5 starship.toml; do
      backup_path "$HOME/.config/$item"
    done
    backup_path "$HOME/.local/share/fcitx5/rime"
  fi

  install -d "$HOME/.config" "$HOME/.local/bin" "$HOME/Pictures/Screenshots"
  for item in niri waybar fuzzel foot swaync swaylock swayidle fish fontconfig fcitx5 \
    xdg-desktop-portal satty; do
    copy_tree "$SCRIPT_DIR/config/$item" "$HOME/.config/$item"
  done
  install -m 0644 "$SCRIPT_DIR/config/starship.toml" "$HOME/.config/starship.toml"
  install -m 0755 "$SCRIPT_DIR/scripts/"*.sh "$HOME/.local/bin/"
  printf 'managed-by=arch-niri-deploy\n' > "$marker"
  printf 'managed-by=arch-niri-deploy\n' > "$stack_marker"
}

install_rime_ice() {
  local rime_dir="$HOME/.local/share/fcitx5/rime"
  local temp_dir
  temp_dir=$(mktemp -d)

  if ! git clone --depth 1 https://github.com/iDvel/rime-ice.git "$temp_dir/rime-ice"; then
    rm -rf -- "$temp_dir"
    die "雾凇拼音下载失败，请检查 GitHub 网络连接后重新运行。"
  fi

  install -d -m 0755 "$rime_dir"
  cp -a -- "$temp_dir/rime-ice"/. "$rime_dir"/
  rm -rf -- "$rime_dir/.git" "$temp_dir"
  install -m 0644 "$SCRIPT_DIR/config/rime/default.custom.yaml" \
    "$rime_dir/default.custom.yaml"
}

configure_fonts() {
  if sudo grep -q '^FONT=' /etc/vconsole.conf; then
    sudo sed -i 's/^FONT=.*/FONT=ter-v28n/' /etc/vconsole.conf
  else
    printf 'FONT=ter-v28n\n' | sudo tee -a /etc/vconsole.conf >/dev/null
  fi
  fc-cache -f
}

configure_default_shell() {
  local current_shell
  current_shell=$(getent passwd "$USER" | cut -d: -f7)
  if [[ $current_shell != /usr/bin/fish ]]; then
    sudo chsh -s /usr/bin/fish "$USER"
  fi
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
  require_command sudo pacman lspci systemctl getent git
  check_network
  sudo -v
  verify_btrfs_layout /

  progress_init 13
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
  progress_step "安装 SHORiN 字体组合"
  pacman_install "${SHORIN_FONT_PACKAGES[@]}"
  configure_fonts
  progress_step "安装 Fcitx5 输入法框架"
  pacman_install "${SHORIN_INPUT_PACKAGES[@]}"
  progress_step "安装 Fish、Foot 与终端工具"
  pacman_install "${SHORIN_TERMINAL_PACKAGES[@]}"
  progress_step "部署 Niri 和桌面组件配置"
  deploy_user_configs
  progress_step "部署雾凇拼音词库"
  install_rime_ice
  progress_step "配置 greetd、网络、蓝牙与音频服务"
  configure_greetd
  configure_services

  progress_step "设置 Fish 为当前用户默认 Shell"
  configure_default_shell

  if command -v niri >/dev/null 2>&1; then
    niri validate
  fi
  progress_step "校验 Niri 并创建安装后快照"
  create_snapshot "After Niri desktop installation"
  progress_done "Niri 桌面环境安装完成"

  banner "Niri 安装完成"
  ok "配置已部署到 $HOME/.config，脚本已部署到 $HOME/.local/bin。"
  info "重启后 greetd 会显示 Niri 会话。快捷键：Super+T 终端，Super+D 启动器。"
  if (( GPU_NEEDS_LEGACY_NVIDIA )); then
    warn "在安装兼容的 NVIDIA legacy 驱动前，请勿进入 Niri。"
  fi
}

main "$@"
