#!/usr/bin/env bash
set -euo pipefail

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
sudo ip netns exec app-server ip addr add 10.10.1.10/24 dev eth0
sudo ip netns exec app-server ip link set eth0 up
sudo ip netns exec app-server ip link set lo up

sudo ip link add veth-db-host type veth peer name veth-db
sudo ip link set veth-db-host master br-private-db
sudo ip link set veth-db-host up
sudo ip link set veth-db netns database
sudo ip netns exec database ip link set veth-db name eth0
sudo ip netns exec database ip addr add 10.10.2.10/24 dev eth0
sudo ip netns exec database ip link set eth0 up
sudo ip netns exec database ip link set lo up

echo "Step 2 network setup complete."
