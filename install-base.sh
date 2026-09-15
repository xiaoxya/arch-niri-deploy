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
# shellcheck source=lib/locale.sh
source "$SCRIPT_DIR/lib/locale.sh"
# shellcheck source=lib/network.sh
source "$SCRIPT_DIR/lib/network.sh"
# shellcheck source=lib/rollback-package.sh
source "$SCRIPT_DIR/lib/rollback-package.sh"

readonly INSTALL_MOUNT=/mnt
MOUNTED=0
HOSTNAME_VALUE='arch-niri'
USERNAME_VALUE='user'
TIMEZONE_VALUE='Asia/Shanghai'
KEYMAP_VALUE='us'
SYSTEM_LOCALE='zh_CN.UTF-8'
USER_PASSWORD=''
ROOT_PASSWORD=''
ROOT_LOGIN='locked'
MIRROR_PROFILE=$DEFAULT_MIRROR_PROFILE

cleanup() {
  local exit_code=$?
  trap - EXIT
  unset USER_PASSWORD ROOT_PASSWORD
  if [[ $ROLLBACK_SOURCE_DIR == /tmp/arch-niri-rollback-source.* && -d $ROLLBACK_SOURCE_DIR ]]; then
    rm -rf -- "$ROLLBACK_SOURCE_DIR"
  fi
  # Only unmount filesystems owned by this run, never pre-existing /mnt mounts.
  if (( MOUNTED )); then
    if [[ -f $LOG_FILE && -d $INSTALL_MOUNT/var/log ]]; then
      install -D -m 0600 "$LOG_FILE" \
        "$INSTALL_MOUNT/var/log/arch-niri-deploy/base-install-failed.log" \
        2>/dev/null || true
    fi
    sync || true
    if umount -R "$INSTALL_MOUNT" 2>/dev/null; then
      MOUNTED=0
    else
      warn "退出时未能自动卸载 ${INSTALL_MOUNT}，请检查占用后手动卸载。"
      findmnt -R "$INSTALL_MOUNT" || true
    fi
  fi
  exit "$exit_code"
}
trap cleanup EXIT

unmount_target() {
  (( MOUNTED )) || return 0
  info "正在把缓存数据写入磁盘……"
  sync
  if ! umount -R "$INSTALL_MOUNT"; then
    error "自动卸载 ${INSTALL_MOUNT} 失败，当前仍有以下挂载或占用："
    findmnt -R "$INSTALL_MOUNT" || true
    return 1
  fi
  MOUNTED=0
  if findmnt -R "$INSTALL_MOUNT" >/dev/null 2>&1; then
    error "${INSTALL_MOUNT} 下仍存在挂载点，为安全起见请勿重启。"
    findmnt -R "$INSTALL_MOUNT" || true
    return 1
  fi
  ok "目标系统已安全卸载。"
}

