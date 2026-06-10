#!/usr/bin/env bash
set -euo pipefail

VPC_VM_IP="${VPC_VM_IP:-192.168.56.2}"
APP_IP="${APP_IP:-10.10.1.10}"
IGW_IP="${IGW_IP:-10.10.1.254}"

add_rule() {
  local table="$1"
  shift
  if ! sudo iptables -t "${table}" -C "$@" 2>/dev/null; then
    sudo iptables -t "${table}" -A "$@"
  fi
}

add_filter_rule() {
  if ! sudo iptables -C "$@" 2>/dev/null; then
    sudo iptables -A "$@"
  fi
}

sudo sysctl -w net.ipv4.ip_forward=1

if ! ip addr show br-public | grep -q "${IGW_IP}/24"; then
  sudo ip addr add "${IGW_IP}/24" dev br-public
fi

sudo ip netns exec app-server ip route replace default via "${IGW_IP}" dev eth0

add_rule nat PREROUTING -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80"
add_rule nat OUTPUT -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80"

add_filter_rule FORWARD -p tcp -d "${APP_IP}" --dport 80 -j ACCEPT
add_filter_rule FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "Step 5 IGW DNAT setup complete."
