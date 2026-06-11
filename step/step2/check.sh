#!/usr/bin/env bash
set -euo pipefail

echo "[bridges]"
ip link show br-public
ip link show br-private-db

echo
echo "[app-server eth0]"
sudo ip netns exec app-server ip addr show eth0

echo
echo "[database eth0]"
sudo ip netns exec database ip addr show eth0

echo
echo "[app-server nginx]"
sudo ip netns exec app-server curl -I http://10.10.1.10

echo
echo "[database mysql]"
docker exec database mysqladmin ping -uroot -plocalpass
