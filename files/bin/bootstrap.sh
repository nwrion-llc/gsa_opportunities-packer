#!/usr/bin/env bash
# Runs once per boot, before gunicorn/celery start (see app-config.service).
# Pulls runtime config from GCE instance metadata and ensures the Postgres
# role/db exist. The app-specific migrate/collectstatic step below is a
# placeholder — fill in once gsa_opportunities' actual framework is known.
set -euo pipefail

# shellcheck disable=SC2034 # used by the commented-out migrate step below
APP_DIR=/opt/app/src
ENV_FILE=/opt/app/.env
# shellcheck disable=SC2034 # used by the commented-out migrate step below
VENV=/opt/app/venv/bin
METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/attributes/app-env"

if curl -sf -H "Metadata-Flavor: Google" "$METADATA_URL" -o "${ENV_FILE}.tmp"; then
  mv "${ENV_FILE}.tmp" "$ENV_FILE"
else
  echo "bootstrap: no 'app-env' metadata key set on this instance; keeping existing ${ENV_FILE} if present" >&2
  rm -f "${ENV_FILE}.tmp"
  touch "$ENV_FILE"
fi
chown app:app "$ENV_FILE"
chmod 600 "$ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${POSTGRES_DB:?POSTGRES_DB must be set via the app-env metadata key}"
: "${POSTGRES_USER:?POSTGRES_USER must be set via the app-env metadata key}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set via the app-env metadata key}"

sudo -u postgres psql -v ON_ERROR_STOP=1 -v user="${POSTGRES_USER}" -v pass="${POSTGRES_PASSWORD}" <<-'EOSQL'
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'user') THEN
      EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'user', :'pass');
   ELSE
      EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', :'user', :'pass');
   END IF;
END
$$;
EOSQL

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'" | grep -q 1 \
  || sudo -u postgres createdb -O "${POSTGRES_USER}" "${POSTGRES_DB}"

# TODO: once the app's framework is decided, run its migration step here, e.g.:
# sudo -u app -H bash -c "
#   cd '${APP_DIR}' &&
#   set -a && source '${ENV_FILE}' && set +a &&
#   '${VENV}/python' manage.py migrate --noinput
# "
