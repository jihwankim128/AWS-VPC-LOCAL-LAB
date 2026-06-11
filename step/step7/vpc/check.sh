#!/usr/bin/env bash
set -euo pipefail

echo "[database init]"
docker exec database mysql -uroot -plocalpass appdb -e 'SELECT id, title FROM page_contents;'

echo
echo "[app-server namespace]"
sudo ip netns exec app-server curl -s http://10.10.1.10 | grep -E 'AWS VPC Local Lab|DB 연결 성공'

echo
echo "[app-server ssh]"
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.1.10/22" && echo "ssh 22 reachable" || echo "ssh 22 blocked"'

echo
echo "[app-server public endpoint]"
curl -s http://192.168.56.3 | grep -E 'AWS VPC Local Lab|DB 연결 성공'

echo
echo "[public domain]"
curl -s http://api.local.test | grep -E 'AWS VPC Local Lab|DB 연결 성공'

echo
echo "[app-server -> database 3306]"
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 blocked"'

echo
echo "[router source -> database 3306: expected to fail]"
sudo ip netns exec router bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "router source allowed" || echo "router source blocked"'

echo
echo "[app-server -> database 3307: expected to fail]"
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3307" && echo "database 3307 reachable" || echo "database 3307 blocked"'
