#!/usr/bin/env bash
set -euo pipefail

VPC_VM_IP="${VPC_VM_IP:-192.168.56.2}"
APP_PUBLIC_IP="${APP_PUBLIC_IP:-192.168.56.3}"
APP_IP="${APP_IP:-10.10.1.10}"
DB_IP="${DB_IP:-10.10.2.10}"
IGW_IP="${IGW_IP:-10.10.1.254}"
PUBLIC_IFACE="${PUBLIC_IFACE:-}"

if [ -z "${PUBLIC_IFACE}" ]; then
  PUBLIC_IFACE="$(ip -o -4 addr show | awk -v ip="${VPC_VM_IP}" '$4 ~ "^" ip "/" {print $2; exit}')"
fi

sudo iptables -t nat -D PREROUTING -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -d "${VPC_VM_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true
sudo iptables -t nat -D PREROUTING -d "${APP_PUBLIC_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -d "${APP_PUBLIC_IP}" -p tcp --dport 80 -j DNAT --to-destination "${APP_IP}:80" 2>/dev/null || true
sudo iptables -t nat -D PREROUTING -d "${APP_PUBLIC_IP}" -p tcp --dport 22 -j DNAT --to-destination "${APP_IP}:22" 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -d "${APP_PUBLIC_IP}" -p tcp --dport 22 -j DNAT --to-destination "${APP_IP}:22" 2>/dev/null || true

sudo iptables -D FORWARD -p tcp -d "${APP_IP}" --dport 80 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -p tcp -d "${APP_IP}" --dport 22 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

for ns in app-server database; do
  if sudo ip netns exec "${ns}" true 2>/dev/null; then
    sudo ip netns exec "${ns}" iptables -P INPUT ACCEPT 2>/dev/null || true
    sudo ip netns exec "${ns}" iptables -P OUTPUT ACCEPT 2>/dev/null || true
    sudo ip netns exec "${ns}" iptables -P FORWARD ACCEPT 2>/dev/null || true
    sudo ip netns exec "${ns}" iptables -F 2>/dev/null || true
    sudo ip netns exec "${ns}" iptables -X 2>/dev/null || true
  fi
done

if sudo ip netns exec app-server true 2>/dev/null; then
  sudo ip netns exec app-server ip route del default via "${IGW_IP}" dev eth0 2>/dev/null || true
  sudo ip netns exec app-server ip route del 10.10.2.0/24 via 10.10.1.1 dev eth0 2>/dev/null || true
  sudo ip netns exec app-server ip link delete eth0 2>/dev/null || true
fi

if sudo ip netns exec database true 2>/dev/null; then
  sudo ip netns exec database ip route del 10.10.1.0/24 via 10.10.2.1 dev eth0 2>/dev/null || true
  sudo ip netns exec database ip link delete eth0 2>/dev/null || true
fi

if docker inspect app-server >/dev/null 2>&1; then
  docker exec app-server bash -lc '
    rm -f /home/ubuntu/.ssh/authorized_keys
    rm -f /tmp/app-server-key.pub
    rmdir /home/ubuntu/.ssh 2>/dev/null || true
  ' 2>/dev/null || true
fi

rm -f app-server-key.pub

sudo ip netns delete router 2>/dev/null || true

sudo ip addr del "${IGW_IP}/24" dev br-public 2>/dev/null || true
if [ -n "${PUBLIC_IFACE}" ]; then
  sudo ip addr del "${APP_PUBLIC_IP}/24" dev "${PUBLIC_IFACE}" 2>/dev/null || true
fi

for link in veth-app-host veth-app veth-db-host veth-db vrpubh vrpub vrdbh vrdb; do
  sudo ip link delete "${link}" 2>/dev/null || true
done

sudo ip link delete br-public 2>/dev/null || true
sudo ip link delete br-private-db 2>/dev/null || true
sudo rm -f /var/run/netns/app-server
sudo rm -f /var/run/netns/database

echo "Step 7 standalone network and SSH key cleanup complete."