read_password_pair() {
  local account_label=$1 destination=$2 first second
  while true; do
    printf '设置 %s 的密码：' "$account_label" >/dev/tty
    IFS= read -r -s first </dev/tty
    printf '\n再次输入密码：' >/dev/tty
    IFS= read -r -s second </dev/tty
    printf '\n' >/dev/tty
    if ((${#first} < 3)); then
      warn "密码至少需要 3 个字符。"
      continue
    fi
    if [[ $first == *:* ]]; then
      warn "密码不能包含冒号。"
      continue
    fi
    if [[ $first != "$second" ]]; then
      warn "两次密码不一致，请重试。"
      continue
    fi
    printf -v "$destination" '%s' "$first"
    first=''
    second=''
    return 0
  done
}

prompt_valid_default() {
  local label=$1 default_value=$2 validator=$3 value
  while true; do
    value=$(prompt_default "$label" "$default_value")
    if "$validator" "$value"; then
      printf '%s' "$value"
      return 0
    fi
    warn "${label}格式无效，请重新输入。" >&2
  done
}

prompt_install_settings() {
  local locale_choice root_choice mirror_choice rollback_choice
  section "系统身份"
  HOSTNAME_VALUE=$(prompt_valid_default "主机名" "$HOSTNAME_VALUE" is_valid_hostname)
  USERNAME_VALUE=$(prompt_valid_default "普通用户名" "$USERNAME_VALUE" is_valid_username)

  while true; do
    TIMEZONE_VALUE=$(prompt_default "时区" "$TIMEZONE_VALUE")
    [[ -e "/usr/share/zoneinfo/${TIMEZONE_VALUE}" ]] && break
    warn "时区不存在：${TIMEZONE_VALUE}"
  done
  while true; do
    KEYMAP_VALUE=$(prompt_default "TTY 键盘布局" "$KEYMAP_VALUE")
    # Consume all output: grep -q may SIGPIPE localectl under pipefail.
    localectl list-keymaps | grep -Fx "$KEYMAP_VALUE" >/dev/null && break
    warn "键盘布局不存在：${KEYMAP_VALUE}"
  done

  locale_choice=$(choose_one "选择系统语言" 1 \
    "简体中文（zh_CN.UTF-8）" \
    "English (en_US.UTF-8)")
  case $locale_choice in
    1) SYSTEM_LOCALE='zh_CN.UTF-8' ;;
    2) SYSTEM_LOCALE='en_US.UTF-8' ;;
  esac
  info "本机 TTY 使用英文 UTF-8；所选语言用于桌面及其他正常支持中文的终端。"

  mirror_choice=$(choose_one "选择软件镜像" 1 \
    "中国科学技术大学 USTC（默认）" \
    "清华大学 TUNA")
  case $mirror_choice in
    1) MIRROR_PROFILE='ustc' ;;
    2) MIRROR_PROFILE='tuna' ;;
  esac

  prompt_network_settings
  rollback_choice=$(choose_one '安装额外的 snapper-rollback 包？' 1 \
    '安装（固定版本安全封装包，增加 base-devel 构建依赖）' \
    '跳过（仍保留原有 Snapper 回滚工具）')
  [[ $rollback_choice == 1 ]] || INSTALL_ROLLBACK_PACKAGE=0

  section "账户密码"
  read_password_pair "$USERNAME_VALUE" USER_PASSWORD
  root_choice=$(choose_one "root 账户策略" 1 \
    "锁定 root，仅使用 sudo" \
    "设置独立 root 密码")
  if [[ $root_choice == 2 ]]; then
    ROOT_LOGIN='password'
    read_password_pair root ROOT_PASSWORD
  fi
}

verify_install_environment() {
  require_root
  require_arch
  require_uefi
  [[ $(uname -m) == x86_64 ]] || die "仅支持 x86_64。"
  [[ -r /dev/tty && -w /dev/tty ]] || die "需要交互式终端，不能通过无 TTY 的管道运行。"
  require_command lsblk awk wipefs sgdisk partprobe udevadm mkfs.fat mkfs.btrfs \
    btrfs pacstrap genfstab arch-chroot blkid localectl getent findmnt sync umount \
    swapon readlink tar grep sed tee find install mount sleep mktemp curl ip sha256sum

  if [[ ! -d /run/archiso ]]; then
    warn "未检测到官方 Arch ISO 环境；请确认你正在使用专用的 Arch Live 系统。"
    confirm "仍要继续？" || die "用户取消安装。"
  fi
  install -d "$INSTALL_MOUNT"
  if findmnt -R "$INSTALL_MOUNT" >/dev/null 2>&1; then
    error "${INSTALL_MOUNT} 当前已挂载："
    findmnt -R "$INSTALL_MOUNT" || true
    die "请确认这些挂载不再需要并手动卸载后重试。"
  fi
  if find "$INSTALL_MOUNT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    die "${INSTALL_MOUNT} 不是空目录，请先移走其中内容。"
  fi
}

detect_microcode() {
  local vendor
  vendor=$(awk -F: '/vendor_id/{gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo)
  case $vendor in
    GenuineIntel) printf '%s|%s' intel-ucode intel-ucode.img ;;
    AuthenticAMD) printf '%s|%s' amd-ucode amd-ucode.img ;;
    *) printf '|' ;;
  esac
}

