#!/usr/bin/env bash
set -Eeuo pipefail

select_disk() {
  local -a disks=()
  local selection index disk size model transport serial
  mapfile -t disks < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" {print $1}')
  ((${#disks[@]} > 0)) || die "未发现可用磁盘。"

  info "已扫描到以下本地磁盘：" >&2
  printf '\n  %-4s %-16s %-10s %-24s %-8s %s\n' \
    "编号" "设备" "容量" "型号" "接口" "序列号" >&2
  printf '  %s\n' '────────────────────────────────────────────────────────────────────────────' >&2
  for index in "${!disks[@]}"; do
    disk=${disks[$index]}
    size=$(lsblk -dno SIZE "$disk" | awk '{$1=$1; print}')
    model=$(lsblk -dno MODEL "$disk" | awk '{$1=$1; print}')
    transport=$(lsblk -dno TRAN "$disk" | awk '{$1=$1; print}')
    serial=$(lsblk -dno SERIAL "$disk" | awk '{$1=$1; print}')
    printf '  [%-2d] %-16s %-10s %-24s %-8s %s\n' \
      "$((index + 1))" "$disk" "${size:--}" "${model:--}" "${transport:--}" "${serial:--}" >&2
  done
  printf '\n' >&2

  while true; do
    read -r -p "请选择目标磁盘编号 [1-${#disks[@]}]：" selection
    if [[ $selection =~ ^[0-9]+$ ]] \
      && (( selection >= 1 && selection <= ${#disks[@]} )); then
      printf '%s\n' "${disks[$((selection - 1))]}"
      return 0
    fi
    warn "无效选择，请输入 1 到 ${#disks[@]} 之间的编号。" >&2
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
