#!/usr/bin/env bash
set -Eeuo pipefail

readonly BTRFS_OPTIONS='noatime,compress=zstd:1,ssd,discard=async,space_cache=v2'

create_subvolumes() {
  local root_partition=$1
  mount "$root_partition" /mnt
  local subvolume
  for subvolume in @ @home @log @cache @snapshots; do
    if ! btrfs subvolume list /mnt | awk '{print $9}' | grep -Fxq "$subvolume"; then
      btrfs subvolume create "/mnt/${subvolume}"
    fi
  done
  umount /mnt
}

mount_subvolumes() {
  local root_partition=$1 esp_partition=$2
  mount -o "${BTRFS_OPTIONS},subvol=@" "$root_partition" /mnt
  install -d /mnt/{boot,home,var/log,var/cache,.snapshots}
  mount -o "${BTRFS_OPTIONS},subvol=@home" "$root_partition" /mnt/home
  mount -o "${BTRFS_OPTIONS},subvol=@log" "$root_partition" /mnt/var/log
  mount -o "${BTRFS_OPTIONS},subvol=@cache" "$root_partition" /mnt/var/cache
  mount -o "${BTRFS_OPTIONS},subvol=@snapshots" "$root_partition" /mnt/.snapshots
  mount "$esp_partition" /mnt/boot
}

verify_btrfs_layout() {
  local mountpoint=${1:-/}
  findmnt -no FSTYPE "$mountpoint" | grep -Fxq btrfs || die "${mountpoint} 不是 Btrfs。"
}
