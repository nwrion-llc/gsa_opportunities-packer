#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
POSTGRES_VERSION="${POSTGRES_VERSION:-16}"

# Ubuntu 22.04 ships PostgreSQL 14 by default; pull from the PGDG repo instead.
install -d /usr/share/postgresql-common/pgdg
curl -sSf -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list

apt-get update
apt-get install -y --no-install-recommends "postgresql-${POSTGRES_VERSION}"

PG_CONF_DIR="/etc/postgresql/${POSTGRES_VERSION}/main"

# Self-hosted on this VM only — never expose it off-box.
sed -i "s/^#listen_addresses.*/listen_addresses = 'localhost'/" "${PG_CONF_DIR}/postgresql.conf"

# Local password auth for the app role; the postgres superuser stays peer-authenticated.
cat > "${PG_CONF_DIR}/pg_hba.conf" <<-'EOF'
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF

systemctl enable postgresql "postgresql@${POSTGRES_VERSION}-main"
if ! systemctl restart "postgresql@${POSTGRES_VERSION}-main"; then
  systemctl status "postgresql@${POSTGRES_VERSION}-main" --no-pager || true
  journalctl -xeu "postgresql@${POSTGRES_VERSION}-main" --no-pager -n 200 || true
  echo "--- /var/log/postgresql/postgresql-${POSTGRES_VERSION}-main.log (tail) ---"
  tail -n 100 "/var/log/postgresql/postgresql-${POSTGRES_VERSION}-main.log" || true
  exit 1
fi
