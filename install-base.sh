#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/disk.sh
source "$SCRIPT_DIR/lib/disk.sh"
# shellcheck source=lib/btrfs.sh
source "$SCRIPT_DIR/lib/btrfs.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"

MOUNTED=0
cleanup() {
  if (( MOUNTED )); then
    sync
    umount -R /mnt 2>/dev/null || true
  fi
}
trap cleanup EXIT

prompt_install_settings() {
  local mirror_pattern='^[[:alpha:] ,_-]+$'
  HOSTNAME_VALUE=$(prompt_default "主机名" "arch-niri")
  is_valid_hostname "$HOSTNAME_VALUE" || die "主机名格式无效。"

  USERNAME_VALUE=$(prompt_default "普通用户名" "user")
  is_valid_username "$USERNAME_VALUE" || die "用户名格式无效。"

  TIMEZONE_VALUE=$(prompt_default "时区" "Asia/Shanghai")
  [[ -e "/usr/share/zoneinfo/${TIMEZONE_VALUE}" ]] || die "时区不存在：${TIMEZONE_VALUE}"

  KEYMAP_VALUE=$(prompt_default "TTY 键盘布局" "us")
  localectl list-keymaps | grep -Fxq "$KEYMAP_VALUE" || die "键盘布局不存在：${KEYMAP_VALUE}"

  MIRROR_COUNTRIES=$(prompt_default "优选镜像国家/地区（逗号分隔）" "China,Singapore,Japan")
  [[ $MIRROR_COUNTRIES =~ $mirror_pattern ]] || die "镜像国家/地区格式无效。"

  while true; do
    read -r -s -p "设置 ${USERNAME_VALUE} 的密码：" USER_PASSWORD
    printf '\n'
    read -r -s -p "再次输入密码：" password_confirm
    printf '\n'
    [[ -n $USER_PASSWORD ]] || { warn "密码不能为空。"; continue; }
    [[ $USER_PASSWORD == "$password_confirm" ]] && break
    warn "两次密码不一致，请重试。"
  done
  unset password_confirm
}

configure_installed_system() {
  local disk=$1 root_partition=$2 microcode_package=$3 microcode_image=$4
  local root_uuid
  root_uuid=$(blkid -s UUID -o value "$root_partition")

  info "配置语言、时区、用户和服务……"
  ln -sf "/usr/share/zoneinfo/${TIMEZONE_VALUE}" /mnt/etc/localtime
  arch-chroot /mnt hwclock --systohc
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
  sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  printf 'LANG=en_US.UTF-8\n' > /mnt/etc/locale.conf
  printf 'KEYMAP=%s\n' "$KEYMAP_VALUE" > /mnt/etc/vconsole.conf
  printf '%s\n' "$HOSTNAME_VALUE" > /mnt/etc/hostname
  {
    printf '127.0.0.1 localhost\n'
    printf '::1 localhost\n'
    printf '127.0.1.1 %s.localdomain %s\n' "$HOSTNAME_VALUE" "$HOSTNAME_VALUE"
  } > /mnt/etc/hosts

  arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME_VALUE"
  printf '%s:%s\n' "$USERNAME_VALUE" "$USER_PASSWORD" | arch-chroot /mnt chpasswd
  unset USER_PASSWORD
  install -Dm 0440 /dev/null /mnt/etc/sudoers.d/10-wheel
  printf '%%wheel ALL=(ALL:ALL) ALL\n' > /mnt/etc/sudoers.d/10-wheel
  arch-chroot /mnt passwd -l root

  info "安装 systemd-boot……"
  arch-chroot /mnt bootctl --esp-path=/boot install
  install -d /mnt/boot/loader/entries
  {
    printf 'default arch.conf\ntimeout 3\nconsole-mode max\neditor no\n'
  } > /mnt/boot/loader/loader.conf
  {
    printf 'title   Arch Linux\nlinux   /vmlinuz-linux\n'
    [[ -n $microcode_image ]] && printf 'initrd  /%s\n' "$microcode_image"
    printf 'initrd  /initramfs-linux.img\n'
    printf 'options root=UUID=%s rw rootflags=subvol=@ quiet\n' "$root_uuid"
  } > /mnt/boot/loader/entries/arch.conf
  {
    printf 'title   Arch Linux (fallback initramfs)\nlinux   /vmlinuz-linux\n'
    [[ -n $microcode_image ]] && printf 'initrd  /%s\n' "$microcode_image"
    printf 'initrd  /initramfs-linux-fallback.img\n'
    printf 'options root=UUID=%s rw rootflags=subvol=@\n' "$root_uuid"
  } > /mnt/boot/loader/entries/arch-fallback.conf

  arch-chroot /mnt mkinitcpio -P
  arch-chroot /mnt systemctl enable NetworkManager sshd reflector.timer fstrim.timer

  info "部署项目副本并启用 Snapper……"
  rm -rf /mnt/opt/arch-niri-deploy
  install -d /mnt/opt/arch-niri-deploy
  cp -a "$SCRIPT_DIR"/. /mnt/opt/arch-niri-deploy/
  arch-chroot /mnt bash -c "source /opt/arch-niri-deploy/lib/snapshot.sh; configure_snapper_root '$USERNAME_VALUE'"
  arch-chroot /mnt btrfs quota enable / || true
  arch-chroot /mnt snapper -c root create --description 'Fresh Arch base system' --cleanup-algorithm number || true

  info "校验 sudo 配置和引导文件……"
  arch-chroot /mnt visudo -cf /etc/sudoers
  [[ -s /mnt/boot/vmlinuz-linux ]] || die "内核未写入 ESP。"
  [[ -s /mnt/etc/fstab ]] || die "fstab 为空。"
  ok "基础系统配置完成（CPU 微码：${microcode_package}，磁盘：${disk}）。"
}

