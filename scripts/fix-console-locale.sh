#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=${ARCH_NIRI_DEPLOY_DIR:-$(dirname -- "$SCRIPT_DIR")}
[[ -f $PROJECT_DIR/lib/locale.sh ]] || PROJECT_DIR=/opt/arch-niri-deploy
if [[ ! -f $PROJECT_DIR/lib/locale.sh ]]; then
  printf 'Run this script from the updated arch-niri-deploy project.\n' >&2
  exit 1
fi
# shellcheck source=../lib/common.sh
source "$PROJECT_DIR/lib/common.sh"
# shellcheck source=../lib/locale.sh
source "$PROJECT_DIR/lib/locale.sh"

main() {
  local backup relative
  # ASCII output remains readable on the affected console.
  (( EUID == 0 )) || { printf 'Run with sudo: sudo bash scripts/fix-console-locale.sh\n' >&2; exit 1; }
  require_arch
  require_command locale locale-gen sed install mktemp systemctl cp grep
  init_log
  backup=$(mktemp -d /root/arch-niri-console-backup.XXXXXXXX)
  for relative in etc/locale.gen \
    etc/systemd/system/getty@.service.d/10-arch-niri-locale.conf \
    etc/profile.d/zz-arch-niri-console.sh \
    etc/fish/conf.d/arch-niri-console.fish; do
    if [[ -e /$relative ]]; then
      install -d "$backup/$(dirname -- "$relative")"
      cp -a -- "/$relative" "$backup/$relative"
    fi
  done
  printf 'Backup: %s\n' "$backup"
  if ! locale -a | grep -Fxi 'en_US.utf8' >/dev/null; then
    if grep -Eq '^#?[[:space:]]*en_US\.UTF-8[[:space:]]+UTF-8' /etc/locale.gen; then
      sed -Ei 's/^#?[[:space:]]*(en_US\.UTF-8[[:space:]]+UTF-8.*)$/\1/' /etc/locale.gen
    else
      printf '\nen_US.UTF-8 UTF-8\n' >> /etc/locale.gen
    fi
    locale-gen
  fi
  configure_console_locale '' "$PROJECT_DIR"
  systemctl daemon-reload
  printf '%s\n' 'Console locale: English UTF-8. Desktop/SSH language is unchanged.'
  printf '%s\n' 'Reboot to apply to console login prompts. Existing sessions are not restarted.'
}

main "$@"