show_install_summary() {
  local disk=$1 microcode_package=$2 root_text
  [[ $ROOT_LOGIN == locked ]] && root_text='锁定（使用 sudo）' || root_text='独立密码'
  banner "安装配置确认"
  summary_row "目标磁盘" "$disk"
  summary_row "磁盘信息" "$(lsblk -dno SIZE,MODEL "$disk" | awk '{$1=$1; print}')"
  summary_row "分区方式" "UEFI/GPT；1 GiB ESP + 剩余空间 Btrfs"
  summary_row "Btrfs 子卷" "@ @home @log @cache @snapshots"
  summary_row "主机名" "$HOSTNAME_VALUE"
  summary_row "普通用户" "${USERNAME_VALUE}（wheel/sudo）"
  summary_row "root 登录" "$root_text"
  summary_row "系统语言" "$SYSTEM_LOCALE"
  summary_row "时区 / 键盘" "$TIMEZONE_VALUE / $KEYMAP_VALUE"
  summary_row "内核 / 引导" "linux / systemd-boot"
  summary_row "CPU 微码" "${microcode_package:-未识别，将跳过}"
  summary_row "网络 / SSH" "NetworkManager ${NETWORK_MODE} / OpenSSH"
  if [[ $NETWORK_MODE == static ]]; then
    summary_row "固定 IPv4" "$NETWORK_INTERFACE / $NETWORK_MAC / $NETWORK_ADDRESS"
    summary_row "网关 / DNS" "$NETWORK_GATEWAY / $NETWORK_DNS（IPv6 关闭）"
  fi
  summary_row "snapper-rollback" "$INSTALL_ROLLBACK_PACKAGE（1=安装，0=跳过）"
  summary_row "软件源" "$(mirror_profile_label "$MIRROR_PROFILE")（含 Arch Linux CN）"
  summary_row "桌面环境" "不安装"
  printf '\n'
  warn "继续后会永久删除 ${disk} 上的分区、文件系统和全部数据。"
  confirm "以上配置是否正确？" || die "用户取消安装。"
}

install_project_copy() {
  local target="$INSTALL_MOUNT/opt/arch-niri-deploy"
  rm -rf -- "$target"
  install -d "$target"
  tar --exclude=.git --exclude='*.zip' -C "$SCRIPT_DIR" -cf - . \
    | tar -C "$target" -xf -
  find "$target" -type f -name '*.sh' -exec chmod 0755 {} +
}

