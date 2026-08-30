#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Matches gsa_opportunities_frontend's Dockerfile (FROM node:22-alpine).
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y --no-install-recommends nodejs

# App user/group. No login shell — services run as this user, nobody interactively logs in as it.
if ! id -u frontend >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/frontend --shell /usr/sbin/nologin frontend
fi
mkdir -p /opt/frontend/bin /opt/frontend/src
chown -R frontend:frontend /opt/frontend
# nginx (www-data) needs to traverse into here to serve the built static
# files directly - unlike /opt/app, whose contents only gunicorn touches.
chmod 0755 /opt/frontend
