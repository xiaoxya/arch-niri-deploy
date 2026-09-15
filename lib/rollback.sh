#!/usr/bin/env bash
# Conservative checks for this project's systemd-boot + flat Btrfs layout.
set -Eeuo pipefail

rollback_error() { printf '回滚检查失败：%s\n' "$*" >&2; return 1; }

rollback_subvolume_id() {
  LC_ALL=C btrfs subvolume show "$1" | awk '$1 == "Subvolume" && $2 == "ID:" {print $3}'
}

rollback_default_id() {
  LC_ALL=C btrfs subvolume get-default / | awk '$1 == "ID" {print $2}'
}

rollback_package_state_valid() {
  local lock="$1/var/lib/pacman/db.lck"
  [[ ! -e $lock && ! -L $lock ]] && return 0
  # Our own guard lock may be captured in Snapper's automatic rollback backup.
  # Other locks suggest a snapshot taken during a package transaction.
  [[ ! -L $lock && -f $lock && $(< "$lock") == 'arch-niri-deploy rollback guard v1' ]]
}

rollback_root_fstab_valid() {
  awk -v uuid="$2" '
    $1 !~ /^#/ && $2 == "/" {
      count++
      if ($1 != "UUID=" uuid || $3 != "btrfs") bad = 1
      n = split($4, opts, ",")
      for (i=1; i<=n; i++) if (opts[i] ~ /^subvol(=|id=)/ || opts[i] == "ro") bad = 1
    }
    END { exit !(count == 1 && !bad) }
  ' "$1"
}

rollback_mount_rows() {
  awk '$1 !~ /^#/ && NF >= 4 {print $1, $2, $3, $4}' "$1" | LC_ALL=C sort
}

rollback_options_valid() {
  local options=$1 uuid=$2 word roots=0 writable=0
  local -a words=()
  read -r -a words <<< "$options"
  for word in "${words[@]}"; do
    case $word in
      root=*) [[ $word == "root=UUID=$uuid" ]] || return 1; roots=$((roots+1)) ;;
      rw) writable=1 ;;
      ro|rootflags=*|init=*|rd.break*) return 1 ;;
    esac
  done
  (( roots == 1 && writable == 1 ))
}

rollback_kernel_check() {
  local target=$1 current_root=${2:-/} boot_root=${3:-/boot} kernel_version kernel_image listing versions
  local -a candidates=()
  for kernel_image in "$current_root"/usr/lib/modules/*/vmlinuz; do
    [[ -f $kernel_image ]] || continue
    if cmp -s "$boot_root/vmlinuz-linux" "$kernel_image"; then candidates+=("$kernel_image"); fi
  done
  (( ${#candidates[@]} == 1 )) \
    || { rollback_error 'ESP 内核与当前模块目录不一致或无法唯一识别；先修复内核。'; return 1; }
  kernel_version=${candidates[0]%/vmlinuz}
  kernel_version=${kernel_version##*/}
  if [[ ! -f $target/usr/lib/modules/$kernel_version/vmlinuz ]] \
    || ! cmp -s "$boot_root/vmlinuz-linux" "$target/usr/lib/modules/$kernel_version/vmlinuz"; then
    rollback_error '目标内核与 /boot 不一致。禁止在线跨内核回滚；请按 RECOVERY.md 从 ISO 恢复。'
    return 1
  fi
  # Catch same-version rebuilds and NVIDIA/DKMS module changes, too.
  diff -qr --no-dereference -- "$current_root/usr/lib/modules/$kernel_version" "$target/usr/lib/modules/$kernel_version" >/dev/null \
    || { rollback_error '目标内核模块（含 DKMS）与当前系统不同，需要离线重建 initramfs。'; return 1; }
  listing=$(lsinitcpio --list "$boot_root/initramfs-linux.img") || return 1
  versions=$(awk -F/ '{sub(/^\.\//, ""); if ($1=="usr" && $2=="lib" && $3=="modules" && $4!="") print $4}' \
    <<< "$listing" | LC_ALL=C sort -u)
  [[ $versions == "$kernel_version" ]] \
    || { rollback_error 'initramfs 内核版本无法确认或不一致；请先运行 mkinitcpio -P。'; return 1; }
}