configure_installed_system() {
  local disk=$1 root_partition=$2 microcode_package=$3 microcode_image=$4
  local root_uuid
  root_uuid=$(blkid -s UUID -o value "$root_partition")
  [[ -n $root_uuid ]] || die "无法读取 Btrfs 根分区 UUID。"

  progress_step "配置语言、时区与主机身份"
  ln -sf "/usr/share/zoneinfo/${TIMEZONE_VALUE}" "$INSTALL_MOUNT/etc/localtime"
  arch-chroot "$INSTALL_MOUNT" hwclock --systohc
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$INSTALL_MOUNT/etc/locale.gen"
  sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' "$INSTALL_MOUNT/etc/locale.gen"
  arch-chroot "$INSTALL_MOUNT" locale-gen
  printf 'LANG=%s\n' "$SYSTEM_LOCALE" > "$INSTALL_MOUNT/etc/locale.conf"
  printf 'KEYMAP=%s\n' "$KEYMAP_VALUE" > "$INSTALL_MOUNT/etc/vconsole.conf"
  configure_console_locale "$INSTALL_MOUNT" "$SCRIPT_DIR"
  printf '%s\n' "$HOSTNAME_VALUE" > "$INSTALL_MOUNT/etc/hostname"
  {
    printf '127.0.0.1 localhost\n'
    printf '::1 localhost\n'
    printf '127.0.1.1 %s.localdomain %s\n' "$HOSTNAME_VALUE" "$HOSTNAME_VALUE"
  } > "$INSTALL_MOUNT/etc/hosts"

  progress_step "创建用户并配置 sudo"
  arch-chroot "$INSTALL_MOUNT" useradd -m -G wheel -s /bin/bash "$USERNAME_VALUE"
  printf '%s:%s\n' "$USERNAME_VALUE" "$USER_PASSWORD" | arch-chroot "$INSTALL_MOUNT" chpasswd
  USER_PASSWORD=''
  install -Dm 0440 /dev/null "$INSTALL_MOUNT/etc/sudoers.d/10-wheel"
  printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$INSTALL_MOUNT/etc/sudoers.d/10-wheel"
  if [[ $ROOT_LOGIN == password ]]; then
    printf 'root:%s\n' "$ROOT_PASSWORD" | arch-chroot "$INSTALL_MOUNT" chpasswd
    ROOT_PASSWORD=''
  else
    arch-chroot "$INSTALL_MOUNT" passwd -l root
  fi

  progress_step "安装并配置 systemd-boot"
  arch-chroot "$INSTALL_MOUNT" bootctl --esp-path=/boot install
  install -d "$INSTALL_MOUNT/boot/loader/entries"
  printf 'default arch.conf\ntimeout 3\nconsole-mode max\neditor no\n' \
    > "$INSTALL_MOUNT/boot/loader/loader.conf"
  {
    printf 'title   Arch Linux\nlinux   /vmlinuz-linux\n'
    [[ -n $microcode_image ]] && printf 'initrd  /%s\n' "$microcode_image"
    printf 'initrd  /initramfs-linux.img\n'
    printf 'options root=UUID=%s rw quiet\n' "$root_uuid"
  } > "$INSTALL_MOUNT/boot/loader/entries/arch.conf"
  arch-chroot "$INSTALL_MOUNT" mkinitcpio -P

  progress_step "启用网络、SSH 与维护服务"
  configure_target_network "$INSTALL_MOUNT"
  arch-chroot "$INSTALL_MOUNT" systemctl enable \
    NetworkManager sshd systemd-timesyncd.service fstrim.timer
  arch-chroot "$INSTALL_MOUNT" systemctl mask reflector.timer

  progress_step "部署安装项目并配置 Snapper"
  install_project_copy
  install_target_rollback_package "$INSTALL_MOUNT" "$USERNAME_VALUE" "$SCRIPT_DIR" "$root_uuid"
  arch-chroot "$INSTALL_MOUNT" bash -c \
    "source /opt/arch-niri-deploy/lib/snapshot.sh; configure_snapper_root '$USERNAME_VALUE'"
  # chroot 内没有运行 snapperd/系统 D-Bus，必须使用直接访问模式。
  arch-chroot "$INSTALL_MOUNT" bash -c \
    'source /opt/arch-niri-deploy/lib/snapshot.sh; create_initial_root_snapshot'

  ok "基础系统配置完成（CPU 微码：${microcode_package:-无}，磁盘：${disk}）。"
}

