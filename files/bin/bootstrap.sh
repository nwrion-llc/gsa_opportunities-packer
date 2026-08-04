#!/usr/bin/env bash
# Runs once per boot, before gunicorn/celery start (see app-config.service).
# Clones the Django app source fresh from GitHub over SSH (read-only deploy
# key), pulls runtime config from GCE instance metadata, ensures the Postgres
# role/db exist, then applies migrations and collects static files.
set -euo pipefail

APP_DIR=/opt/app/src
APP_REPO_URL="git@github.com:nwrion-llc/gsa_pportunities.git"
DEPLOY_KEY_PATH=/opt/app/.ssh/deploy_key
ENV_FILE=/opt/app/.env
# Persisted on the "pgdata" disk (mounted before this runs - see
# pgdata-disk.service) so a self-generated dev .env survives instance
# replacement, not just reboots of the same instance.
PERSISTED_ENV_FILE=/mnt/pgdata/app.env
VENV=/opt/app/venv/bin

# shellcheck source=files/bin/lib-github-deploy-key.sh
source /opt/bin/lib-github-deploy-key.sh

# Set via InstanceConfig.appGitRef in ../pulumi-infrastructure-gcp - defaults
# to "main" if the metadata key is unset.
APP_REPO_REF="$(metadata "instance/attributes/app-git-ref" || echo main)"

# --- App source: clone fresh each boot (see deploy-check.sh for
# subsequent-boot updates without a full reboot).
GIT_SSH_COMMAND="$(setup_deploy_key "$DEPLOY_KEY_PATH")"
export GIT_SSH_COMMAND
chown -R app:app "$(dirname "$DEPLOY_KEY_PATH")"

rm -rf "${APP_DIR}.new"
sudo -u app --preserve-env=GIT_SSH_COMMAND \
  git clone --branch "$APP_REPO_REF" --depth 1 "$APP_REPO_URL" "${APP_DIR}.new"
unset GIT_SSH_COMMAND

rm -rf "$APP_DIR"
mv "${APP_DIR}.new" "$APP_DIR"
chown -R app:app "$APP_DIR"

sudo -u app "${VENV}/pip" install --no-cache-dir -r "${APP_DIR}/requirements.txt"

# --- Runtime config (secrets, DB creds, etc.)
# Three tiers, first one available wins:
#   1. 'app-env' metadata key - explicit values wired through Pulumi
#      (see InstanceConfig.includeAppEnv in ../pulumi-infrastructure-gcp),
#      for environments that need real, hand-chosen config (e.g. prod).
#   2. A previously self-generated env persisted on the pgdata disk - keeps
#      the Postgres role/Django secret key stable across reboots and
#      instance replacement.
#   3. Generate fresh dev defaults and persist them for next time.
if metadata "instance/attributes/app-env" > "${ENV_FILE}.tmp"; then
  mv "${ENV_FILE}.tmp" "$ENV_FILE"
elif [ -f "$PERSISTED_ENV_FILE" ]; then
  echo "bootstrap: no 'app-env' metadata key; reusing persisted ${PERSISTED_ENV_FILE}" >&2
  cp "$PERSISTED_ENV_FILE" "$ENV_FILE"
else
  echo "bootstrap: no 'app-env' metadata key or persisted env; generating dev defaults" >&2
  rm -f "${ENV_FILE}.tmp"
  cat > "$ENV_FILE" <<EOF
DJANGO_SECRET_KEY=$(openssl rand -hex 32)
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=*

POSTGRES_DB=gsa_opportunities
POSTGRES_USER=gsa_opportunities
POSTGRES_PASSWORD=$(openssl rand -hex 24)
POSTGRES_HOST=localhost
POSTGRES_PORT=5432

CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/1
EOF
  install -m 0600 -o root -g root "$ENV_FILE" "$PERSISTED_ENV_FILE"
fi
chown app:app "$ENV_FILE"
chmod 600 "$ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${POSTGRES_DB:?POSTGRES_DB missing from ${ENV_FILE}}"
: "${POSTGRES_USER:?POSTGRES_USER missing from ${ENV_FILE}}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD missing from ${ENV_FILE}}"

sudo -u postgres psql -v ON_ERROR_STOP=1 -v user="${POSTGRES_USER}" -v pass="${POSTGRES_PASSWORD}" <<-'EOSQL'
SELECT format('ALTER ROLE %I WITH PASSWORD %L', :'user', :'pass')
WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = :'user')
UNION ALL
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'user', :'pass')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'user')
\gexec
EOSQL

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'" | grep -q 1 \
  || sudo -u postgres createdb -O "${POSTGRES_USER}" "${POSTGRES_DB}"

sudo -u app -H bash -c "
  cd '${APP_DIR}' &&
  set -a && source '${ENV_FILE}' && set +a &&
  '${VENV}/python' manage.py migrate --noinput &&
  '${VENV}/python' manage.py collectstatic --noinput
"
