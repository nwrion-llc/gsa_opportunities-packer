#!/usr/bin/env bash
# Shared by bootstrap.sh and deploy-check.sh (source, don't execute). Fetches
# the read-only SSH deploy key for the gsa_pportunities repo from Secret
# Manager (see ../../pulumi-infrastructure-gcp/infra/secrets.py) via this
# instance's own service account, which needs
# roles/secretmanager.secretAccessor on it (InstanceConfig.githubTokenAccess=
# true) - the secret's short ID is passed in via the
# 'github-deploy-key-secret-id' metadata key.

metadata() {
  curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/$1"
}

fetch_deploy_key() {
  local secret_id project_id access_token
  secret_id="$(metadata "instance/attributes/github-deploy-key-secret-id")"
  project_id="$(metadata "project/project-id")"
  access_token="$(metadata "instance/service-accounts/default/token" | jq -r '.access_token')"
  curl -sf -H "Authorization: Bearer ${access_token}" \
    "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${secret_id}/versions/latest:access" \
    | jq -r '.payload.data' | base64 -d
}

# Writes the deploy key to a private-mode file and prints a GIT_SSH_COMMAND
# value pointed at it, with host-key checking relaxed to accept-new (first
# connection trusts GitHub's key rather than failing non-interactively).
setup_deploy_key() {
  local key_path="$1"
  install -d -m 0700 "$(dirname "$key_path")"
  fetch_deploy_key > "$key_path"
  chmod 600 "$key_path"
  printf 'ssh -i %s -o StrictHostKeyChecking=accept-new' "$key_path"
}
