#!/usr/bin/env bash
# Not wired into gsa.pkr.hcl yet (no app source upload until gsa_opportunities
# has real source — see the commented-out provisioners in gsa.pkr.hcl).
# Adjust the manage.py/wsgi assumptions here once the app's actual framework
# and entrypoint are known.
set -euxo pipefail

rm -rf /opt/app/src
mv /tmp/app /opt/app/src
chown -R app:app /opt/app/src

sudo -u app /opt/app/venv/bin/pip install --no-cache-dir -r /opt/app/src/requirements.txt

install -m 0755 -o root -g root /tmp/gunicorn.conf.py /opt/app/gunicorn.conf.py
