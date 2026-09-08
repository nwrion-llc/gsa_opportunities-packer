#!/usr/bin/env bash
# Runs once per boot (see webproxy-setup.service), after nginx/certbot are
# installed (see scripts/05-webproxy.sh). Generates one nginx server block
# per hostname - read from the 'web-hostnames' instance metadata key, a JSON
# object of role -> FQDN (see InstanceConfig.hostnames in
# ../pulumi-infrastructure-gcp) - then obtains/renews their TLS certificates
# via certbot's nginx plugin. Safe to re-run: certbot skips domains that
# already have a valid certificate instead of re-issuing.
#
# Known roles:
#   api - reverse proxy to gunicorn on 127.0.0.1:8000, serving /static/
#         directly from Django's STATIC_ROOT. Also where Google login
#         (django-allauth) and /admin/ live - the app role below can't serve
#         those (its SPA fallback would 404 them).
#   app - 301-redirects everything to https://app.fedrank.com, the app's
#         new home (a separate, already-live deployment outside this repo)
#         - this instance no longer serves the SPA under this hostname.
#         Still needs its own nginx server block + TLS cert so the
#         redirect itself is served over HTTPS for this hostname.
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

  case "$role" in
    api)
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
      ;;
    app)
      cat > "$conf" <<EOF
server {
    listen 80;
    server_name ${fqdn};

    location / {
        return 301 https://app.fedrank.com\$request_uri;
    }
}
EOF
      ;;
    *)
      echo "webproxy-setup: unknown hostname role '${role}' (fqdn ${fqdn}); skipping" >&2
      return
      ;;
  esac

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
