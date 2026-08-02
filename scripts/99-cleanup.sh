#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get -y autoremove
apt-get clean
rm -rf /var/lib/apt/lists/*

rm -rf /tmp/* /var/tmp/*
rm -f /opt/app/.env

# Let cloud-init and machine identity regenerate fresh on first real boot,
# so every instance cloned from this image gets its own identity.
truncate -s 0 /etc/machine-id
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/instance
cloud-init clean --logs || true

history -c || true
rm -f /root/.bash_history /home/*/.bash_history 2>/dev/null || true
