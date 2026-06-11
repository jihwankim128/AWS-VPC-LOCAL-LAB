#!/usr/bin/env bash
set -euo pipefail

VPC_VM_IP="${VPC_VM_IP:-192.168.56.2}"
APP_IP="${APP_IP:-10.10.1.10}"
IGW_IP="${IGW_IP:-10.10.1.254}"

sudo iptables -t nat -D PREROUTING -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true
sudo iptables -D FORWARD -p tcp -d "${APP_IP}" --dport 80 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
sudo ip netns exec app-server ip route del default via "${IGW_IP}" dev eth0 2>/dev/null || true
sudo ip addr del "${IGW_IP}/24" dev br-public 2>/dev/null || true

echo "Step 5 IGW DNAT cleanup complete."
