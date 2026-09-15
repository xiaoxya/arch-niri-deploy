#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_ROLLBACK_PACKAGE=1
ROLLBACK_SOURCE_DIR=''
readonly ROLLBACK_SOURCE_COMMIT=04488f2350e8ec214277fe7de608492a9ee665a7
readonly ROLLBACK_SOURCE_SHA256=a7bc632d724f26fd0a187b1c55441f6b47856f2945dde74ec7e510e56f290679

prepare_rollback_source() {
  (( INSTALL_ROLLBACK_PACKAGE )) || return 0
  ROLLBACK_SOURCE_DIR=$(mktemp -d /tmp/arch-niri-rollback-source.XXXXXXXX)
  local archive="snapper-rollback-${ROLLBACK_SOURCE_COMMIT}.tar.gz"
  info '正在下载并校验固定版本的 snapper-rollback 源码（尚未清盘）……'
  curl --fail --location --show-error --connect-timeout 10 --max-time 120 --retry 2 \
    "https://codeload.github.com/jrabinow/snapper-rollback/tar.gz/${ROLLBACK_SOURCE_COMMIT}" \
    --output "$ROLLBACK_SOURCE_DIR/$archive"
  printf '%s  %s\n' "$ROLLBACK_SOURCE_SHA256" "$ROLLBACK_SOURCE_DIR/$archive" | sha256sum --check
  pacman -Si base-devel jq >/dev/null
}

install_target_rollback_package() {
  local root=$1 account=$2 project_dir=$3 root_uuid=$4 build_dir target_build
  local -a packages=()
  (( INSTALL_ROLLBACK_PACKAGE )) || return 0
  [[ $root_uuid =~ ^[[:xdigit:]-]+$ ]] || die 'snapper-rollback 配置需要有效的分区 UUID。'
  build_dir=$(mktemp -d "$root/var/tmp/arch-niri-rollback-build.XXXXXXXX")
  target_build=${build_dir#"$root"}
  install -m 0644 "$project_dir/packaging/snapper-rollback/PKGBUILD" "$build_dir/PKGBUILD"
  install -m 0644 "$project_dir/packaging/snapper-rollback/launcher.sh" "$build_dir/launcher.sh"
  install -m 0644 "$project_dir/scripts/rollback-snapshot.sh" "$build_dir/rollback-snapshot.sh"
  install -m 0644 "$project_dir/lib/rollback.sh" "$build_dir/rollback.sh"
  install -m 0644 "$project_dir/LICENSE" "$build_dir/PROJECT-LICENSE"
  install -m 0644 "$ROLLBACK_SOURCE_DIR/snapper-rollback-${ROLLBACK_SOURCE_COMMIT}.tar.gz" "$build_dir/"
  arch-chroot "$root" chown -R "$account" "$target_build"
  info '以普通用户构建 snapper-rollback，再由 Pacman 安装；无需从 AUR 在线构建。'
  # shellcheck disable=SC2016
  arch-chroot "$root" runuser -u "$account" -- bash -c \
    'cd -- "$1" && PKGEXT=.pkg.tar.zst makepkg --noconfirm' bash "$target_build"
  packages=("$build_dir"/snapper-rollback-*.pkg.tar.zst)
  [[ ${#packages[@]} == 1 && -f ${packages[0]} ]] || die '未得到唯一的 snapper-rollback 软件包。'
  arch-chroot "$root" pacman -U --noconfirm "${packages[0]#"$root"}"
  {
    printf '[root]\nsubvol_main = @\nsubvol_snapshots = @snapshots\n'
    printf 'mountpoint = /btrfsroot\ndev = /dev/disk/by-uuid/%s\n' "$root_uuid"
  } > "$root/etc/snapper-rollback.conf"
  arch-chroot "$root" snapper-rollback --help >/dev/null
  ok 'snapper-rollback 安全入口已安装（统一使用 Snapper classic）；没有执行回滚。'
}
