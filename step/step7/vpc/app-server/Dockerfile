FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server python3 python3-pip curl procps \
    && pip3 install --no-cache-dir flask pymysql \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash ubuntu \
    && passwd -d ubuntu \
    && printf '%s\n' \
      'PubkeyAuthentication yes' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'ChallengeResponseAuthentication no' \
      'PermitEmptyPasswords no' \
      'PermitRootLogin no' \
      'AuthorizedKeysFile .ssh/authorized_keys' \
      > /etc/ssh/sshd_config.d/99-local-lab.conf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY app.py /app/app.py

EXPOSE 22 80

CMD ["/usr/sbin/sshd", "-D"]
