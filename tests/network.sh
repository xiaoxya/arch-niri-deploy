#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/network.sh
source "$PROJECT_DIR/lib/network.sh"

check() {
  local expected=$1 actual=0
  shift
  "$@" || actual=$?
  if (( expected == 0 && actual != 0 || expected != 0 && actual == 0 )); then
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
  fi
}

for address in 10.10.5.118/24 192.168.1.2/30 172.16.4.8/16; do
  check 0 valid_lan_cidr "$address"
done
for address in 192.168.1.0/24 192.168.1.255/24 192.168.1.2/31 \
  127.0.0.1/8 224.0.0.1/24 0.0.0.1/24 256.1.1.1/24 192.168.01.2/24 \
  10.0.0.1/0 10.0.0.1/024 10.0.0.1/32 '10.0.0.1/24;echo bad' ''; do
  check 1 valid_lan_cidr "$address"
done
check 0 valid_lan_gateway 10.10.5.118/24 10.10.5.1
check 0 valid_lan_gateway 10.10.5.118/24 -
check 1 valid_lan_gateway 10.10.5.118/24 10.10.6.1
check 1 valid_lan_gateway 10.10.5.118/24 10.10.5.118
check 1 valid_lan_gateway 10.10.5.118/24 10.10.5.255
check 0 valid_dns_list 223.5.5.5,119.29.29.29
for dns in ',1.1.1.1' '1.1.1.1,' '1.1.1.1,,9.9.9.9' '1.1.1.1, 9.9.9.9' $'1.1.1.1\n[connection]' ''; do
  check 1 valid_dns_list "$dns"
done

NETWORK_MAC=00:11:22:33:44:55
NETWORK_ADDRESS=10.10.5.118/24
NETWORK_GATEWAY=10.10.5.1
NETWORK_DNS=223.5.5.5,119.29.29.29
profile=$(render_static_network_profile)
[[ $profile == *'mac-address=00:11:22:33:44:55'* && $profile != *'interface-name='* ]]
[[ $profile == *'address1=10.10.5.118/24'* && $profile == *'gateway=10.10.5.1'* ]]
[[ $profile == *'dns=223.5.5.5;119.29.29.29;'* ]]
NETWORK_GATEWAY=-
profile=$(render_static_network_profile)
[[ $profile != *'gateway='* && $profile == *'never-default=true'* ]]
NETWORK_MAC=$'00:11:22:33:44:55\nautoconnect=false'
check 1 render_static_network_profile
printf 'Network validation and profile rendering tests passed.\n'
