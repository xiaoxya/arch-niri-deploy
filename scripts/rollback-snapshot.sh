#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/rollback.sh
source "$PROJECT_DIR/lib/rollback.sh"

ROLLBACK_ARMED=0
ROLLBACK_BEFORE_ID=''
ROLLBACK_PACMAN_LOCK=0

rollback_cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if (( ROLLBACK_ARMED )); then
    status=1
    printf '回滚未通过完整校验；尝试恢复原默认子卷 %s。\n' "$ROLLBACK_BEFORE_ID" >&2
    if btrfs subvolume set-default "$ROLLBACK_BEFORE_ID" / \
      && [[ $(rollback_default_id) == "$ROLLBACK_BEFORE_ID" ]] && sync; then
      printf '已恢复原默认子卷；新快照保留供检查。此操作不会撤销外部钩子对 ESP 的修改；请排除失败原因后再重启。\n' >&2
    else
      printf '严重错误：无法恢复默认子卷！请勿重启，请按 RECOVERY.md 从 Arch ISO 修复。\n' >&2
    fi
  fi
  if (( ROLLBACK_PACMAN_LOCK )); then rm -f -- /var/lib/pacman/db.lck; fi
  exit "$status"
}

rollback_boot_hash() {
  local -a files=(/boot/loader/entries/arch.conf /boot/vmlinuz-linux /boot/initramfs-linux.img)
  local image
  for image in /boot/intel-ucode.img /boot/amd-ucode.img; do
    if [[ -e $image ]]; then files+=("$image"); fi
  done
  sha256sum "${files[@]}"
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

main() {
  local snapshot_number='' check_only=0 argument
  local confirmation after_id rollback_output new_number source_uuid boot_hash log_file
  for argument in "$@"; do
    case $argument in
      --check|--dry-run) check_only=1 ;;
      --help|-h) printf '用法：sudo %s [--check|--dry-run] 快照号\n只支持 root 配置；检查模式不执行回滚。\n' "${0##*/}"; return 0 ;;
      *) [[ -z $snapshot_number && $argument =~ ^[1-9][0-9]*$ ]] || die '参数错误；使用 --help 查看用法。'; snapshot_number=$argument ;;
    esac
  done

  (( EUID == 0 )) || die '请使用 sudo 运行此脚本。'
  [[ $snapshot_number =~ ^[1-9][0-9]*$ ]] \
    || die '用法：sudo rollback-snapshot.sh 快照号'
  require_command awk btrfs findmnt snapper sync flock realpath cmp diff lsinitcpio bootctl jq sha256sum sort grep tee date install
  install -d -m 0750 /var/log/arch-niri-deploy
  log_file="/var/log/arch-niri-deploy/rollback-$(date +%Y%m%d-%H%M%S)-$$.log"
  (umask 077; : > "$log_file")
  exec > >(tee -a "$log_file") 2>&1
  printf '日志：%s\n' "$log_file"
  exec 9>/run/lock/arch-niri-rollback.lock
  flock -n 9 || die '另一个回滚或迁移操作正在进行。'
  trap rollback_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  [[ ! -e /var/lib/pacman/db.lck ]] || die '软件包管理器正在运行或存在遗留锁，请先核对。'
  printf '检查根子卷、目标快照、默认启动项和内核模块，请稍候……\n'
  rollback_preflight "$snapshot_number" || die '安全检查未通过，没有修改默认子卷。'
  if (( check_only )); then
    printf '快照 #%s 当前符合在线回滚检查条件。未执行回滚；实际执行时会重新检查。\n' "$snapshot_number"
    return 0
  fi
  printf '将回滚到快照 #%s。未保存的根系统更改会丢失；@home 不受影响。\n' "$snapshot_number"
  printf '确认继续请输入 ROLLBACK-%s：' "$snapshot_number" >/dev/tty
  IFS= read -r confirmation </dev/tty
  [[ $confirmation == "ROLLBACK-${snapshot_number}" ]] \
    || die '确认文本不匹配，未执行回滚。'

  # Only remove the pacman-compatible lock if this process created it atomically.
  (set -o noclobber; printf 'arch-niri-deploy rollback guard v1\n' > /var/lib/pacman/db.lck) 2>/dev/null \
    || die '无法取得软件包数据库锁。'
  ROLLBACK_PACMAN_LOCK=1
  rollback_preflight "$snapshot_number" || die '确认期间系统状态发生变化，已停止。'
  ROLLBACK_BEFORE_ID=$(rollback_default_id)
  source_uuid=$(btrfs subvolume show "/.snapshots/$snapshot_number/snapshot" | awk '$1 == "UUID:" {print $2}')
  [[ $source_uuid =~ ^[[:xdigit:]-]+$ ]] || die '无法读取来源快照 UUID。'
  boot_hash=$(rollback_boot_hash)
  ROLLBACK_ARMED=1
  if ! rollback_output=$(snapper --ambit classic -c root rollback --print-number "$snapshot_number" 2>&1); then
    printf '%s\n' "$rollback_output" >&2
    die 'Snapper 回滚命令失败，未重启。'
  fi
  printf '%s\n' "$rollback_output"
  new_number=$(awk '/^[0-9]+$/ {n=$0} END {print n}' <<< "$rollback_output")
  rollback_verify_result "$new_number" "$source_uuid" "$ROLLBACK_BEFORE_ID" \
    || die '新默认子卷不是来源快照的预期可写副本。'
  rollback_package_state_valid "/.snapshots/$new_number/snapshot" || die '新根中出现未知的软件包事务锁。'
  # Only the verified NEW writable root is edited; never change source snapshots.
  if [[ -f /.snapshots/$new_number/snapshot/var/lib/pacman/db.lck ]]; then
    rm -- "/.snapshots/$new_number/snapshot/var/lib/pacman/db.lck"
  fi
  printf '%s\n' "$boot_hash" | sha256sum --check --status || die '执行期间 /boot 内容发生变化。'
  [[ $(rollback_mount_rows /etc/fstab) == "$(rollback_mount_rows "/.snapshots/$new_number/snapshot/etc/fstab")" ]] \
    || die '新快照的挂载定义不一致。'
  rollback_kernel_check "/.snapshots/$new_number/snapshot" || die '回滚后内核校验失败。'
  rollback_boot_check "$(findmnt -nro UUID /)" || die '回滚后引导校验失败。'
  after_id=$(rollback_default_id)
  sync
  ROLLBACK_ARMED=0
  printf '回滚已校验：默认子卷 %s → %s（可写快照 #%s）。\n' "$ROLLBACK_BEFORE_ID" "$after_id" "$new_number"
  printf '请尽快执行 sudo reboot，并选择 Arch Linux；重启前不要再次升级或回滚。\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
