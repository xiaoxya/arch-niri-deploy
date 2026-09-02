#!/usr/bin/env bash
set -Eeuo pipefail

list_install_disks() {
  lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$NF == "disk" {print}'
}

select_disk() {
  local -a disks=()
  local line selection
  mapfile -t disks < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" {print $1}')
  ((${#disks[@]} > 0)) || die "未发现可用磁盘。"

  info "可用磁盘："
  list_install_disks
  while true; do
    read -r -p "输入目标磁盘完整路径（例如 /dev/nvme0n1）：" selection
    for line in "${disks[@]}"; do
      if [[ $selection == "$line" ]]; then
        printf '%s' "$selection"
        return 0
      fi
    done
    warn "请输入上方列表中的完整磁盘路径。"
  done
}

confirm_disk_destruction() {
  local disk=$1
  local first second token
  warn "即将永久清空以下整块磁盘："
  lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS "$disk"
  printf '\n'
  read -r -p "第一次确认：请输入完整磁盘路径 ${disk}：" first
  [[ $first == "$disk" ]] || die "磁盘路径不匹配，已取消。"
  token=$(printf '%04d' "$((RANDOM % 10000))")
  read -r -p "第二次确认：请输入 ERASE-${token}：" second
  [[ $second == "ERASE-${token}" ]] || die "确认码不匹配，已取消。"
}

partition_path() {
  local disk=$1 number=$2
  if [[ $disk =~ (nvme|mmcblk|loop) ]]; then
    printf '%sp%s' "$disk" "$number"
  else
    printf '%s%s' "$disk" "$number"
  fi
}

partition_disk() {
  local disk=$1
  info "清理旧签名并创建 GPT 分区表……"
  swapoff --all || true
  umount -R /mnt 2>/dev/null || true
  wipefs --all --force "$disk"
  sgdisk --zap-all "$disk"
  sgdisk --new=1:0:+1GiB --typecode=1:ef00 --change-name=1:'EFI System' "$disk"
  sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:'Arch Linux' "$disk"
  partprobe "$disk"
  udevadm settle
}

format_partitions() {
  local disk=$1
  local esp root
  esp=$(partition_path "$disk" 1)
  root=$(partition_path "$disk" 2)
  mkfs.fat -F 32 -n ARCH_EFI "$esp"
  mkfs.btrfs -f -L ARCH_ROOT "$root"
}
