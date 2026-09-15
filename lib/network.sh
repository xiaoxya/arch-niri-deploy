#!/usr/bin/env bash
set -Eeuo pipefail

NETWORK_MODE=dhcp
NETWORK_INTERFACE=''
NETWORK_MAC=''
NETWORK_ADDRESS=''
NETWORK_GATEWAY=''
NETWORK_DNS=''

valid_ipv4() {
  local address=$1 octet
  local -a octets=()
  [[ $address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a octets <<< "$address"
  for octet in "${octets[@]}"; do
    [[ $octet == 0 || $octet =~ ^[1-9][0-9]{0,2}$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
  # Unspecified, loopback, multicast and reserved addresses are not LAN hosts.
  (( 10#${octets[0]} > 0 && 10#${octets[0]} < 224 && 10#${octets[0]} != 127 ))
}

ipv4_number() {
  local a b c d
  IFS=. read -r a b c d <<< "$1"
  printf '%s' "$(((10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d))"
}

valid_lan_cidr() {
  local address=${1%/*} prefix=${1##*/} number mask host
  [[ $1 == */* && $prefix =~ ^([1-9]|[12][0-9]|30)$ ]] || return 1
  valid_ipv4 "$address" || return 1
  number=$(ipv4_number "$address")
  mask=$(((0xffffffff << (32 - prefix)) & 0xffffffff))
  host=$((number & (0xffffffff ^ mask)))
  (( host != 0 && host != (0xffffffff ^ mask) ))
}

valid_lan_gateway() {
  local cidr=$1 gateway=$2 prefix=${1##*/} mask ip_number gateway_number
  [[ $gateway == - ]] && return 0
  valid_lan_cidr "$cidr" && valid_lan_cidr "$gateway/$prefix" || return 1
  ip_number=$(ipv4_number "${cidr%/*}")
  gateway_number=$(ipv4_number "$gateway")
  mask=$(((0xffffffff << (32 - prefix)) & 0xffffffff))
  (( ip_number != gateway_number && (ip_number & mask) == (gateway_number & mask) ))
}

valid_dns_list() {
  local value=$1 address
  local -a addresses=()
  [[ $value =~ ^[0-9.,]+$ && $value != ,* && $value != *, && $value != *,,* ]] || return 1
  IFS=, read -r -a addresses <<< "$value"
  for address in "${addresses[@]}"; do
    valid_ipv4 "$address" || return 1
  done
}

prompt_network_settings() {
  local choice path interface state address selection gateway
  local -a interfaces=() labels=()
  choice=$(choose_one '新系统网络设置' 1 '自动获取地址（DHCP，默认）' '固定 IPv4（有线网卡，IPv6 关闭）')
  [[ $choice == 2 ]] || return 0
  for path in /sys/class/net/*; do
    [[ -e $path/device && ! -d $path/wireless && ! -e $path/phy80211 ]] || continue
    [[ $(< "$path/type") == 1 ]] || continue
    interface=${path##*/}
    state=$(< "$path/operstate")
    address=$(ip -o -4 addr show dev "$interface" scope global | awk 'NR == 1 {print $4}')
    interfaces+=("$interface")
    labels+=("$interface / $state / ${address:-无 IPv4} / $(< "$path/address")")
  done
  ((${#interfaces[@]})) || die '未找到物理有线网卡；请重新选择 DHCP，无线网络可进入系统后用 nmtui 配置。'
  selection=$(choose_one '选择固定 IP 使用的有线网卡' 1 "${labels[@]}")
  NETWORK_INTERFACE=${interfaces[$((selection - 1))]}
  NETWORK_MAC=$(< "/sys/class/net/$NETWORK_INTERFACE/address")
  [[ $NETWORK_MAC =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ && $NETWORK_MAC != 00:00:00:00:00:00 ]] \
    || die '无法读取有效网卡 MAC 地址。'
  [[ $(< "/sys/class/net/$NETWORK_INTERFACE/addr_assign_type") == 0 ]] \
    || die '所选网卡 MAC 不是永久地址，请恢复网卡永久 MAC 后重试或选择 DHCP。'
  address=$(ip -o -4 addr show dev "$NETWORK_INTERFACE" scope global | awk 'NR == 1 {print $4}')
  info '请输入路由器已预留或 DHCP 池以外的地址，避免 IP 冲突。支持普通 LAN 的 /1 到 /30。'
  while true; do
    NETWORK_ADDRESS=$(prompt_default '固定 IPv4/前缀（例如 192.168.1.50/24）' "${address:-}")
    valid_lan_cidr "$NETWORK_ADDRESS" && break
    warn 'IPv4/前缀无效，不能使用网络地址或广播地址。'
  done
  gateway=$(ip -4 route show default dev "$NETWORK_INTERFACE" | awk '$1 == "default" && $2 == "via" {print $3; exit}')
  while true; do
    NETWORK_GATEWAY=$(prompt_default '网关（无网关输入 -）' "${gateway:--}")
    valid_lan_gateway "$NETWORK_ADDRESS" "$NETWORK_GATEWAY" && break
    warn '网关必须是同网段的另一台主机地址；无网关请输入 -。'
  done
  while true; do
    NETWORK_DNS=$(prompt_default 'DNS IPv4（英文逗号分隔，不含空格）' '223.5.5.5,119.29.29.29')
    valid_dns_list "$NETWORK_DNS" && break
    warn 'DNS 列表格式无效。'
  done
  NETWORK_MODE=static
  info '固定 IP 在重启进入新系统后生效；当前 Live/SSH 网络保持原状。'
}

render_static_network_profile() {
  valid_lan_cidr "$NETWORK_ADDRESS" \
    && valid_lan_gateway "$NETWORK_ADDRESS" "$NETWORK_GATEWAY" \
    && valid_dns_list "$NETWORK_DNS" || return 1
  [[ $NETWORK_MAC =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || return 1
  printf '[connection]\nid=arch-niri-static\ntype=ethernet\nautoconnect=true\nautoconnect-priority=100\n'
  # Match hardware rather than the ISO interface name, which may change at boot.
  printf '\n[ethernet]\nmac-address=%s\n' "$NETWORK_MAC"
  printf '\n[ipv4]\nmethod=manual\naddress1=%s\n' "$NETWORK_ADDRESS"
  if [[ $NETWORK_GATEWAY != - ]]; then
    printf 'gateway=%s\n' "$NETWORK_GATEWAY"
  else
    printf 'never-default=true\n'
  fi
  printf 'dns=%s;\nignore-auto-dns=true\nmay-fail=false\n' "${NETWORK_DNS//,/;}"
  printf '\n[ipv6]\nmethod=disabled\n'
}

configure_target_network() {
  local root=$1 profile
  [[ $NETWORK_MODE == static ]] || return 0
  profile="$root/etc/NetworkManager/system-connections/arch-niri-static.nmconnection"
  install -d -m 0700 "$root/etc/NetworkManager/system-connections"
  install -m 0600 /dev/null "$profile"
  render_static_network_profile > "$profile"
  # Offline parsing works in chroot, without starting NetworkManager or D-Bus.
  arch-chroot "$root" nmcli --offline connection modify connection.id arch-niri-static \
    < "$profile" >/dev/null
  ok "固定 IPv4 已写入新系统：$NETWORK_INTERFACE / $NETWORK_ADDRESS（按 MAC 绑定）。"
}
