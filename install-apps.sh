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

  local answer option selected_count=0
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

  for option in {1..10}; do
    contains_selection "$option" "${selections[@]}" && ((selected_count += 1))
  done
  progress_init "$((selected_count + 3))"
  progress_step "创建可选应用安装前快照"
  create_snapshot "Before optional applications"
  progress_step "配置中科大 USTC 软件镜像"
  configure_ustc_mirror
  if contains_selection 1 "${selections[@]}"; then
    progress_step "安装 Firefox"
    pacman_install firefox
  fi
  if contains_selection 2 "${selections[@]}"; then
    progress_step "安装 MPV"
    pacman_install mpv
  fi
  if contains_selection 3 "${selections[@]}"; then
    progress_step "安装 LocalSend"
    aur_install localsend
  fi
  if contains_selection 4 "${selections[@]}"; then
    progress_step "安装 Steam、Lutris 与 MangoHud"
    enable_multilib
    detect_gpu
    install_32bit_gpu_drivers
    pacman_install steam lutris wine-staging winetricks gamemode lib32-gamemode \
      mangohud lib32-mangohud
  fi
  if contains_selection 5 "${selections[@]}"; then
    progress_step "安装 KVM 与 virt-manager"
    install_kvm
  fi
  if contains_selection 6 "${selections[@]}"; then
    progress_step "安装 VS Code（Code - OSS）"
    pacman_install code
  fi
  if contains_selection 7 "${selections[@]}"; then
    progress_step "安装 Neovim 与可选 LazyVim"
    install_lazyvim
  fi
  if contains_selection 8 "${selections[@]}"; then
    progress_step "安装 Docker 与 Compose"
    install_docker
  fi
  if contains_selection 9 "${selections[@]}"; then
    progress_step "安装 OBS Studio"
    pacman_install obs-studio
  fi
  if contains_selection 10 "${selections[@]}"; then
    progress_step "安装 Flatpak 并配置 Flathub"
    pacman_install flatpak
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  progress_step "创建可选应用安装后快照"
  create_snapshot "After optional applications"
  progress_done "所选应用安装完成"

  ok "所选应用已安装。"
  if contains_selection 5 "${selections[@]}" || contains_selection 8 "${selections[@]}"; then
    warn "用户组已更新，请注销并重新登录后再使用虚拟化或 Docker。"
  fi
}

main "$@"