verify_installed_system() {
  local root_partition=$1 microcode_image=$2 root_uuid subvolume mountpoint
  local _profile _label official_mirror archlinuxcn_mirror _probe
  progress_step "执行安装后完整性检查"
  root_uuid=$(blkid -s UUID -o value "$root_partition")

  arch-chroot "$INSTALL_MOUNT" visudo -cf /etc/sudoers >/dev/null
  arch-chroot "$INSTALL_MOUNT" id "$USERNAME_VALUE" >/dev/null
  arch-chroot "$INSTALL_MOUNT" systemctl is-enabled NetworkManager >/dev/null
  arch-chroot "$INSTALL_MOUNT" systemctl is-enabled sshd >/dev/null
  arch-chroot "$INSTALL_MOUNT" systemctl is-enabled snapper-timeline.timer >/dev/null
  arch-chroot "$INSTALL_MOUNT" systemctl is-enabled snapper-cleanup.timer >/dev/null
  arch-chroot "$INSTALL_MOUNT" bash -c \
    'source /opt/arch-niri-deploy/lib/snapshot.sh; verify_initial_root_snapshot'
  arch-chroot "$INSTALL_MOUNT" pacman -Q archlinuxcn-keyring >/dev/null
  if (( INSTALL_ROLLBACK_PACKAGE )); then
    arch-chroot "$INSTALL_MOUNT" pacman -Q snapper-rollback >/dev/null
  fi
  arch-chroot "$INSTALL_MOUNT" locale -a | grep -Fxi 'en_US.utf8' >/dev/null \
    || die "英文 UTF-8 locale 未生成，TTY 语言回退不可用。"
  grep -Fxq 'Environment=LC_ALL=en_US.UTF-8' \
    "$INSTALL_MOUNT/etc/systemd/system/getty@.service.d/10-arch-niri-locale.conf" \
    || die "TTY 英文语言设置未写入。"

  [[ -s $INSTALL_MOUNT/etc/fstab ]] || die "fstab 为空。"
  awk '
    $1 !~ /^#/ && $2 == "/" && $3 == "btrfs" {
      found = 1
      count = split($4, options, ",")
      for (i = 1; i <= count; i++) {
        if (options[i] ~ /^subvol(=|id=)/) invalid = 1
      }
    }
    END { exit !(found && !invalid) }
  ' "$INSTALL_MOUNT/etc/fstab" \
    || die "fstab 根挂载不应固定 subvol；否则 Snapper rollback 无法生效。"
  for subvolume in @home @log @cache @snapshots; do
    case $subvolume in
      @home) mountpoint=/home ;;
      @log) mountpoint=/var/log ;;
      @cache) mountpoint=/var/cache ;;
      @snapshots) mountpoint=/.snapshots ;;
    esac
    awk -v target="$mountpoint" -v volume="$subvolume" '
      $1 !~ /^#/ && $2 == target && $3 == "btrfs" {
        count = split($4, options, ",")
        for (i = 1; i <= count; i++) {
          value = options[i]
          sub(/^subvol=\//, "subvol=", value)
          if (value == "subvol=" volume) found = 1
        }
      }
      END { exit !found }
    ' "$INSTALL_MOUNT/etc/fstab" \
      || die "fstab 缺少 ${subvolume} 到 ${mountpoint} 的挂载项。"
  done
  grep -Fq "$root_uuid" "$INSTALL_MOUNT/boot/loader/entries/arch.conf" \
    || die "启动项中的根分区 UUID 不正确。"
  if grep -Fq 'rootflags=' "$INSTALL_MOUNT/boot/loader/entries/arch.conf"; then
    die "启动项不应固定 rootflags；否则 Snapper rollback 无法切换默认子卷。"
  fi
  [[ -s $INSTALL_MOUNT/boot/vmlinuz-linux ]] || die "内核未写入 ESP。"
  [[ -s $INSTALL_MOUNT/boot/initramfs-linux.img ]] || die "initramfs 未生成。"
  [[ -s $INSTALL_MOUNT/boot/EFI/systemd/systemd-bootx64.efi ]] || die "systemd-boot EFI 文件缺失。"
  [[ -z $microcode_image || -s $INSTALL_MOUNT/boot/$microcode_image ]] \
    || die "CPU 微码镜像缺失：${microcode_image}"
  IFS='|' read -r _profile _label official_mirror archlinuxcn_mirror _probe \
    <<< "$(mirror_profile_values "$MIRROR_PROFILE")"
  grep -Fqx "Server = ${official_mirror}" "$INSTALL_MOUNT/etc/pacman.d/mirrorlist" \
    || die "新系统没有使用所选的 ${_label} Arch Linux 镜像。"
  if ! { grep -Fqx '[archlinuxcn]' "$INSTALL_MOUNT/etc/pacman.conf" \
    && grep -Fqx "Server = ${archlinuxcn_mirror}" "$INSTALL_MOUNT/etc/pacman.conf" \
    && grep -Fqx "$MIRROR_PROFILE" "$INSTALL_MOUNT${MIRROR_PROFILE_FILE}"; }; then
    die "新系统没有使用所选的 ${_label} Arch Linux CN 仓库。"
  fi
  for subvolume in @ @home @log @cache @snapshots; do
    btrfs subvolume list "$INSTALL_MOUNT" | awk '{print $9}' | grep -Fxq "$subvolume" \
      || die "缺少 Btrfs 子卷：${subvolume}"
  done
  verify_snapper_rollback_layout "$INSTALL_MOUNT"
  ok "分区、用户、服务、内核、引导、镜像与 Btrfs 子卷检查通过。"
}

