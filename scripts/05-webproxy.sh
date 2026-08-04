#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get install -y --no-install-recommends nginx certbot python3-certbot-nginx

# Actual server blocks (one per hostname) are generated at boot by
# webproxy-setup.sh, once the real hostnames are known (see the
# 'web-hostnames' instance metadata key) - nginx's default site would
# otherwise conflict with certbot matching server_name across our configs.
rm -f /etc/nginx/sites-enabled/default

# Renewal timer ships with the certbot package and defaults to enabled: this
# is just belt-and-suspenders in case that ever changes upstream.
systemctl enable certbot.timer
