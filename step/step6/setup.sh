#!/usr/bin/env bash
# 코어 파일 및 도커 컴포즈 생성
cat > Corefile << 'EOF'
.:53 {
    log
    errors

    hosts {
        192.168.56.2 api.local.test
        fallthrough
    }

    forward . 1.1.1.1 8.8.8.8
}
EOF

cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  route53-dns:
    image: coredns/coredns:1.11.3
    container_name: route53-dns
    restart: unless-stopped
    command: -conf /etc/coredns/Corefile
    ports:
      - "192.168.56.6:53:53/udp"
      - "192.168.56.6:53:53/tcp"
    volumes:
      - ./Corefile:/etc/coredns/Corefile:ro
EOF

# 실습
set -euo pipefail

docker-compose up -d
docker ps --filter name=route53-dns
docker logs route53-dns --tail 30

echo "Step 6 CoreDNS setup complete."
