#!/usr/bin/env bash
set -euo pipefail

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

echo "Step 3 router setup complete."
