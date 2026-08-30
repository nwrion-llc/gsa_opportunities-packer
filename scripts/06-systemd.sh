#!/usr/bin/env bash
set -euxo pipefail

install -m 0644 -o root -g root /tmp/lib-secrets.sh /opt/bin/lib-secrets.sh

install -m 0755 -o root -g root /tmp/bootstrap.sh /opt/app/bin/bootstrap.sh
install -m 0755 -o root -g root /tmp/pgdata-disk.sh /opt/app/bin/pgdata-disk.sh
install -m 0755 -o root -g root /tmp/webproxy-setup.sh /opt/app/bin/webproxy-setup.sh
install -m 0755 -o root -g root /tmp/deploy-check.sh /opt/app/bin/deploy-check.sh
install -m 0755 -o root -g root /tmp/gunicorn.conf.py /opt/app/gunicorn.conf.py
install -m 0755 -o root -g root /tmp/frontend-deploy.sh /opt/frontend/bin/frontend-deploy.sh
install -m 0755 -o root -g root /tmp/frontend-deploy-check.sh /opt/frontend/bin/frontend-deploy-check.sh

install -m 0644 -o root -g root /tmp/systemd/app-config.service /etc/systemd/system/app-config.service
install -m 0644 -o root -g root /tmp/systemd/gunicorn.service /etc/systemd/system/gunicorn.service
install -m 0644 -o root -g root /tmp/systemd/celery-worker.service /etc/systemd/system/celery-worker.service
install -m 0644 -o root -g root /tmp/systemd/celery-beat.service /etc/systemd/system/celery-beat.service
install -m 0644 -o root -g root /tmp/systemd/pgdata-disk.service /etc/systemd/system/pgdata-disk.service
install -m 0644 -o root -g root /tmp/systemd/webproxy-setup.service /etc/systemd/system/webproxy-setup.service
install -m 0644 -o root -g root /tmp/systemd/app-deploy-check.service /etc/systemd/system/app-deploy-check.service
install -m 0644 -o root -g root /tmp/systemd/app-deploy-check.timer /etc/systemd/system/app-deploy-check.timer
install -m 0644 -o root -g root /tmp/systemd/frontend-deploy.service /etc/systemd/system/frontend-deploy.service
install -m 0644 -o root -g root /tmp/systemd/frontend-deploy-check.service /etc/systemd/system/frontend-deploy-check.service
install -m 0644 -o root -g root /tmp/systemd/frontend-deploy-check.timer /etc/systemd/system/frontend-deploy-check.timer

systemctl daemon-reload

# Enabled but not started here — app-config.service needs the 'app-env' and
# 'github-deploy-key-secret-id' instance metadata keys, pgdata-disk.service
# needs the attached "pgdata" disk, webproxy-setup.service needs the
# 'web-hostnames' metadata key, and frontend-deploy.service needs that same
# 'github-deploy-key-secret-id' key (reused - see frontend-deploy.sh), none
# of which exist until the real instance boots. app-deploy-check.timer and
# frontend-deploy-check.timer are safe to enable outright - their first runs
# are gated on app-config.service/frontend-deploy.service already having run
# once.
systemctl enable app-config.service gunicorn.service celery-worker.service celery-beat.service pgdata-disk.service webproxy-setup.service app-deploy-check.timer frontend-deploy.service frontend-deploy-check.timer
