#!/usr/bin/env bash
# Runs once per boot (see frontend-deploy.service), and again whenever
# frontend-deploy-check.sh finds the tracked branch has moved. Clones the
# frontend fresh, builds it, and swaps it into place - Vite produces a static
# build, so nginx serves FRONTEND_DIR/dist directly (see webproxy-setup.sh);
# no running Node process is needed in production.
set -euo pipefail

FRONTEND_DIR=/opt/frontend/src
FRONTEND_REPO_URL="git@github.com:nwrion-llc/gsa_opportunities_frontend.git"
DEPLOY_KEY_PATH=/opt/frontend/.ssh/deploy_key

# shellcheck source=files/bin/lib-secrets.sh
source /opt/bin/lib-secrets.sh # also provides metadata()

# Shared with the Django app's branch mapping - see InstanceConfig.appGitRef
# in ../pulumi-infrastructure-gcp. Both repos always deploy the same branch.
FRONTEND_REPO_REF="$(metadata "instance/attributes/app-git-ref" || echo main)"

# A separate deploy key from gsa_opportunities' own (see bootstrap.sh) -
# GitHub deploy keys are unique per public key across all of GitHub, so the
# two repos each need their own keypair (see 'frontend-deploy-key-secret-id',
# granted via InstanceConfig.githubFrontendTokenAccess in
# ../pulumi-infrastructure-gcp).
GIT_SSH_COMMAND="$(setup_deploy_key "$DEPLOY_KEY_PATH" "frontend-deploy-key-secret-id")"
export GIT_SSH_COMMAND
chown -R frontend:frontend "$(dirname "$DEPLOY_KEY_PATH")"

rm -rf "${FRONTEND_DIR}.new"
sudo -u frontend --preserve-env=GIT_SSH_COMMAND \
  git clone --branch "$FRONTEND_REPO_REF" --depth 1 "$FRONTEND_REPO_URL" "${FRONTEND_DIR}.new"
unset GIT_SSH_COMMAND

# VITE_DJANGO_ORIGIN (SignIn.tsx's "Sign in with Google" link target, and
# Layout.tsx's Status link) - a public URL, not a secret, so this is derived
# straight from the same 'web-hostnames' metadata key webproxy-setup.sh uses
# rather than needing its own secret/metadata plumbing. VITE_API_BASE_URL
# needs no override - its code default ('/api', relative) is already correct
# here, since nginx proxies /api/ under this same app.* origin.
if HOSTNAMES_JSON="$(metadata "instance/attributes/web-hostnames")"; then
  API_FQDN="$(echo "$HOSTNAMES_JSON" | jq -r '.api // empty')"
  if [ -n "$API_FQDN" ]; then
    printf 'VITE_DJANGO_ORIGIN=https://%s\n' "$API_FQDN" > "${FRONTEND_DIR}.new/.env"
  fi
fi

chown -R frontend:frontend "${FRONTEND_DIR}.new"
sudo -u frontend -H bash -c "
  cd '${FRONTEND_DIR}.new' &&
  npm ci &&
  npm run build
"

rm -rf "$FRONTEND_DIR"
mv "${FRONTEND_DIR}.new" "$FRONTEND_DIR"
echo "frontend-deploy: deployed $(sudo -u frontend git -C "$FRONTEND_DIR" rev-parse HEAD)"
