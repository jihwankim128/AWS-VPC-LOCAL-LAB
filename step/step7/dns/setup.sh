#!/usr/bin/env bash
set -euo pipefail

docker rm -f route53-dns 2>/dev/null || true
docker-compose up -d
docker ps --filter name=route53-dns
docker logs route53-dns --tail 30

echo "Step 7 DNS setup complete."
