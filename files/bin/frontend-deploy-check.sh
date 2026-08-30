#!/usr/bin/env bash
# Runs periodically (see frontend-deploy-check.timer). Self-healing on two
# independent fronts:
#   1. dist/index.html is missing - most commonly because
#      frontend-deploy.service failed during a prior boot (git clone hiccup,
#      missing branch, npm/build error) and never came back: nothing retries
#      a oneshot service that already failed, so a broken build would
#      otherwise sit 404ing forever.
#   2. The tracked branch has moved past what's currently built.
# Either trigger re-deploys via frontend-deploy.sh; no-ops (no npm
# install/build) if neither holds.
set -euo pipefail

FRONTEND_DIR=/opt/frontend/src
FRONTEND_REPO_URL="git@github.com:nwrion-llc/gsa_opportunities_frontend.git"
DEPLOY_KEY_PATH=/opt/frontend/.ssh/deploy_key

# shellcheck source=files/bin/lib-secrets.sh
source /opt/bin/lib-secrets.sh # also provides metadata()

FRONTEND_REPO_REF="$(metadata "instance/attributes/app-git-ref" || echo main)"

if [ ! -f "${FRONTEND_DIR}/dist/index.html" ]; then
  echo "frontend-deploy-check: no built site found, redeploying"
  exec /opt/frontend/bin/frontend-deploy.sh
fi

CURRENT_SHA="$(sudo -u frontend git -C "$FRONTEND_DIR" rev-parse HEAD 2>/dev/null || echo none)"

GIT_SSH_COMMAND="$(setup_deploy_key "$DEPLOY_KEY_PATH")"
export GIT_SSH_COMMAND
chown -R frontend:frontend "$(dirname "$DEPLOY_KEY_PATH")"
REMOTE_SHA="$(git ls-remote "$FRONTEND_REPO_URL" "refs/heads/${FRONTEND_REPO_REF}" | cut -f1)"
unset GIT_SSH_COMMAND

if [ "$CURRENT_SHA" = "$REMOTE_SHA" ]; then
  echo "frontend-deploy-check: ${FRONTEND_REPO_REF} unchanged (${CURRENT_SHA}) and site present; nothing to do"
  exit 0
fi

echo "frontend-deploy-check: ${FRONTEND_REPO_REF} moved ${CURRENT_SHA} -> ${REMOTE_SHA}, redeploying"
exec /opt/frontend/bin/frontend-deploy.sh
