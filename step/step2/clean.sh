#!/usr/bin/env bash
set -euo pipefail

sudo ip link delete br-public 2>/dev/null || true
sudo ip link delete br-private-db 2>/dev/null || true
sudo rm -f /var/run/netns/app-server
sudo rm -f /var/run/netns/database

echo "Step 2 network cleanup complete."
