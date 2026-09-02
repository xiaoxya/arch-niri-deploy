#!/usr/bin/env bash
set -Eeuo pipefail

configure_snapper_root() {
  local allowed_user=${1:-}
  install -d -m 0750 /etc/snapper/configs
  if [[ ! -f /etc/snapper/configs/root ]]; then
    install -m 0644 /dev/null /etc/snapper/configs/root
    {
      printf 'SUBVOLUME="/"\nFSTYPE="btrfs"\nQGROUP="1/0"\n'
      printf 'SPACE_LIMIT="0.5"\nFREE_LIMIT="0.2"\n'
      printf 'ALLOW_USERS="%s"\nALLOW_GROUPS="wheel"\nSYNC_ACL="yes"\n' "$allowed_user"
      printf 'BACKGROUND_COMPARISON="yes"\nNUMBER_CLEANUP="yes"\n'
      printf 'NUMBER_MIN_AGE="1800"\nNUMBER_LIMIT="10"\nNUMBER_LIMIT_IMPORTANT="5"\n'
      printf 'TIMELINE_CREATE="yes"\nTIMELINE_CLEANUP="yes"\n'
      printf 'TIMELINE_MIN_AGE="1800"\nTIMELINE_LIMIT_HOURLY="10"\n'
      printf 'TIMELINE_LIMIT_DAILY="7"\nTIMELINE_LIMIT_WEEKLY="0"\n'
      printf 'TIMELINE_LIMIT_MONTHLY="3"\nTIMELINE_LIMIT_YEARLY="0"\n'
      printf 'EMPTY_PRE_POST_CLEANUP="yes"\nEMPTY_PRE_POST_MIN_AGE="1800"\n'
    } > /etc/snapper/configs/root
  fi
  grep -q '^SNAPPER_CONFIGS=' /etc/conf.d/snapper 2>/dev/null \
    && sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS="root"/' /etc/conf.d/snapper \
    || printf 'SNAPPER_CONFIGS="root"\n' > /etc/conf.d/snapper
  systemctl enable snapper-timeline.timer snapper-cleanup.timer
}

create_snapshot() {
  local description=${1:-"手动快照"}
  if command -v snapper >/dev/null 2>&1 && [[ -f /etc/snapper/configs/root ]]; then
    sudo snapper -c root create --description "$description" --cleanup-algorithm number
  fi
}
