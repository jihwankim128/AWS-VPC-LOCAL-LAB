#!/usr/bin/env bash
set -euo pipefail

for ns in app-server database; do
  sudo ip netns exec "${ns}" iptables -P INPUT ACCEPT
  sudo ip netns exec "${ns}" iptables -P OUTPUT ACCEPT
  sudo ip netns exec "${ns}" iptables -P FORWARD ACCEPT
  sudo ip netns exec "${ns}" iptables -F
  sudo ip netns exec "${ns}" iptables -X
done

echo "Step 4 security group rules cleared."
