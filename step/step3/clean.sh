#!/usr/bin/env bash
set -euo pipefail

sudo ip netns exec app-server ip route del 10.10.2.0/24 via 10.10.1.1 dev eth0 2>/dev/null || true
sudo ip netns exec database ip route del 10.10.1.0/24 via 10.10.2.1 dev eth0 2>/dev/null || true
sudo ip netns delete router 2>/dev/null || true

echo "Step 3 router cleanup complete."
