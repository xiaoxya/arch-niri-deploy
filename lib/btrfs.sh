#!/usr/bin/env bash
set -Eeuo pipefail

readonly BTRFS_OPTIONS='noatime,compress=zstd:1,ssd,discard=async,space_cache=v2'

create_subvolumes() {
  local root_partition=$1
  local subvolume root_subvolume_id
  info "正在挂载 Btrfs 顶层并创建子卷……"
  mount -o subvolid=5 "$root_partition" /mnt
  for subvolume in @ @home @log @cache @snapshots; do
    if ! btrfs subvolume list /mnt | awk '{print $9}' | grep -Fxq "$subvolume"; then
      btrfs subvolume create "/mnt/${subvolume}"
    fi
  done
  root_subvolume_id=$(btrfs subvolume show /mnt/@ \
    | awk '$1 == "Subvolume" && $2 == "ID:" {print $3; exit}')
  [[ $root_subvolume_id =~ ^[0-9]+$ ]] \
    || die "无法读取 @ 根子卷的 ID。"
  # Snapper 的 rollback 依赖 Btrfs 默认子卷。初始默认值必须是 @，而不是
  # Btrfs 顶层子卷（ID 5）；后续 rollback 会将默认值切换到新的可写快照。
  btrfs subvolume set-default "$root_subvolume_id" /mnt
  umount /mnt
  ok "Btrfs 子卷已创建，@ 已设为默认根子卷。"
}

mount_subvolumes() {
  local root_partition=$1 esp_partition=$2
  info "正在挂载根目录、Home、日志、缓存、快照与 EFI 分区……"
  mount -o "${BTRFS_OPTIONS},subvol=@" "$root_partition" /mnt
  install -d /mnt/{boot,home,var/log,var/cache,.snapshots}
  mount -o "${BTRFS_OPTIONS},subvol=@home" "$root_partition" /mnt/home
  mount -o "${BTRFS_OPTIONS},subvol=@log" "$root_partition" /mnt/var/log
  mount -o "${BTRFS_OPTIONS},subvol=@cache" "$root_partition" /mnt/var/cache
  mount -o "${BTRFS_OPTIONS},subvol=@snapshots" "$root_partition" /mnt/.snapshots
  mount "$esp_partition" /mnt/boot
  ok "目标系统文件系统已挂载到 /mnt。"
}

verify_btrfs_layout() {
  local mountpoint=${1:-/}
  findmnt -no FSTYPE "$mountpoint" | grep -Fxq btrfs || die "${mountpoint} 不是 Btrfs。"
}

configure_root_fstab_for_snapper_rollback() {
  local fstab=$1 temporary
  [[ -f $fstab ]] || die "找不到 fstab：${fstab}"
  temporary=$(mktemp "${fstab}.arch-niri-deploy.XXXXXX")
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
    die "fstab 中没有可用于 Snapper 回滚的 Btrfs 根挂载项。"
  fi
  install -m 0644 "$temporary" "$fstab"
  rm -f -- "$temporary"
}

verify_snapper_rollback_layout() {
  local mountpoint=${1:-/}
  local root_subvolume_id default_subvolume_id
  root_subvolume_id=$(btrfs subvolume show "$mountpoint" \
    | awk '$1 == "Subvolume" && $2 == "ID:" {print $3; exit}')
  default_subvolume_id=$(btrfs subvolume get-default "$mountpoint" \
    | awk '{print $2; exit}')
  [[ $root_subvolume_id =~ ^[0-9]+$ ]] \
    || die "无法读取当前根子卷 ID。"
  [[ $default_subvolume_id =~ ^[0-9]+$ ]] \
    || die "无法读取 Btrfs 默认子卷 ID。"
  [[ $root_subvolume_id == "$default_subvolume_id" ]] \
    || die "Btrfs 默认子卷不是当前 @ 根子卷，Snapper rollback 无法可靠启动。"
}
