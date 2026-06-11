#!/usr/bin/env bash
set -euo pipefail

PUBLIC_KEY_FILE="${PUBLIC_KEY_FILE:-app-server-key.pub}"

if [ ! -f "${PUBLIC_KEY_FILE}" ]; then
  echo "Missing ${PUBLIC_KEY_FILE}." >&2
  echo "Create a key on Host and copy the public key to this VPC VM directory first." >&2
  exit 1
fi

docker cp "${PUBLIC_KEY_FILE}" app-server:/tmp/app-server-key.pub
docker exec app-server bash -lc '
  set -euo pipefail
  mkdir -p /home/ubuntu/.ssh
  cat /tmp/app-server-key.pub > /home/ubuntu/.ssh/authorized_keys
  chown -R ubuntu:ubuntu /home/ubuntu/.ssh
  chmod 700 /home/ubuntu/.ssh
  chmod 600 /home/ubuntu/.ssh/authorized_keys
  cat > /etc/ssh/sshd_config.d/99-local-lab.conf <<'"'"'EOF'"'"'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
PermitRootLogin no
AuthorizedKeysFile .ssh/authorized_keys
EOF
  sshd -t
  pkill -HUP sshd
  rm -f /tmp/app-server-key.pub
'

echo "Public key installed for ubuntu user."
echo "Password authentication disabled for the AppServer Ubuntu user."
echo "Connect from Host with: ssh -i local-keys/app-server-key ubuntu@192.168.56.3"
