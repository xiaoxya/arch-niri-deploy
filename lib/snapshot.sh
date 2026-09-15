#!/usr/bin/env bash
set -Eeuo pipefail

configure_snapper_root() {
  local allowed_user=${1:-} configs
  local -a existing_configs=()
  install -d -m 0750 /etc/snapper/configs
  if [[ ! -f /etc/snapper/configs/root ]]; then
    install -m 0644 /dev/null /etc/snapper/configs/root
    {
      printf 'SUBVOLUME="/"\nFSTYPE="btrfs"\nQGROUP=""\n'
      printf 'SPACE_LIMIT="0.5"\nFREE_LIMIT="0.2"\n'
      printf 'ALLOW_USERS="%s"\nALLOW_GROUPS="wheel"\nSYNC_ACL="yes"\n' "$allowed_user"
      printf 'BACKGROUND_COMPARISON="yes"\nNUMBER_CLEANUP="yes"\n'
      printf 'NUMBER_MIN_AGE="1800"\nNUMBER_LIMIT="2-10"\nNUMBER_LIMIT_IMPORTANT="2-5"\n'
      printf 'TIMELINE_CREATE="yes"\nTIMELINE_CLEANUP="yes"\n'
      printf 'TIMELINE_MIN_AGE="1800"\nTIMELINE_LIMIT_HOURLY="2-10"\n'
      printf 'TIMELINE_LIMIT_DAILY="2-7"\nTIMELINE_LIMIT_WEEKLY="0"\n'
      printf 'TIMELINE_LIMIT_MONTHLY="1-3"\nTIMELINE_LIMIT_YEARLY="0"\n'
      printf 'EMPTY_PRE_POST_CLEANUP="yes"\nEMPTY_PRE_POST_MIN_AGE="1800"\n'
    } > /etc/snapper/configs/root
  fi
  install -d /etc/conf.d
  if grep -q '^SNAPPER_CONFIGS=' /etc/conf.d/snapper 2>/dev/null; then
    # Preserve other existing Snapper configurations.
    configs=$(sed -n 's/^SNAPPER_CONFIGS="\([^"]*\)"[[:space:]]*$/\1/p' /etc/conf.d/snapper)
    [[ $configs =~ ^[[:alnum:]_[:space:]-]*$ ]] || return 1
    grep -Eq '^SNAPPER_CONFIGS="[^"]*"[[:space:]]*$' /etc/conf.d/snapper || return 1
    read -r -a existing_configs <<< "$configs"
    if [[ " ${existing_configs[*]} " != *' root '* ]]; then
      existing_configs+=(root)
    fi
    sed -i "s/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS=\"${existing_configs[*]}\"/" /etc/conf.d/snapper
  else
    printf 'SNAPPER_CONFIGS="root"\n' >> /etc/conf.d/snapper
  fi
  configure_snapper_quota
  systemctl enable snapper-timeline.timer snapper-cleanup.timer
}

snapper_qgroup_valid() {
  local group listing config=${1:-/etc/snapper/configs/root}
  group=$(sed -n 's/^QGROUP="\([0-9][0-9]*\/[0-9][0-9]*\)"$/\1/p' "$config")
  [[ $group =~ ^1/[0-9]+$ ]] || return 1
  listing=$(LC_ALL=C btrfs qgroup show --raw /) || return 1
  awk -v group="$group" '$1 == group {found=1} END {exit !found}' <<< "$listing"
}

configure_snapper_quota() {
  if ! snapper_qgroup_valid; then
    printf '初始化 Snapper 配额组（不是只开启 Btrfs quota）……\n'
    snapper --no-dbus -c root setup-quota || return 1
  fi
  snapper_qgroup_valid || return 1
  printf '等待 Btrfs 配额统计完成……\n'
  btrfs quota rescan -w / || return 1
}

create_initial_root_snapshot() {
  local number
  # A failed baseline must fail installation, not produce a success banner.
  number=$(snapper --no-dbus -c root create --print-number \
    --description 'Fresh Arch base system' --cleanup-algorithm number \
    --userdata important=yes) || return 1
  [[ $number =~ ^[1-9][0-9]*$ ]] || return 1
  [[ $(btrfs property get -ts "/.snapshots/$number/snapshot" ro) == ro=true ]] || return 1
  install -d -m 0755 /var/lib/arch-niri-deploy
  printf '%s\n' "$number" > /var/lib/arch-niri-deploy/initial-snapshot
  printf '初始只读快照 #%s 已创建并验证。\n' "$number"
}

verify_initial_root_snapshot() {
  local number
  IFS= read -r number < /var/lib/arch-niri-deploy/initial-snapshot || return 1
  [[ $number =~ ^[1-9][0-9]*$ ]] || return 1
  [[ $(btrfs property get -ts "/.snapshots/$number/snapshot" ro) == ro=true ]] || return 1
  snapper_qgroup_valid
}

create_snapshot() {
  local description=${1:-"手动快照"}
  if command -v snapper >/dev/null 2>&1 && [[ -f /etc/snapper/configs/root ]]; then
    sudo snapper -c root create --description "$description" --cleanup-algorithm number
  fi
}
