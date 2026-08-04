#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y upgrade
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  software-properties-common \
  build-essential \
  libpq-dev \
  git \
  jq

# App user/group. No login shell — services run as this user, nobody interactively logs in as it.
if ! id -u app >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/app --shell /usr/sbin/nologin app
fi
mkdir -p /opt/app/bin /opt/app/src /opt/app/static /opt/app/log
chown -R app:app /opt/app

# Shared library scripts (lib-secrets.sh) live here - root-owned,
# world-readable, not scoped to the app user's own directory.
install -d -m 0755 /opt/bin
