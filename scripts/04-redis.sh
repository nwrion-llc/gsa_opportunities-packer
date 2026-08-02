#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get install -y --no-install-recommends redis-server

# Self-hosted on this VM only.
# IPv4-only: GCE instances have no IPv6 loopback, and the `-::1` optional-bind
# syntax that would otherwise skip it gracefully isn't supported until Redis 6.2
# (this image ships Ubuntu's 6.0.16 apt package).
sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf
sed -i 's/^supervised .*/supervised systemd/' /etc/redis/redis.conf

systemctl enable redis-server
if ! systemctl restart redis-server; then
  systemctl status redis-server --no-pager || true
  journalctl -xeu redis-server --no-pager -n 200 || true
  # redis.conf's `logfile` directive sends Redis's own startup errors here,
  # not to the journal — this is almost always where the real reason lives.
  echo "--- /var/log/redis/redis-server.log (tail) ---"
  tail -n 100 /var/log/redis/redis-server.log || true
  exit 1
fi
