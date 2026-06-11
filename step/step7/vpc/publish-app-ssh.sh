#!/usr/bin/env bash
set -euo pipefail

APP_PUBLIC_IP="${APP_PUBLIC_IP:-192.168.56.3}"
APP_IP="${APP_IP:-10.10.1.10}"

add_nat_rule() {
  if ! sudo iptables -t nat -C "$@" 2>/dev/null; then
    sudo iptables -t nat -A "$@"
  fi
}

add_filter_rule() {
  if ! sudo iptables -C "$@" 2>/dev/null; then
    sudo iptables -A "$@"
  fi
}

if ! ip link show br-public >/dev/null 2>&1; then
  echo "br-public was not found. Run ./reapply-network.sh first." >&2
  exit 1
fi

if ! sudo ip netns exec app-server ip addr show eth0 | grep -q "${APP_IP}/24"; then
  echo "app-server namespace does not have ${APP_IP}/24. Run ./reapply-network.sh first." >&2
  exit 1
fi

add_nat_rule PREROUTING -d "${APP_PUBLIC_IP}" -p tcp --dport 22 -j DNAT --to-destination "${APP_IP}:22"
add_nat_rule OUTPUT -d "${APP_PUBLIC_IP}" -p tcp --dport 22 -j DNAT --to-destination "${APP_IP}:22"
add_filter_rule FORWARD -p tcp -d "${APP_IP}" --dport 22 -j ACCEPT

echo "AppServer SSH public access published."
echo "  SSH: ssh -i local-keys/app-server-key ubuntu@${APP_PUBLIC_IP}"
