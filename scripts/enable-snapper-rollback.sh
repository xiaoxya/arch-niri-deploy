#!/usr/bin/env bash
set -Eeuo pipefail

readonly BACKUP_PREFIX='/root/arch-niri-deploy-snapper-backup'
MIGRATION_ARMED=0
MIGRATION_BACKUP=''
MIGRATION_OLD_DEFAULT=''

migration_cleanup() {
  local status=$? entry failed=0
  trap - EXIT INT TERM
  if (( MIGRATION_ARMED )); then
    status=1
    install -m 0644 "$MIGRATION_BACKUP/fstab" /etc/fstab || failed=1
    for entry in "$MIGRATION_BACKUP"/loader-entries/*.conf; do
      install -m 0644 "$entry" "/boot/loader/entries/$(basename -- "$entry")" || failed=1
    done
    btrfs subvolume set-default "$MIGRATION_OLD_DEFAULT" / || failed=1
    [[ $(btrfs subvolume get-default / | awk '{print $2}') == "$MIGRATION_OLD_DEFAULT" ]] || failed=1
    sync || failed=1
    if (( failed )); then
      printf '严重错误：迁移恢复不完整，请勿重启！备份：%s\n' "$MIGRATION_BACKUP" >&2
    else
      printf '迁移失败；原 fstab、启动项和默认子卷已恢复。备份：%s\n' "$MIGRATION_BACKUP" >&2
    fi
  fi
  exit "$status"
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

require_command() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 \
      || die "缺少命令：${command_name}"
  done
}

normalize_root_fstab() {
  local fstab=/etc/fstab temporary
  temporary=$(mktemp /etc/fstab.arch-niri-deploy.XXXXXX)
  if ! awk '
    $1 !~ /^#/ && $2 == "/" && $3 == "btrfs" {
      found = 1
      count = split($4, options, ",")
      normalized = ""
      for (i = 1; i <= count; i++) {
        if (options[i] ~ /^subvol(=|id=)/) continue
        normalized = normalized (normalized == "" ? "" : ",") options[i]
      }
      $4 = (normalized == "" ? "defaults" : normalized)
    }
    { print }
    END { exit !found }
  ' "$fstab" > "$temporary"; then
    rm -f -- "$temporary"
    die '无法在 /etc/fstab 中找到 Btrfs 根挂载项。'
  fi
  install -m 0644 "$temporary" "$fstab"
  rm -f -- "$temporary"
}

main() {
  local root_source root_device root_subvolume_id default_subvolume_id
  local backup_dir timestamp entry
  local -a boot_entries=()

  (( EUID == 0 )) || die '请使用 sudo 运行此脚本。'
  require_command awk btrfs date findmnt install mktemp sed sync flock
  export LC_ALL=C
  exec 9>/run/lock/arch-niri-rollback.lock
  flock -n 9 || die '另一个回滚或迁移操作正在进行。'
  [[ $(findmnt -no FSTYPE /) == btrfs ]] || die '当前根目录不是 Btrfs。'
  [[ -f /etc/snapper/configs/root ]] || die '未找到 Snapper root 配置。'

  root_source=$(findmnt -nro SOURCE /)
  root_device=${root_source%%\[*}
  [[ -b $root_device ]] || die "无法解析根分区设备：${root_source}"
  root_subvolume_id=$(btrfs subvolume show / \
    | awk '$1 == "Subvolume" && $2 == "ID:" {print $3; exit}')
  [[ $root_subvolume_id =~ ^[0-9]+$ && $root_subvolume_id != 5 ]] \
    || die '当前根目录不是可用于回滚的 Btrfs 子卷。'
  [[ $(btrfs property get -ts / ro) == ro=false ]] || die '当前根子卷必须可写。'
  MIGRATION_OLD_DEFAULT=$(btrfs subvolume get-default / | awk '{print $2}')
  [[ $MIGRATION_OLD_DEFAULT =~ ^[0-9]+$ ]] || die '默认子卷不可读。'
  [[ $MIGRATION_OLD_DEFAULT == 5 || $MIGRATION_OLD_DEFAULT == "$root_subvolume_id" ]] \
    || die '已有另一个默认根（可能是等待重启的回滚）；拒绝覆盖。'
  [[ $(findmnt -nro FSTYPE --mountpoint /boot) == vfat ]] || die '/boot 未正确挂载为 ESP。'

  [[ -f /boot/loader/entries/arch.conf ]] \
    || die '未找到本项目的 systemd-boot 主启动项：/boot/loader/entries/arch.conf'
  for entry in /boot/loader/entries/arch.conf /boot/loader/entries/arch-fallback.conf; do
    if [[ -f $entry ]]; then
      boot_entries+=("$entry")
    fi
  done

  printf '%s\n' '此工具会：'
  printf '%s\n' '  1. 将当前根子卷设为 Btrfs 默认子卷；'
  printf '%s\n' '  2. 移除根目录 fstab 与 systemd-boot 启动项中的固定子卷参数；'
  printf '%s\n' '  3. 在 /root 下备份原配置。'
  printf '确认继续请输入 ENABLE-SNAPPER-ROLLBACK：' >/dev/tty
  local confirmation
  IFS= read -r confirmation </dev/tty
  [[ $confirmation == ENABLE-SNAPPER-ROLLBACK ]] || die '确认文本不匹配，未修改系统。'

  timestamp=$(date +%Y%m%d-%H%M%S)
  backup_dir="${BACKUP_PREFIX}-${timestamp}"
  [[ ! -e $backup_dir ]] || die '备份目录已存在，请稍后重试。'
  install -d -m 0700 "$backup_dir/loader-entries"
  install -m 0644 /etc/fstab "$backup_dir/fstab"
  for entry in "${boot_entries[@]}"; do
    install -m 0644 "$entry" "$backup_dir/loader-entries/$(basename -- "$entry")"
  done
  printf '%s\n' "$MIGRATION_OLD_DEFAULT" > "$backup_dir/default-subvolume-id"
  MIGRATION_BACKUP=$backup_dir
  trap migration_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  MIGRATION_ARMED=1
  btrfs subvolume set-default "$root_subvolume_id" /
  default_subvolume_id=$(btrfs subvolume get-default / \
    | awk '{print $2; exit}')
  [[ $default_subvolume_id == "$root_subvolume_id" ]] \
    || die 'Btrfs 默认子卷验证失败，已停止。'

  normalize_root_fstab
  sed -Ei 's/[[:space:]]+rootflags=[^[:space:]]+//g' "${boot_entries[@]}"
  if grep -Fq 'rootflags=' "${boot_entries[@]}"; then
    die '启动项仍包含 rootflags，请从备份中恢复后检查。'
  fi
  sync
  MIGRATION_ARMED=0

  printf '配置完成。原文件备份在：%s\n' "$backup_dir"
  printf '%s\n' '请重启一次并创建新快照，再使用 rollback-snapshot.sh --check 快照号。旧快照中的 fstab 不会被改写。'
}

main "$@"
