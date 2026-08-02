#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"

# Ubuntu 22.04's default Python (3.10) is older than this version, so pull
# from deadsnakes. Adjust PYTHON_VERSION (variables.pkr.hcl) once the real
# app's requirements are known.
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update
apt-get install -y --no-install-recommends \
  "python${PYTHON_VERSION}" \
  "python${PYTHON_VERSION}-venv" \
  "python${PYTHON_VERSION}-dev"

sudo -u app python"${PYTHON_VERSION}" -m venv /opt/app/venv
sudo -u app /opt/app/venv/bin/pip install --no-cache-dir --upgrade pip
