#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/snapper-rollback/PKGBUILD
source "$PROJECT_DIR/packaging/snapper-rollback/PKGBUILD"
files=("$PROJECT_DIR/packaging/snapper-rollback/launcher.sh"
       "$PROJECT_DIR/scripts/rollback-snapshot.sh" "$PROJECT_DIR/lib/rollback.sh" "$PROJECT_DIR/LICENSE")
for index in "${!files[@]}"; do
  actual=$(sha256sum "${files[$index]}" | awk '{print $1}')
  [[ $actual == "${sha256sums[$((index+1))]}" ]] || { printf 'Checksum mismatch: %s\n' "${files[$index]}" >&2; exit 1; }
done
if [[ -n ${1:-} ]]; then
  actual=$(sha256sum "$1" | awk '{print $1}')
  [[ $actual == "${sha256sums[0]}" ]] || { printf 'Upstream archive checksum mismatch.\n' >&2; exit 1; }
fi
[[ $pkgrel == 3 && " ${depends[*]} " == *' snapper '* && " ${depends[*]} " == *' jq '* ]]
printf 'Package source integrity and dependency checks passed.\n'
