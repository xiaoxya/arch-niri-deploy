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
# shellcheck source=lib/snapshot.sh
source "$SCRIPT_DIR/lib/snapshot.sh"

contains_selection() {
  local needle=$1 value
  shift
  for value in "$@"; do
    [[ $value == "$needle" ]] && return 0
  done
  return 1
}

install_lazyvim() {
  pacman_install neovim git ripgrep fd unzip lazygit
  if confirm "是否部署 LazyVim Starter？现有 Neovim 配置会先备份。"; then
    backup_path "$HOME/.config/nvim"
    backup_path "$HOME/.local/share/nvim"
    backup_path "$HOME/.local/state/nvim"
    backup_path "$HOME/.cache/nvim"
    rm -rf -- "$HOME/.config/nvim"
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf -- "$HOME/.config/nvim/.git"
  fi
}

install_kvm() {
  pacman_install qemu-full libvirt virt-manager virt-viewer dnsmasq iptables-nft \
    bridge-utils edk2-ovmf swtpm
  sudo usermod -aG libvirt,kvm "$USER"
  sudo systemctl enable --now libvirtd
}

install_docker() {
  pacman_install docker docker-compose docker-buildx
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
}

main() {
  init_log
  banner "可选应用安装器"
  require_non_root
  require_arch
  require_command sudo pacman
  check_network
  sudo -v

  local answer
  answer=$(choose_many "选择要安装的分组：" \
    "Firefox 浏览器" \
    "MPV 播放器" \
    "LocalSend（AUR）" \
    "Steam + Lutris + MangoHud" \
    "KVM + virt-manager" \
    "VS Code（官方仓库 Code - OSS）" \
    "Neovim + 可选 LazyVim Starter" \
    "Docker + Compose" \
    "OBS Studio" \
    "Flatpak")
  read -r -a selections <<<"$answer"
  ((${#selections[@]} > 0)) || { info "未选择任何软件。"; return 0; }

  create_snapshot "Before optional applications"
  contains_selection 1 "${selections[@]}" && pacman_install firefox
  contains_selection 2 "${selections[@]}" && pacman_install mpv
  contains_selection 3 "${selections[@]}" && aur_install localsend
  if contains_selection 4 "${selections[@]}"; then
    enable_multilib
    detect_gpu
    install_32bit_gpu_drivers
    pacman_install steam lutris wine-staging winetricks gamemode lib32-gamemode \
      mangohud lib32-mangohud
  fi
  contains_selection 5 "${selections[@]}" && install_kvm
  contains_selection 6 "${selections[@]}" && pacman_install code
  contains_selection 7 "${selections[@]}" && install_lazyvim
  contains_selection 8 "${selections[@]}" && install_docker
  contains_selection 9 "${selections[@]}" && pacman_install obs-studio
  if contains_selection 10 "${selections[@]}"; then
    pacman_install flatpak
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  create_snapshot "After optional applications"

  ok "所选应用已安装。"
  if contains_selection 5 "${selections[@]}" || contains_selection 8 "${selections[@]}"; then
    warn "用户组已更新，请注销并重新登录后再使用虚拟化或 Docker。"
  fi
}

main "$@"