main() {
  init_log
  banner "Arch Linux 基础系统安装"
  require_root
  require_uefi
  [[ $(uname -m) == x86_64 ]] || die "仅支持 x86_64。"
  require_command lsblk awk wipefs sgdisk partprobe udevadm mkfs.fat mkfs.btrfs \
    btrfs pacstrap genfstab arch-chroot blkid localectl getent
  check_network
  findmnt /mnt >/dev/null 2>&1 && warn "/mnt 已挂载；确认后会先卸载。"

  prompt_install_settings
  local disk esp_partition root_partition microcode_package microcode_image
  disk=$(select_disk)
  confirm_disk_destruction "$disk"

  case $(awk -F: '/vendor_id/{gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo) in
    GenuineIntel) microcode_package=intel-ucode; microcode_image=intel-ucode.img ;;
    AuthenticAMD) microcode_package=amd-ucode; microcode_image=amd-ucode.img ;;
    *) microcode_package=''; microcode_image=''; warn "未识别 CPU 厂商，将不安装微码包。" ;;
  esac

  partition_disk "$disk"
  format_partitions "$disk"
  esp_partition=$(partition_path "$disk" 1)
  root_partition=$(partition_path "$disk" 2)
  create_subvolumes "$root_partition"
  mount_subvolumes "$root_partition" "$esp_partition"
  MOUNTED=1

  info "刷新密钥与镜像列表……"
  pacman -Sy --needed --noconfirm archlinux-keyring reflector
  reflector --country "$MIRROR_COUNTRIES" --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist || \
    warn "Reflector 未能优化镜像，将沿用 ISO 当前镜像列表。"

  local -a bootstrap_packages=("${BASE_PACKAGES[@]}")
  [[ -n $microcode_package ]] && bootstrap_packages+=("$microcode_package")
  info "安装基础软件包（不包含桌面）……"
  pacstrap -K /mnt "${bootstrap_packages[@]}"
  genfstab -U /mnt > /mnt/etc/fstab
  configure_installed_system "$disk" "$root_partition" "$microcode_package" "$microcode_image"

  banner "安装完成"
  ok "已得到纯 Arch 基础系统：网络、SSH、sudo、Btrfs/Snapper 和 systemd-boot 均已配置。"
  info "卸载后可执行 reboot；登录后运行：/opt/arch-niri-deploy/install-niri.sh"
}

main "$@"
