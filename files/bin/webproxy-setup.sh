#!/usr/bin/env bash
# Runs once per boot (see webproxy-setup.service), after nginx/certbot are
# installed (see scripts/05-webproxy.sh). Generates one nginx server block
# per hostname - read from the 'web-hostnames' instance metadata key, a JSON
# object of role -> FQDN (see InstanceConfig.hostnames in
# ../pulumi-infrastructure-gcp) - then obtains/renews their TLS certificates
# via certbot's nginx plugin. Safe to re-run: certbot skips domains that
# already have a valid certificate instead of re-issuing.
#
# Every hostname (api.*, app.*) proxies to the same gunicorn backend and
# serves /static/ directly from Django's STATIC_ROOT - there's no separate
# frontend build here, Django's own templates/static serve that role (unlike
# ../../gratefulforu/api-packer, which splits "api" vs "app" into a reverse
# proxy vs. a static frontend bundle).
set -euo pipefail

METADATA_ROOT="http://metadata.google.internal/computeMetadata/v1"

metadata() {
  curl -sf -H "Metadata-Flavor: Google" "${METADATA_ROOT}/$1"
}

if ! HOSTNAMES_JSON="$(metadata "instance/attributes/web-hostnames")"; then
  echo "webproxy-setup: no 'web-hostnames' metadata key on this instance; nothing to do" >&2
  exit 0
fi
LE_EMAIL="$(metadata "instance/attributes/letsencrypt-email")"

write_site() {
  local role="$1" fqdn="$2"
  local conf="/etc/nginx/sites-available/${role}.conf"

  cat > "$conf" <<EOF
server {
    listen 80;
    server_name ${fqdn};

    location /static/ {
        alias /opt/app/src/staticfiles/;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  ln -sf "$conf" "/etc/nginx/sites-enabled/${role}.conf"
}

CERTBOT_DOMAIN_ARGS=()
while IFS=$'\t' read -r role fqdn; do
  write_site "$role" "$fqdn"
  CERTBOT_DOMAIN_ARGS+=(-d "$fqdn")
done < <(echo "$HOSTNAMES_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')

nginx -t
systemctl reload nginx

certbot --nginx --non-interactive --agree-tos -m "$LE_EMAIL" --redirect "${CERTBOT_DOMAIN_ARGS[@]}"
