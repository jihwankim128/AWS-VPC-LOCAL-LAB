#!/usr/bin/env bash
set -euo pipefail

docker exec app-server pkill -f /app/app.py 2>/dev/null || true
docker exec -d app-server python3 /app/app.py

echo "AppServer web application started inside the Ubuntu EC2 container."
