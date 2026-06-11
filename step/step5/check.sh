#!/usr/bin/env bash
set -euo pipefail

VPC_VM_IP="${VPC_VM_IP:-192.168.56.2}"

echo "[host ip_forward]"
sysctl net.ipv4.ip_forward

echo
echo "[br-public]"
ip addr show br-public

echo
echo "[app-server route]"
sudo ip netns exec app-server ip route

echo
echo "[nat rules]"
sudo iptables -t nat -S

echo
echo "[forward rules]"
sudo iptables -S FORWARD

echo
echo "[VPC VM -> public endpoint]"
curl -I "http://${VPC_VM_IP}"

echo
echo "[VPC VM -> database direct: expected to fail]"
timeout 3 bash -c 'cat < /dev/null > /dev/tcp/10.10.2.10/3306' && echo "database direct reachable" || echo "database direct blocked"

echo
echo "[app-server -> database 3306]"
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 blocked"'