save_install_log() {
  local target="$INSTALL_MOUNT/var/log/arch-niri-deploy/base-install.log"
  install -D -m 0600 "$LOG_FILE" "$target"
  info "安装日志已保存到新系统：/var/log/arch-niri-deploy/base-install.log"
}

main() {
  init_log
  banner "Arch Linux 基础系统安装"
  verify_install_environment
  info "该阶段只安装基础系统，不会安装 Niri 或其他桌面软件。"

  prompt_install_settings
  local disk esp_partition root_partition microcode_package microcode_image microcode_data
  disk=$(select_disk)
  microcode_data=$(detect_microcode)
  IFS='|' read -r microcode_package microcode_image <<< "$microcode_data"
  [[ -n $microcode_package ]] || warn "未识别 CPU 厂商，将不安装微码包。"
  show_install_summary "$disk" "$microcode_package"
  confirm_disk_destruction "$disk"

  progress_init 13
  progress_step "预检所选镜像、并行下载与密钥环（尚未清空磁盘）"
  configure_mirror_profile '' "$MIRROR_PROFILE"
  configure_pacman_parallel_downloads
  test_selected_mirror_connection "$MIRROR_PROFILE"
  info "正在刷新软件数据库并更新密钥环；失败会在清空磁盘前停止。"
  pacman -Syy --needed --noconfirm archlinux-keyring
  ok "软件数据库与 Arch Linux 密钥环已就绪。"
  prepare_rollback_source
  # 网络检查期间设备状态可能改变；清盘前再次检查挂载与安装介质。
  validate_target_disk "$disk" "$(detect_live_disk)"
  progress_step "清空磁盘并创建 GPT 分区"
  partition_disk "$disk"
  esp_partition=$(partition_path "$disk" 1)
  root_partition=$(partition_path "$disk" 2)

  progress_step "格式化 EFI 与 Btrfs 根分区"
  format_partitions "$disk"
  MOUNTED=1
  progress_step "创建并挂载 Btrfs 子卷"
  create_subvolumes "$root_partition"
  mount_subvolumes "$root_partition" "$esp_partition"

  local -a bootstrap_packages=("${BASE_PACKAGES[@]}")
  if (( INSTALL_ROLLBACK_PACKAGE )); then
    bootstrap_packages+=(base-devel)
  fi
  [[ -n $microcode_package ]] && bootstrap_packages+=("$microcode_package")
  progress_step "下载并安装基础软件包（Pacman 会显示包级进度）"
  info "即将从所选镜像下载 ${#bootstrap_packages[@]} 个基础包；下载后还会在本地解压安装。"
  pacstrap -K "$INSTALL_MOUNT" "${bootstrap_packages[@]}"
  ok "基础软件包下载与安装完成。"

  progress_step "写入新系统所选官方/CN 仓库、并行下载与 fstab"
  configure_mirror_profile "$INSTALL_MOUNT" "$MIRROR_PROFILE"
  configure_pacman_parallel_downloads "$INSTALL_MOUNT"
  genfstab -U "$INSTALL_MOUNT" > "$INSTALL_MOUNT/etc/fstab"
  configure_root_fstab_for_snapper_rollback "$INSTALL_MOUNT/etc/fstab"
  configure_installed_system "$disk" "$root_partition" "$microcode_package" "$microcode_image"
  verify_installed_system "$root_partition" "$microcode_image"
  save_install_log

  progress_step "同步数据并安全卸载目标系统"
  unmount_target
  progress_done "基础系统安装完成"

  banner "安装完成"
  ok "已得到纯 Arch 基础系统：网络、SSH、sudo、Btrfs/Snapper 和 systemd-boot 均已配置。"
  info "目标系统已经卸载，现在可以执行 reboot；登录后运行：/opt/arch-niri-deploy/install-niri.sh"
}

main "$@"
