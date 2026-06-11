#!/usr/bin/env bash
set -euo pipefail

VPC_VM_IP="${VPC_VM_IP:-192.168.56.2}"
APP_PUBLIC_IP="${APP_PUBLIC_IP:-192.168.56.3}"
APP_IP="${APP_IP:-10.10.1.10}"
IGW_IP="${IGW_IP:-10.10.1.254}"
PUBLIC_IFACE="${PUBLIC_IFACE:-}"

if [ -z "${PUBLIC_IFACE}" ]; then
  PUBLIC_IFACE="$(ip -o -4 addr show | awk -v ip="${VPC_VM_IP}" '$4 ~ "^" ip "/" {print $2; exit}')"
fi

if [ -z "${PUBLIC_IFACE}" ]; then
  echo "Cannot detect VPC VM public interface for ${VPC_VM_IP}." >&2
  exit 1
fi

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

sudo sysctl -w net.ipv4.ip_forward=1

if ! ip addr show dev br-public | grep -q "${IGW_IP}/24"; then
  sudo ip addr add "${IGW_IP}/24" dev br-public
fi

sudo ip netns exec app-server ip route replace default via "${IGW_IP}" dev eth0

if ! ip addr show dev "${PUBLIC_IFACE}" | grep -q "${APP_PUBLIC_IP}/24"; then
  sudo ip addr add "${APP_PUBLIC_IP}/24" dev "${PUBLIC_IFACE}"
fi

sudo iptables -t nat -D PREROUTING -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true

add_nat_rule PREROUTING -d "${APP_PUBLIC_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80"
add_nat_rule OUTPUT -d "${APP_PUBLIC_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80"
add_filter_rule FORWARD -p tcp -d "${APP_IP}" --dport 80 -j ACCEPT
add_filter_rule FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "AppServer EC2-style public endpoint published."
echo "  HTTP: http://${APP_PUBLIC_IP}"
