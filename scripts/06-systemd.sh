#!/usr/bin/env bash
set -euxo pipefail

install -m 0755 -o root -g root /tmp/bootstrap.sh /opt/app/bin/bootstrap.sh
install -m 0755 -o root -g root /tmp/pgdata-disk.sh /opt/app/bin/pgdata-disk.sh

install -m 0644 -o root -g root /tmp/systemd/app-config.service /etc/systemd/system/app-config.service
install -m 0644 -o root -g root /tmp/systemd/gunicorn.service /etc/systemd/system/gunicorn.service
install -m 0644 -o root -g root /tmp/systemd/celery-worker.service /etc/systemd/system/celery-worker.service
install -m 0644 -o root -g root /tmp/systemd/celery-beat.service /etc/systemd/system/celery-beat.service
install -m 0644 -o root -g root /tmp/systemd/pgdata-disk.service /etc/systemd/system/pgdata-disk.service

systemctl daemon-reload

# Enabled but not started here — app-config.service needs the 'app-env'
# instance metadata key, and pgdata-disk.service needs the attached "pgdata"
# disk, neither of which exist until the real instance boots.
systemctl enable app-config.service gunicorn.service celery-worker.service celery-beat.service pgdata-disk.service
