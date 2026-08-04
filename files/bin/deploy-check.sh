#!/usr/bin/env bash
# Runs periodically (see app-deploy-check.timer). Self-healing on two
# independent fronts:
#   1. gunicorn/celery aren't actually running - most commonly because
#      app-config.service failed during a prior boot (git clone hiccup,
#      missing branch, transient Secret Manager error) and never came back:
#      Restart= only kicks in when a unit's own process exits, not when it
#      never started because a Requires= dependency failed, so a broken
#      deploy would otherwise sit dead until a human intervenes or the
#      instance reboots. Fix: restart app-config.service (reruns bootstrap.sh
#      in full - if whatever broke it is now fixed, this succeeds), then the
#      app services.
#   2. APP_REPO_REF has moved past what's currently deployed - re-clone,
#      reinstall, migrate, and collectstatic to pick up the new code
#      (skipped if trigger 1 already fired, since bootstrap.sh does the same
#      work).
# No-ops entirely if neither condition holds.
set -euo pipefail

APP_DIR=/opt/app/src
APP_REPO_URL="git@github.com:nwrion-llc/gsa_pportunities.git"
DEPLOY_KEY_PATH=/opt/app/.ssh/deploy_key
ENV_FILE=/opt/app/.env
VENV=/opt/app/venv/bin

# shellcheck source=files/bin/lib-secrets.sh
source /opt/bin/lib-secrets.sh

APP_REPO_REF="$(metadata "instance/attributes/app-git-ref" || echo main)"

SERVICES_DOWN=false
for svc in gunicorn.service celery-worker.service celery-beat.service; do
  if ! systemctl is-active --quiet "$svc"; then
    echo "deploy-check: ${svc} is not active"
    SERVICES_DOWN=true
  fi
done

if [ "$SERVICES_DOWN" = true ]; then
  echo "deploy-check: restarting app-config.service to recover"
  systemctl restart app-config.service
  systemctl restart gunicorn.service celery-worker.service celery-beat.service
  echo "deploy-check: recovered at $(sudo -u app git -C "$APP_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
  exit 0
fi

CURRENT_SHA="$(sudo -u app git -C "$APP_DIR" rev-parse HEAD 2>/dev/null || echo none)"

GIT_SSH_COMMAND="$(setup_deploy_key "$DEPLOY_KEY_PATH")"
export GIT_SSH_COMMAND
REMOTE_SHA="$(git ls-remote "$APP_REPO_URL" "refs/heads/${APP_REPO_REF}" | cut -f1)"

if [ "$CURRENT_SHA" = "$REMOTE_SHA" ]; then
  unset GIT_SSH_COMMAND
  echo "deploy-check: ${APP_REPO_REF} unchanged (${CURRENT_SHA}) and services healthy; nothing to do"
  exit 0
fi

echo "deploy-check: ${APP_REPO_REF} moved ${CURRENT_SHA} -> ${REMOTE_SHA}, redeploying"

rm -rf "${APP_DIR}.new"
sudo -u app --preserve-env=GIT_SSH_COMMAND \
  git clone --branch "$APP_REPO_REF" --depth 1 "$APP_REPO_URL" "${APP_DIR}.new"
unset GIT_SSH_COMMAND

rm -rf "$APP_DIR"
mv "${APP_DIR}.new" "$APP_DIR"
chown -R app:app "$APP_DIR"

sudo -u app "${VENV}/pip" install --no-cache-dir -r "${APP_DIR}/requirements.txt"

sudo -u app -H bash -c "
  cd '${APP_DIR}' &&
  set -a && source '${ENV_FILE}' && set +a &&
  '${VENV}/python' manage.py migrate --noinput &&
  '${VENV}/python' manage.py collectstatic --noinput
"

systemctl restart gunicorn.service celery-worker.service celery-beat.service
echo "deploy-check: redeployed and restarted at ${REMOTE_SHA}"