rollback_boot_check() {
  local uuid=$1 entries entry options initrd
  [[ $(findmnt -nro FSTYPE --mountpoint /sys/firmware/efi/efivars) == efivarfs ]] \
    || { rollback_error '无法读取 EFI 启动变量，不能确认下次默认启动项。'; return 1; }
  [[ $(findmnt -nro FSTYPE --mountpoint /boot) == vfat ]] \
    || { rollback_error '/boot 必须是已挂载的 ESP。'; return 1; }
  [[ $(bootctl --print-esp-path) == /boot ]] || return 1
  entries=$(bootctl --json=short list) || return 1
  entry=$(jq -cer '[.[] | select(.isDefault == true)] | if length == 1 then .[0] else error("ambiguous default") end' <<< "$entries") || return 1
  jq -e '.id == "arch.conf" and .path == "/boot/loader/entries/arch.conf" and .linux == "/vmlinuz-linux" and ((.extras // []) | length == 0) and ((.addons // []) | length == 0) and ((.cmdline // .options) == .options)' \
    <<< "$entry" >/dev/null \
    || { rollback_error '实际默认启动项不是本项目的 arch.conf，或存在启动附加配置。'; return 1; }
  options=$(jq -er '.options' <<< "$entry") || return 1
  rollback_options_valid "$options" "$uuid" \
    || { rollback_error '默认启动项固定子卷、只读启动或使用错误的根 UUID。'; return 1; }
  jq -e '(.initrd | map(select(. == "/initramfs-linux.img")) | length) == 1' <<< "$entry" >/dev/null || return 1
  while IFS= read -r initrd; do
    case $initrd in /initramfs-linux.img|/intel-ucode.img|/amd-ucode.img) ;; *) return 1 ;; esac
    [[ -s /boot$initrd ]] || return 1
  done < <(jq -r '.initrd[]' <<< "$entry")
  [[ -s /boot/vmlinuz-linux ]] || return 1
}

rollback_preflight() {
  local number=$1 target="/.snapshots/$1/snapshot" current_id default_id uuid point volume source
  [[ $number =~ ^[1-9][0-9]*$ ]] || return 1
  [[ $(findmnt -nro FSTYPE /) == btrfs ]] || return 1
  [[ $(btrfs property get -ts / ro) == ro=false ]] || return 1
  current_id=$(rollback_subvolume_id /) || return 1
  default_id=$(rollback_default_id) || return 1
  [[ $current_id =~ ^[0-9]+$ && $current_id != 5 && $current_id == "$default_id" ]] \
    || { rollback_error '当前根和默认根不同：可能已有等待重启的回滚，或尚未完成旧布局迁移。'; return 1; }
  uuid=$(findmnt -nro UUID /) || return 1
  [[ $uuid =~ ^[[:xdigit:]-]+$ ]] || return 1
  for point in /home /var/log /var/cache /.snapshots; do
    case $point in /home) volume=@home ;; /var/log) volume=@log ;; /var/cache) volume=@cache ;; /.snapshots) volume=@snapshots ;; esac
    [[ $(findmnt -nro UUID --mountpoint "$point") == "$uuid" \
      && $(findmnt -nro FSROOT --mountpoint "$point") == "/$volume" ]] \
      || { rollback_error "$point 不是本项目的独立子卷。"; return 1; }
  done
  [[ -f /etc/snapper/configs/root ]] || return 1
  grep -Eq '^SUBVOLUME="/"$' /etc/snapper/configs/root || return 1
  [[ $(btrfs property get -ts "$target" ro) == ro=true ]] \
    || { rollback_error '请选择存在的只读根快照，不能使用活动可写根。'; return 1; }
  source=$(realpath -e -- "$target") || return 1
  [[ $source == "$target" ]] || return 1
  [[ $(findmnt -nro UUID --target "$target") == "$uuid" ]] || return 1
  rollback_package_state_valid "$target" \
    || { rollback_error '目标包含软件包事务锁，可能是在安装中途创建的快照；请离线检查包数据库。'; return 1; }
  if ! rollback_root_fstab_valid /etc/fstab "$uuid" \
    || ! rollback_root_fstab_valid "$target/etc/fstab" "$uuid"; then
    rollback_error '当前或目标 fstab 固定子卷/使用其他布局。旧快照请离线恢复。'
    return 1
  fi
  [[ $(rollback_mount_rows /etc/fstab) == "$(rollback_mount_rows "$target/etc/fstab")" ]] \
    || { rollback_error '目标 fstab 挂载定义与当前系统不同，请离线核对。'; return 1; }
  rollback_boot_check "$uuid" || return 1
  rollback_kernel_check "$target" || return 1
}

rollback_verify_result() {
  local number=$1 source_uuid=$2 before_id=$3 target="/.snapshots/$1/snapshot" new_id parent_uuid
  [[ $number =~ ^[1-9][0-9]*$ ]] || return 1
  new_id=$(rollback_subvolume_id "$target") || return 1
  [[ $new_id =~ ^[0-9]+$ && $new_id != "$before_id" && $new_id == "$(rollback_default_id)" ]] || return 1
  [[ $(btrfs property get -ts "$target" ro) == ro=false ]] || return 1
  parent_uuid=$(LC_ALL=C btrfs subvolume show "$target" | awk '$1 == "Parent" && $2 == "UUID:" {print $3}') || return 1
  [[ $parent_uuid == "$source_uuid" ]] || return 1
}
