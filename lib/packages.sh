#!/usr/bin/env bash
set -Eeuo pipefail

# 这些数组由入口脚本读取，单独检查库文件时 ShellCheck 无法看到调用方。
# shellcheck disable=SC2034
readonly -a BASE_PACKAGES=(
  base linux linux-firmware mkinitcpio iptables-nft btrfs-progs sudo networkmanager openssh
  reflector snapper pacman-contrib git curl wget vim nano man-db man-pages
  bash-completion less which usbutils pciutils efibootmgr dosfstools
)

# pacman 会在读取 mirrorlist 时展开 $repo 与 $arch，此处必须保留字面量。
# shellcheck disable=SC2016
readonly USTC_ARCH_MIRROR='https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch'

configure_ustc_mirror() {
  local root=${1:-}
  local mirrorlist="${root%/}/etc/pacman.d/mirrorlist"
  local -a privilege=()
  (( EUID == 0 )) || privilege=(sudo)

  "${privilege[@]}" install -d "$(dirname -- "$mirrorlist")"
  if [[ -f $mirrorlist && ! -e ${mirrorlist}.pre-ustc ]]; then
    "${privilege[@]}" cp -a "$mirrorlist" "${mirrorlist}.pre-ustc"
  fi
  {
    printf '# Managed by arch-niri-deploy; reflector.timer is intentionally disabled.\n'
    printf 'Server = %s\n' "$USTC_ARCH_MIRROR"
  } | "${privilege[@]}" tee "$mirrorlist" >/dev/null
}

# shellcheck disable=SC2034
readonly -a NIRI_PACKAGES=(
  niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
  xdg-desktop-portal-gtk pipewire pipewire-alsa pipewire-pulse pipewire-jack
  wireplumber fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-rime
  waybar fuzzel kitty swaync swaylock swayidle swaybg wl-clipboard cliphist
  grim slurp satty thunar tumbler ffmpegthumbnailer poppler-glib gvfs
  gvfs-smb gvfs-mtp gvfs-gphoto2 file-roller thunar-archive-plugin
  greetd greetd-tuigreet polkit-gnome gnome-keyring network-manager-applet
  pavucontrol brightnessctl playerctl bluez bluez-utils blueman
  noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu ttf-nerd-fonts-symbols-mono
  fish starship jq libnotify
)

pacman_install() {
  local -a packages=("$@")
  ((${#packages[@]} > 0)) || return 0
  sudo pacman -S --needed --noconfirm "${packages[@]}"
}

pacman_install_root() {
  local -a packages=("$@")
  ((${#packages[@]} > 0)) || return 0
  pacman -S --needed --noconfirm "${packages[@]}"
}

enable_multilib() {
  if ! grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//;}' /etc/pacman.conf
    sudo pacman -Syy
  fi
}

install_aur_helper() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi
  require_command git makepkg
  local build_dir
  build_dir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin"
  (
    cd "$build_dir/yay-bin"
    makepkg -si --noconfirm
  )
  rm -rf -- "$build_dir"
}

aur_install() {
  install_aur_helper
  yay -S --needed --noconfirm "$@"
}
