#!/usr/bin/env bash
# Runs once per boot, before postgresql@${POSTGRES_VERSION}-main.service starts
# (see pgdata-disk.service). Moves PGDATA onto the attached "pgdata" persistent
# disk so it survives the boot disk being replaced (e.g. when a new app image
# is rolled out) instead of living on the ephemeral boot disk.
#
# First boot: format the disk, migrate the on-image default cluster onto it,
# and repoint postgresql.conf's data_directory there. Later boots: the mount
# and data_directory are already in place, this is a no-op.
set -euo pipefail

POSTGRES_VERSION="16"
DEVICE="/dev/disk/by-id/google-pgdata"
MOUNT_POINT="/mnt/pgdata"
PGDATA="${MOUNT_POINT}/${POSTGRES_VERSION}/main"
PG_CONF="/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf"
DEFAULT_PGDATA="/var/lib/postgresql/${POSTGRES_VERSION}/main"

if [ ! -e "$DEVICE" ]; then
  echo "pgdata-disk: no attached disk at ${DEVICE}; refusing to start postgresql against ephemeral storage" >&2
  exit 1
fi

if ! blkid "$DEVICE" >/dev/null 2>&1; then
  echo "pgdata-disk: ${DEVICE} is unformatted; formatting ext4 (first boot)"
  mkfs.ext4 -F -m 0 "$DEVICE"
fi

install -d -m 0755 "$MOUNT_POINT"
if ! mountpoint -q "$MOUNT_POINT"; then
  mount "$DEVICE" "$MOUNT_POINT"
fi

if ! grep -qs "^${DEVICE} " /etc/fstab; then
  echo "${DEVICE} ${MOUNT_POINT} ext4 defaults,nofail 0 2" >> /etc/fstab
fi

if [ ! -d "$PGDATA" ]; then
  echo "pgdata-disk: ${PGDATA} does not exist yet; migrating on-image cluster from ${DEFAULT_PGDATA}"
  systemctl stop "postgresql@${POSTGRES_VERSION}-main" 2>/dev/null || true
  install -d -m 0700 -o postgres -g postgres "${MOUNT_POINT}/${POSTGRES_VERSION}"
  rsync -a "${DEFAULT_PGDATA}/" "${PGDATA}/"
  chown -R postgres:postgres "${MOUNT_POINT}/${POSTGRES_VERSION}"
  chmod 700 "$PGDATA"
fi

if ! grep -q "^data_directory = '${PGDATA}'" "$PG_CONF"; then
  sed -i "\|^data_directory\s*=|d" "$PG_CONF"
  echo "data_directory = '${PGDATA}'" >> "$PG_CONF"
fi
