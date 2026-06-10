#!/usr/bin/env bash
set -euo pipefail

DNS_VM_IP="${DNS_VM_IP:-192.168.56.6}"
DOMAIN="${DOMAIN:-api.local.test}"

echo "[CoreDNS container]"
docker ps --filter name=route53-dns

echo
echo "[DNS query]"
dig @"${DNS_VM_IP}" "${DOMAIN}" +short

echo
echo "[HTTP via resolved IP]"
curl -I http://192.168.56.2
