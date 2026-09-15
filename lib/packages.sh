#!/usr/bin/env bash
set -Eeuo pipefail

# 这些数组由入口脚本读取，单独检查库文件时 ShellCheck 无法看到调用方。
# shellcheck disable=SC2034
readonly -a BASE_PACKAGES=(
  base linux linux-firmware mkinitcpio iptables-nft btrfs-progs sudo networkmanager openssh
  reflector snapper pacman-contrib archlinuxcn-keyring git curl wget vim nano man-db man-pages
  bash-completion less which usbutils pciutils efibootmgr dosfstools jq
)

# Pacman 会在读取配置时展开 $repo 与 $arch，此处必须保留字面量。
# shellcheck disable=SC2016
readonly USTC_ARCH_MIRROR='https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch'
readonly USTC_ARCHLINUXCN_MIRROR='https://mirrors.ustc.edu.cn/archlinuxcn/$arch'
readonly TUNA_ARCH_MIRROR='https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch'
readonly TUNA_ARCHLINUXCN_MIRROR='https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch'
readonly PACMAN_PARALLEL_DOWNLOADS=5
readonly USTC_PROBE_URL='https://mirrors.ustc.edu.cn/archlinux/core/os/x86_64/core.db'
readonly TUNA_PROBE_URL='https://mirrors.tuna.tsinghua.edu.cn/archlinux/core/os/x86_64/core.db'
readonly DEFAULT_MIRROR_PROFILE='ustc'
readonly MIRROR_PROFILE_FILE='/etc/arch-niri-deploy/mirror-profile'

mirror_profile_values() {
  local profile=$1
  case $profile in
    ustc) printf '%s\n' "ustc|中国科学技术大学 USTC|${USTC_ARCH_MIRROR}|${USTC_ARCHLINUXCN_MIRROR}|${USTC_PROBE_URL}" ;;
    tuna) printf '%s\n' "tuna|清华大学 TUNA|${TUNA_ARCH_MIRROR}|${TUNA_ARCHLINUXCN_MIRROR}|${TUNA_PROBE_URL}" ;;
    *) die "未知镜像配置：${profile}" ;;
  esac
}

resolve_mirror_profile() {
  local root=${1:-} requested=${2:-} profile profile_file
  profile=$requested
  profile_file="${root%/}${MIRROR_PROFILE_FILE}"
  if [[ -z $profile && -f $profile_file ]]; then
    IFS= read -r profile < "$profile_file" || true
  fi
  profile=${profile:-$DEFAULT_MIRROR_PROFILE}
  mirror_profile_values "$profile" >/dev/null
  printf '%s\n' "$profile"
}

mirror_profile_label() {
  local _profile label _official _archlinuxcn _probe
  IFS='|' read -r _profile label _official _archlinuxcn _probe \
    <<< "$(mirror_profile_values "$1")"
  printf '%s' "$label"
}

configure_mirror_profile() {
  local root=${1:-} requested=${2:-}
  local profile label official_mirror archlinuxcn_mirror _probe
  local mirrorlist pacman_conf profile_file temporary
  local -a privilege=()
  (( EUID == 0 )) || privilege=(sudo)
  profile=$(resolve_mirror_profile "$root" "$requested")
  IFS='|' read -r profile label official_mirror archlinuxcn_mirror _probe \
    <<< "$(mirror_profile_values "$profile")"
  mirrorlist="${root%/}/etc/pacman.d/mirrorlist"
  pacman_conf="${root%/}/etc/pacman.conf"
  profile_file="${root%/}${MIRROR_PROFILE_FILE}"

  "${privilege[@]}" install -d "$(dirname -- "$mirrorlist")" "$(dirname -- "$profile_file")"
  [[ -f $pacman_conf ]] || die "找不到 Pacman 配置：${pacman_conf}"
  if [[ -f $mirrorlist && ! -e ${mirrorlist}.pre-arch-niri-deploy ]]; then
    "${privilege[@]}" cp -a "$mirrorlist" "${mirrorlist}.pre-arch-niri-deploy"
  fi
  if [[ ! -e ${pacman_conf}.pre-archlinuxcn ]]; then
    "${privilege[@]}" cp -a "$pacman_conf" "${pacman_conf}.pre-archlinuxcn"
  fi
  {
    printf '# Managed by arch-niri-deploy; reflector.timer is intentionally disabled.\n'
    printf 'Server = %s\n' "$official_mirror"
  } | "${privilege[@]}" tee "$mirrorlist" >/dev/null
  temporary=$(mktemp)
  awk -v server="$archlinuxcn_mirror" '
    BEGIN { found = 0; in_archlinuxcn = 0 }
    /^\[archlinuxcn\][[:space:]]*$/ {
      if (!found) {
        print "[archlinuxcn]"
        print "Server = " server
        found = 1
      }
      in_archlinuxcn = 1
      next
    }
    in_archlinuxcn && /^\[[^]]+\][[:space:]]*$/ { in_archlinuxcn = 0 }
    !in_archlinuxcn { print }
    END {
      if (!found) {
        print ""
        print "[archlinuxcn]"
        print "Server = " server
      }
    }
  ' "$pacman_conf" > "$temporary"
  "${privilege[@]}" install -m 0644 "$temporary" "$pacman_conf"
  rm -f -- "$temporary"
  printf '%s\n' "$profile" | "${privilege[@]}" tee "$profile_file" >/dev/null
  grep -Fqx "Server = ${official_mirror}" "$mirrorlist" \
    && grep -Fqx '[archlinuxcn]' "$pacman_conf" \
    && grep -Fqx "Server = ${archlinuxcn_mirror}" "$pacman_conf" \
    && grep -Fqx "$profile" "$profile_file" \
    || die "无法写入 ${label} 镜像配置。"
  info "已选择镜像：${label}"
  info "Arch Linux：${official_mirror}（写入 ${mirrorlist}）"
  info "Arch Linux CN：${archlinuxcn_mirror}（写入 ${pacman_conf}）"
}

