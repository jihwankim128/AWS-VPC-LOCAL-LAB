#!/usr/bin/env bash
set -euo pipefail

echo "[app-server iptables]"
sudo ip netns exec app-server iptables -S

echo
echo "[database iptables]"
sudo ip netns exec database iptables -S

echo
echo "[app-server -> database 3306]"
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 blocked"'

echo
echo "[app-server -> database ping: expected to fail]"
sudo ip netns exec app-server ping -c 2 10.10.2.10 && echo "ping allowed" || echo "ping blocked"

echo
echo "[router source -> database 3306: expected to fail]"
sudo ip netns exec router bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "router source allowed" || echo "router source blocked"'

echo
echo "[app-server -> database 3307: expected to fail]"
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3307" && echo "database 3307 reachable" || echo "database 3307 blocked"'

echo
echo "[database mysql]"
docker exec database mysqladmin ping -uroot -plocalpass
