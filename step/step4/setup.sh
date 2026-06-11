#!/usr/bin/env bash
set -euo pipefail

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
sudo ip netns exec app-server iptables -A OUTPUT -p tcp -d 10.10.2.10 --dport 3306 -j ACCEPT
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
sudo ip netns exec database iptables -A INPUT -p tcp -s 10.10.1.10 --dport 3306 -j ACCEPT

echo "Step 4 security group rules applied."
