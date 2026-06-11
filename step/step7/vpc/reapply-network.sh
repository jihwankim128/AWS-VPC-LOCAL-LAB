#!/usr/bin/env bash
set -euo pipefail

VPC_VM_IP="${VPC_VM_IP:-192.168.56.2}"
APP_IP="${APP_IP:-10.10.1.10}"
DB_IP="${DB_IP:-10.10.2.10}"

echo "[cleanup old Step 7 network state]"
./clean.sh || true

echo "[Step 2: subnet and ENI]"
APP_PID="$(docker inspect -f '{{.State.Pid}}' app-server)"
DB_PID="$(docker inspect -f '{{.State.Pid}}' database)"

sudo mkdir -p /var/run/netns
sudo ln -sfT "/proc/${APP_PID}/ns/net" /var/run/netns/app-server
sudo ln -sfT "/proc/${DB_PID}/ns/net" /var/run/netns/database

sudo ip link add br-public type bridge
sudo ip link set br-public up
sudo ip link add br-private-db type bridge
sudo ip link set br-private-db up

sudo ip link add veth-app-host type veth peer name veth-app
sudo ip link set veth-app-host master br-public
sudo ip link set veth-app-host up
sudo ip link set veth-app netns app-server
sudo ip netns exec app-server ip link set veth-app name eth0
sudo ip netns exec app-server ip addr add "${APP_IP}/24" dev eth0
sudo ip netns exec app-server ip link set eth0 up
sudo ip netns exec app-server ip link set lo up

sudo ip link add veth-db-host type veth peer name veth-db
sudo ip link set veth-db-host master br-private-db
sudo ip link set veth-db-host up
sudo ip link set veth-db netns database
sudo ip netns exec database ip link set veth-db name eth0
sudo ip netns exec database ip addr add "${DB_IP}/24" dev eth0
sudo ip netns exec database ip link set eth0 up
sudo ip netns exec database ip link set lo up

echo "[Step 3: router and local route]"
sudo ip netns add router
sudo ip netns exec router ip link set lo up

sudo ip link add vrpubh type veth peer name vrpub
sudo ip link set vrpubh master br-public
sudo ip link set vrpubh up
sudo ip link set vrpub netns router
sudo ip netns exec router ip link set vrpub name eth-public
sudo ip netns exec router ip addr add 10.10.1.1/24 dev eth-public
sudo ip netns exec router ip link set eth-public up

sudo ip link add vrdbh type veth peer name vrdb
sudo ip link set vrdbh master br-private-db
sudo ip link set vrdbh up
sudo ip link set vrdb netns router
sudo ip netns exec router ip link set vrdb name eth-db
sudo ip netns exec router ip addr add 10.10.2.1/24 dev eth-db
sudo ip netns exec router ip link set eth-db up

sudo ip netns exec router sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec app-server ip route add 10.10.2.0/24 via 10.10.1.1 dev eth0
sudo ip netns exec database ip route add 10.10.1.0/24 via 10.10.2.1 dev eth0

echo "[Step 4: security group]"
sudo ip netns exec app-server iptables -F
sudo ip netns exec app-server iptables -X
sudo ip netns exec app-server iptables -P INPUT DROP
sudo ip netns exec app-server iptables -P OUTPUT DROP
sudo ip netns exec app-server iptables -P FORWARD DROP
sudo ip netns exec app-server iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -o lo -j ACCEPT
sudo ip netns exec app-server iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec app-server iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo ip netns exec app-server iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -p tcp -d "${DB_IP}" --dport 3306 -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

sudo ip netns exec database iptables -F
sudo ip netns exec database iptables -X
sudo ip netns exec database iptables -P INPUT DROP
sudo ip netns exec database iptables -P OUTPUT DROP
sudo ip netns exec database iptables -P FORWARD DROP
sudo ip netns exec database iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec database iptables -A OUTPUT -o lo -j ACCEPT
sudo ip netns exec database iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec database iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec database iptables -A INPUT -p tcp -s "${APP_IP}" --dport 3306 -j ACCEPT

echo "Step 7 internal VPC network setup complete."
echo "Run ./publish-app-server.sh next to expose AppServer with an EC2-style public address."
