#!/usr/bin/env bash
set -Eeuo pipefail

GPU_SUMMARY=''
GPU_NEEDS_LEGACY_NVIDIA=0
declare -ag GPU_PACKAGES=()

detect_gpu() {
  local gpu_lines
  gpu_lines=$(lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
  [[ -n $gpu_lines ]] || die "未检测到显卡控制器。"
  GPU_SUMMARY=$gpu_lines
  GPU_PACKAGES=(mesa vulkan-icd-loader)
  GPU_NEEDS_LEGACY_NVIDIA=0

  if grep -Eqi 'AMD|ATI' <<<"$gpu_lines"; then
    GPU_PACKAGES+=(vulkan-radeon libva-mesa-driver mesa-vdpau)
  fi
  if grep -Eqi 'Intel' <<<"$gpu_lines"; then
    GPU_PACKAGES+=(vulkan-intel intel-media-driver)
  fi
  if grep -Eqi 'NVIDIA' <<<"$gpu_lines"; then
    if grep -Eqi 'GTX (10[0-9]{2}|9[0-9]{2}|8[0-9]{2}|7[0-9]{2}|6[0-9]{2})|Quadro (M|K)|GeForce [4-9][0-9]{2}' <<<"$gpu_lines"; then
      GPU_NEEDS_LEGACY_NVIDIA=1
    else
      GPU_PACKAGES+=(nvidia-open nvidia-utils libva-nvidia-driver)
    fi
  fi
}

install_gpu_drivers() {
  detect_gpu
  info "检测到显卡："
  printf '%s\n' "$GPU_SUMMARY"
  if (( GPU_NEEDS_LEGACY_NVIDIA )); then
    warn "检测到可能属于 Pascal/Maxwell 或更旧的 NVIDIA 显卡。"
    warn "当前官方 590+ 驱动已停止支持；为避免黑屏，本脚本不自动安装 AUR legacy 驱动。"
    warn "请先阅读 Arch 新闻，并手工安装 nvidia-580xx-dkms 后再启动 Niri。"
      GPU_PACKAGES+=(dkms linux-headers)
  fi
  pacman_install "${GPU_PACKAGES[@]}"
}

install_32bit_gpu_drivers() {
  local -a packages=(lib32-mesa lib32-vulkan-icd-loader)
  grep -Eqi 'AMD|ATI' <<<"$GPU_SUMMARY" && packages+=(lib32-vulkan-radeon)
  grep -Eqi 'Intel' <<<"$GPU_SUMMARY" && packages+=(lib32-vulkan-intel)
  if grep -Eqi 'NVIDIA' <<<"$GPU_SUMMARY" && (( ! GPU_NEEDS_LEGACY_NVIDIA )); then
    packages+=(lib32-nvidia-utils)
  fi
  pacman_install "${packages[@]}"
}
