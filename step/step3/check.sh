#!/usr/bin/env bash
set -euo pipefail

echo "[router namespace]"
ip netns list

echo
echo "[router interfaces]"
sudo ip netns exec router ip addr show eth-public
sudo ip netns exec router ip addr show eth-db

echo
echo "[router forwarding]"
sudo ip netns exec router sysctl net.ipv4.ip_forward

echo
echo "[app-server route]"
sudo ip netns exec app-server ip route

echo
echo "[database route]"
sudo ip netns exec database ip route

echo
echo "[app-server -> database ping]"
sudo ip netns exec app-server ping -c 2 10.10.2.10

echo
echo "[app-server -> database 3306]"
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 unreachable"'
