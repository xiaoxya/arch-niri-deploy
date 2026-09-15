#!/usr/bin/env bash
# All disk/initramfs operations are mocked; fixtures are read-only text files.
# Mocks are called indirectly; create_snapshot's sudo path is not exercised.
# shellcheck disable=SC2329,SC2032
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/rollback-snapshot.sh
source "$PROJECT_DIR/scripts/rollback-snapshot.sh"
# shellcheck source=../lib/snapshot.sh
source "$PROJECT_DIR/lib/snapshot.sh"
fixtures="$PROJECT_DIR/tests/fixtures/rollback"
count=0
check() {
  local expected=$1 actual=0
  shift
  "$@" || actual=$?
  if (( expected == 0 && actual != 0 || expected != 0 && actual == 0 )); then
    printf 'FAIL: %s\n' "$*" >&2; exit 1
  fi
  count=$((count+1))
}

check 0 rollback_root_fstab_valid "$fixtures/fstab-valid" abcd-1234
check 1 rollback_root_fstab_valid "$fixtures/fstab-valid" ffff-0000
check 0 rollback_package_state_valid "$fixtures/target"
check 0 rollback_package_state_valid "$fixtures/own-lock"
check 1 rollback_package_state_valid "$fixtures/foreign-lock"
for fixture in fstab-fixed fstab-fixed-id fstab-duplicate; do
  check 1 rollback_root_fstab_valid "$fixtures/$fixture" abcd-1234
done
check 0 rollback_options_valid 'root=UUID=abcd-1234 rw quiet' abcd-1234
for options in 'root=UUID=abcd-1234 ro' 'root=UUID=abcd-1234 rw rootflags=subvol=@' \
  'root=UUID=abcd-1234 rw rootflags=subvolid=256' 'root=UUID=bad rw' \
  'root=UUID=abcd-1234 rw init=/bin/sh' 'rw' \
  'root=UUID=abcd-1234 root=UUID=abcd-1234 rw'; do
  check 1 rollback_options_valid "$options" abcd-1234
done

lsinitcpio() { printf 'usr/lib/modules/%s/kernel/mock.ko\n' "$mock_initramfs_version"; }
mock_initramfs_version=test-kernel
check 0 rollback_kernel_check "$fixtures/target" "$fixtures/current" "$fixtures/boot"
check 1 rollback_kernel_check "$fixtures/dkms-mismatch" "$fixtures/current" "$fixtures/boot"
check 1 rollback_kernel_check "$fixtures/missing-kernel" "$fixtures/current" "$fixtures/boot"
mock_initramfs_version=old-kernel
check 1 rollback_kernel_check "$fixtures/target" "$fixtures/current" "$fixtures/boot"
lsinitcpio() { return 1; }
check 1 rollback_kernel_check "$fixtures/target" "$fixtures/current" "$fixtures/boot"

mock_new_id=300 mock_default_id=300 mock_ro=false mock_parent=aaaa-bbbb
rollback_subvolume_id() { printf '%s\n' "$mock_new_id"; }
rollback_default_id() { printf '%s\n' "$mock_default_id"; }
btrfs() {
  case "$1 $2" in
    'property get') printf 'ro=%s\n' "$mock_ro" ;;
    'subvolume show') printf 'Parent UUID: %s\n' "$mock_parent" ;;
    'qgroup show') printf '%s 100 100\n' "$mock_qgroup" ;;
    *) printf 'Unexpected mocked disk operation: %s\n' "$*" >&2; return 98 ;;
  esac
}
check 0 rollback_verify_result 9 aaaa-bbbb 256
mock_default_id=301
check 1 rollback_verify_result 9 aaaa-bbbb 256
mock_default_id=300 mock_new_id=256
check 1 rollback_verify_result 9 aaaa-bbbb 256
mock_new_id=300 mock_ro=true
check 1 rollback_verify_result 9 aaaa-bbbb 256
mock_ro=false mock_parent=cccc-dddd
check 1 rollback_verify_result 9 aaaa-bbbb 256
check 1 rollback_verify_result '../bad' aaaa-bbbb 256
mock_qgroup=1/0
check 0 snapper_qgroup_valid "$fixtures/qgroup"
mock_qgroup=1/1
check 1 snapper_qgroup_valid "$fixtures/qgroup"
snapper() { return 42; }
check 1 create_initial_root_snapshot

compensate_success() (
  ROLLBACK_ARMED=1 ROLLBACK_BEFORE_ID=256 ROLLBACK_PACMAN_LOCK=0
  btrfs() { [[ $* == 'subvolume set-default 256 /' ]]; }
  rollback_default_id() { printf '256\n'; }
  sync() { :; }
  rollback_cleanup
)
compensate_failure() (
  ROLLBACK_ARMED=1 ROLLBACK_BEFORE_ID=256 ROLLBACK_PACMAN_LOCK=0
  btrfs() { return 1; }
  rollback_cleanup
)
check 1 compensate_success
check 1 compensate_failure
output=$(compensate_success 2>&1) && exit 1
[[ $output == *'已恢复原默认子卷'* && $output != *'严重错误'* ]]
output=$(compensate_failure 2>&1) && exit 1
[[ $output == *'严重错误'* && $output != *'已恢复原默认子卷'* ]]
count=$((count+2))
check 0 main --help
printf '%s rollback checks passed (mocked, no real disk operations).\n' "$count"
