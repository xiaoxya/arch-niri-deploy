#!/usr/bin/env bash
set -Eeuo pipefail

detect_live_disk() {
  local source parent
  source=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
  [[ -n $source ]] || source=$(findmnt -no SOURCE / 2>/dev/null || true)
  [[ $source == /dev/* ]] || return 0
  source=$(readlink -f -- "$source")
  parent=$(lsblk -srnpo NAME,TYPE "$source" 2>/dev/null \
    | awk '$2 == "disk" {print $1; exit}')
  if [[ -n $parent ]]; then
    printf '%s\n' "$parent"
  elif [[ $(lsblk -dno TYPE "$source" 2>/dev/null || true) == disk ]]; then
    printf '%s\n' "$source"
  fi
}

validate_target_disk() {
  local disk=$1 live_disk=$2 size_bytes read_only swap_source
  [[ -b $disk ]] || die "目标不是块设备：${disk}"
  [[ $(lsblk -dno TYPE "$disk") == disk ]] || die "目标不是整块磁盘：${disk}"
  [[ -z $live_disk || $disk != "$live_disk" ]] || die "不能选择当前 Arch 安装介质：${disk}"

  read_only=$(lsblk -dno RO "$disk" | awk '{$1=$1; print}')
  [[ $read_only == 0 ]] || die "目标磁盘为只读设备：${disk}"
  size_bytes=$(lsblk -bdno SIZE "$disk" | awk '{$1=$1; print}')
  (( size_bytes >= 16 * 1024 * 1024 * 1024 )) || die "目标磁盘至少需要 16 GiB。"

  if lsblk -nrpo MOUNTPOINTS "$disk" | awk 'NF {found=1} END {exit !found}'; then
    error "目标磁盘或其分区仍处于挂载状态："
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$disk"
    die "请先卸载目标磁盘上的全部分区。"
  fi
  while IFS= read -r swap_source; do
    [[ -n $swap_source ]] || continue
    if lsblk -srnpo NAME "$swap_source" 2>/dev/null | grep -Fxq "$disk"; then
      die "目标磁盘上存在活动交换分区，请先执行 swapoff。"
    fi
  done < <(swapon --noheadings --raw --show=NAME 2>/dev/null || true)
}

select_disk() {
  local -a disks=()
  local selection index disk size model transport serial live_disk table line separator
  live_disk=$(detect_live_disk)
  mapfile -t disks < <(
    lsblk -dpno NAME,TYPE | awk '$2 == "disk" {print $1}' \
      | while IFS= read -r disk; do
          if [[ -z $live_disk || $disk != "$live_disk" ]]; then
            printf '%s\n' "$disk"
          fi
        done
  )
  ((${#disks[@]} > 0)) || die "未发现可用磁盘。"

  table=''
  if [[ -n $live_disk ]]; then
    printf -v line '%s!%s 已自动排除当前安装介质：%s\n' \
      "$C_YELLOW" "$C_RESET" "$live_disk"
    table+=$line
  fi
  printf -v line '%sℹ%s 已扫描到以下本地磁盘：\n\n' "$C_BLUE" "$C_RESET"
  table+=$line
  # 中文字符在不同终端中的 printf 字段宽度计算并不一致，表头使用按
  # 显示列预先排好的空格；数据行只含 ASCII，可继续使用定宽格式。
  printf -v line '  编号 设备             容量       型号                     接口     序列号\n'
  table+=$line
  printf -v separator '%*s' 96 ''
  separator=${separator// /─}
  printf -v line '  %s\n' "$separator"
  table+=$line
  for index in "${!disks[@]}"; do
    disk=${disks[$index]}
    size=$(lsblk -dno SIZE "$disk" | awk '{$1=$1; print}')
    model=$(lsblk -dno MODEL "$disk" | awk '{$1=$1; print}')
    transport=$(lsblk -dno TRAN "$disk" | awk '{$1=$1; print}')
    serial=$(lsblk -dno SERIAL "$disk" | awk '{$1=$1; print}')
    model=${model:--}
    printf -v line '  [%-2d] %-16s %-10s %-24s %-8s %s\n' \
      "$((index + 1))" "$disk" "${size:--}" "${model:0:24}" \
      "${transport:--}" "${serial:--}"
    table+=$line
  done
  table+=$'\n'
  tty_log_block "$table"

  while true; do
    printf '请选择目标磁盘编号 [1-%s]：' "${#disks[@]}" >/dev/tty
    IFS= read -r selection </dev/tty
    if [[ $selection =~ ^[0-9]+$ ]] \
      && (( selection >= 1 && selection <= ${#disks[@]} )); then
      disk=$(readlink -f -- "${disks[$((selection - 1))]}")
      validate_target_disk "$disk" "$live_disk"
      printf '%s\n' "$disk"
      return 0
    fi
    printf -v line '%s!%s 无效选择，请输入 1 到 %d 之间的编号。\n' \
      "$C_YELLOW" "$C_RESET" "${#disks[@]}"
    tty_log_block "$line"
  done
}

confirm_disk_destruction() {
  local disk=$1
  local first second token
  warn "即将永久清空以下整块磁盘："
  lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS "$disk"
  printf '\n'
  # 让提示和读取由同一个 Bash 内建直接操作 TTY，避免部分远程终端把
  # 单独 printf 的提示与后续输入拆成两行。
  IFS= read -r -p "第一次确认：请输入完整磁盘路径 ${disk}：" first </dev/tty 2>/dev/tty
  [[ $first == "$disk" ]] || die "磁盘路径不匹配，已取消。"
  token=$(printf '%04d' "$((RANDOM % 10000))")
  IFS= read -r -p "第二次确认：请输入 ERASE-${token}：" second </dev/tty 2>/dev/tty
  [[ $second == "ERASE-${token}" ]] || die "确认码不匹配，已取消。"
}

partition_path() {
  local disk=$1 number=$2
  local partition attempt
  for ((attempt = 1; attempt <= 20; attempt++)); do
    partition=$(lsblk -nrpo NAME,PARTN "$disk" \
      | awk -v n="$number" '$2 == n {print $1; exit}')
    if [[ -n $partition && -b $partition ]]; then
      printf '%s' "$partition"
      return 0
    fi
    udevadm settle || true
    sleep 0.25
  done
  die "等待 ${disk} 的第 ${number} 个分区超时。"
}

partition_disk() {
  local disk=$1
  info "清理旧签名并创建 GPT 分区表……"
  wipefs --all --force "$disk"
  sgdisk --zap-all "$disk"
  sgdisk --new=1:0:+1GiB --typecode=1:ef00 --change-name=1:'EFI System' "$disk"
  sgdisk --new=2:0:0 --typecode=2:8304 --change-name=2:'Arch Linux Root' "$disk"
  info "正在等待内核识别新分区……"
  partprobe "$disk"
  udevadm settle
  partition_path "$disk" 1 >/dev/null
  partition_path "$disk" 2 >/dev/null
}

format_partitions() {
  local disk=$1
  local esp root
  esp=$(partition_path "$disk" 1)
  root=$(partition_path "$disk" 2)
  info "正在格式化 EFI 分区：${esp}"
  mkfs.fat -F 32 -n ARCH_EFI "$esp"
  info "正在创建 Btrfs 文件系统：${root}（会执行完整 TRIM；慢盘或 USB 磁盘可能需要数分钟）"
  mkfs.btrfs -f -L ARCH_ROOT "$root"
  ok "EFI 与 Btrfs 文件系统已创建。"
}