configure_pacman_parallel_downloads() {
  local root=${1:-}
  local pacman_conf="${root%/}/etc/pacman.conf"
  local -a privilege=()
  (( EUID == 0 )) || privilege=(sudo)

  [[ -f $pacman_conf ]] || die "找不到 Pacman 配置：${pacman_conf}"
  if grep -Eq '^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=' "$pacman_conf"; then
    "${privilege[@]}" sed -E -i \
      "s|^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=.*|ParallelDownloads = ${PACMAN_PARALLEL_DOWNLOADS}|" \
      "$pacman_conf"
  else
    "${privilege[@]}" sed -i \
      "/^\[options\]/a ParallelDownloads = ${PACMAN_PARALLEL_DOWNLOADS}" "$pacman_conf"
  fi
  grep -Fqx "ParallelDownloads = ${PACMAN_PARALLEL_DOWNLOADS}" "$pacman_conf" \
    || die "无法启用 Pacman 并行下载。"
  info "Pacman 已启用 ${PACMAN_PARALLEL_DOWNLOADS} 路并行下载。"
}

test_selected_mirror_connection() {
  local requested=${1:-} profile label _official _archlinuxcn probe_url
  local probe_result status speed_bytes speed_kib
  profile=$(resolve_mirror_profile '' "$requested")
  IFS='|' read -r profile label _official _archlinuxcn probe_url \
    <<< "$(mirror_profile_values "$profile")"
  require_command curl
  info "正在测试 ${label} 镜像 HTTPS 连通性（IPv4，最多等待 20 秒）……"
  if ! probe_result=$(curl --ipv4 --fail --location --silent --show-error \
    --connect-timeout 8 --max-time 20 --output /dev/null \
    --write-out '%{http_code}|%{speed_download}' "$probe_url"); then
    die "无法通过 IPv4 连接 ${label} 镜像；请检查网络或 DNS 后重试，未开始下载基础包。"
  fi
  IFS='|' read -r status speed_bytes <<< "$probe_result"
  [[ $status == 200 ]] || die "${label} 镜像预检返回 HTTP ${status:-未知}，未开始下载基础包。"
  speed_kib=$(awk -v bytes="$speed_bytes" 'BEGIN { printf "%.0f", bytes / 1024 }')
  [[ $speed_kib =~ ^[0-9]+$ ]] || die "无法读取 USTC 镜像测速结果。"
  if (( speed_kib < 64 )); then
    warn "${label} 镜像测速仅 ${speed_kib} KiB/s；下载约 767 MiB 基础包可能非常慢。"
    confirm "仍要使用 ${label} 继续下载？" \
      || die "用户取消低速下载，未开始安装基础包。"
  else
    ok "${label} 镜像连接正常：${speed_kib} KiB/s（IPv4 预检）。"
  fi
}

# shellcheck disable=SC2034
readonly -a NIRI_PACKAGES=(
  niri xwayland-satellite xdg-desktop-portal xdg-desktop-portal-gnome
  xdg-desktop-portal-gtk pipewire pipewire-alsa pipewire-pulse pipewire-jack
  wireplumber sof-firmware alsa-ucm-conf
  wl-clipboard cliphist grim slurp satty thunar tumbler poppler-glib gvfs
  gvfs-smb gvfs-mtp gvfs-gphoto2 file-roller thunar-archive-plugin
  greetd gnome-keyring xdg-user-dirs
  brightnessctl bluez bluez-utils jq libnotify
)

# DankMaterialShell 的 Arch 官方仓库稳定版及完整 Niri 集成。
# 显式指定 dms-shell-niri，避免 pacman 在 compositor provider 中误选 Hyprland。
# shellcheck disable=SC2034
readonly -a DMS_PACKAGES=(
  dms-shell-niri matugen cava qt6-multimedia-ffmpeg wtype
  power-profiles-daemon papirus-icon-theme adw-gtk-theme
)

# DMS Greeter 是 DMS 官方维护的 greetd 图形登录器。目前 Arch 官方仓库
# 未提供该包，因此通过 AUR 的二进制发行包安装，避免在桌面安装中编译 DMS。
readonly DMS_GREETER_AUR_PACKAGE='greetd-dms-greeter-bin'

# SHORiN DMS Niri 中字体、输入法、Shell 与终端的通用稳定子集。
# 仅使用 Arch 官方仓库组件；雾凇拼音词库由 install-niri.sh 从上游部署。
# shellcheck disable=SC2034
readonly -a SHORIN_FONT_PACKAGES=(
  noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
  adobe-source-han-sans-cn-fonts adobe-source-han-serif-cn-fonts
  ttf-dejavu ttf-liberation ttf-roboto ttf-opensans
  ttf-firacode-nerd ttf-jetbrains-mono-nerd
  ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono
  ttf-material-symbols-variable otf-font-awesome terminus-font
)

# shellcheck disable=SC2034
readonly -a SHORIN_INPUT_PACKAGES=(
  fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-rime
  qt5-wayland qt6-wayland
)

# shellcheck disable=SC2034
readonly -a SHORIN_TERMINAL_PACKAGES=(
  kitty fish starship eza zoxide bat yazi fastfetch
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
  sudo pacman -S --needed --noconfirm base-devel
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
