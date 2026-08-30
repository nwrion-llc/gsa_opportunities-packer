#!/usr/bin/env bash
# Shared by bootstrap.sh and deploy-check.sh (source, don't execute). Fetches
# Secret Manager secrets via this instance's own service account, which needs
# roles/secretmanager.secretAccessor on each one it's granted access to (see
# InstanceConfig.githubTokenAccess / includeOauthEnv in
# ../../pulumi-infrastructure-gcp/infra/compute.py) - each secret's short ID
# is passed in via its own instance metadata key.

metadata() {
  curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/$1"
}

# Fetches and decodes a Secret Manager secret by its short ID.
fetch_secret() {
  local secret_id="$1" project_id access_token
  project_id="$(metadata "project/project-id")"
  access_token="$(metadata "instance/service-accounts/default/token" | jq -r '.access_token')"
  curl -sf -H "Authorization: Bearer ${access_token}" \
    "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${secret_id}/versions/latest:access" \
    | jq -r '.payload.data' | base64 -d
}

# Fetches a Secret Manager secret whose short ID is itself given by an
# instance metadata key (rather than known ahead of time) - returns nothing
# (exit 1) if that metadata key isn't set on this instance.
fetch_secret_by_metadata_key() {
  local secret_id
  secret_id="$(metadata "instance/attributes/$1")" || return 1
  fetch_secret "$secret_id"
}

# Writes a GitHub deploy key to a private-mode file and prints a
# GIT_SSH_COMMAND value pointed at it, with host-key checking relaxed to
# accept-new (first connection trusts GitHub's key rather than failing
# non-interactively). metadata_key defaults to gsa_opportunities' own deploy
# key; frontend-deploy.sh passes 'frontend-deploy-key-secret-id' for its own,
# separate one (GitHub deploy keys are unique per public key across all of
# GitHub, so the two repos can't share a single keypair - see
# ../pulumi-infrastructure-gcp/infra/secrets.py's DeployKey docstring).
setup_deploy_key() {
  local key_path="$1" metadata_key="${2:-github-deploy-key-secret-id}"
  install -d -m 0700 "$(dirname "$key_path")"
  fetch_secret_by_metadata_key "$metadata_key" > "$key_path"
  chmod 600 "$key_path"
  printf 'ssh -i %s -o StrictHostKeyChecking=accept-new' "$key_path"
}
