# gsa_opportunities-packer

Packer project that builds a GCE image for `gsa_opportunities`. Modeled on
`gratefulforu`'s `api-packer`: gunicorn, a Celery worker, Celery beat,
PostgreSQL, and Redis all run natively (no Docker) on the same VM, managed by
systemd.

**This is currently a template.** `../gsa_opportunities` has no app source
yet, so the Django/gunicorn/Celery assumptions baked into the scripts and
systemd units here are placeholders carried over from the source project —
adjust `scripts/05-app.sh`, `files/bin/bootstrap.sh`, and the systemd
`ExecStart` lines once the real app framework and entrypoint are decided.

Unlike `gratefulforu`, this project targets a single environment (`prod`) —
no dev/prod split.

## What gets baked in

- Ubuntu 22.04 LTS base
- Python 3.13 (via deadsnakes PPA) + a venv at `/opt/app/venv`
- PostgreSQL 16 (via the PGDG apt repo), listening on localhost only
- Redis 7 (Ubuntu's packaged version), listening on localhost only
- systemd units: `app-config.service` (oneshot bootstrap), `gunicorn.service`,
  `celery-worker.service`, `celery-beat.service`

App source upload is disabled for now (see the commented-out provisioners in
`gsa.pkr.hcl` and `scripts/05-app.sh`) since there's no app to upload yet.

**Secrets and runtime config are never baked into the image.** They're meant
to be fetched at boot from an `app-env` instance metadata key by
`/opt/app/bin/bootstrap.sh`, which creates the Postgres role/database if
needed (the actual app migration step is a TODO placeholder until the
framework is chosen).

## Prerequisites

- [Packer](https://developer.hashicorp.com/packer) >= 1.9
- The `nwrion-management` GCP project (or another project) with the Compute
  Engine API enabled
- Credentials Packer can use — either `gcloud auth application-default login`
  locally, or a service account key via `GOOGLE_APPLICATION_CREDENTIALS`
- IAM roles for the build identity: `roles/compute.instanceAdmin.v1` and
  `roles/iam.serviceAccountUser` (Packer spins up and tears down a temporary
  build VM)

## Build

Via `make` (see `make help` for the full target list):

```
cd gsa_opportunities-packer
make check    # fmt-check + shellcheck — run before committing
make init
make validate   # PROJECT_ID defaults to nwrion-management
make build
```

Or with the Packer CLI directly:

```
cd gsa_opportunities-packer
packer init .
packer validate -var project_id=nwrion-management .
packer build -var project_id=nwrion-management .
```

Override any other variable in `variables.pkr.hcl` the same way
(`-var zone=us-west1-a`), or drop a `local.pkrvars.hcl` file (see
`local.pkrvars.hcl.example`) and pass `VAR_FILE=local.pkrvars.hcl` (make) /
`-var-file=local.pkrvars.hcl` (packer).

The resulting image is published to the `gsa-opportunities-app` image family
(`var.image_family`), so instances/templates can always track
`--image-family=gsa-opportunities-app --image-project=YOUR_PROJECT_ID`
without hardcoding a specific image name.

## Deploying an instance from the image

Set the `app-env` metadata key to `KEY=VALUE` lines (one per line) with real
runtime config:

```
gcloud compute instances create gsa-opportunities-1 \
  --image-family=gsa-opportunities-app \
  --image-project=nwrion-management \
  --machine-type=e2-medium \
  --metadata-from-file=app-env=./production.env
```

On first boot, `app-config.service` fetches that metadata key to
`/opt/app/.env` and provisions the Postgres role/database; `gunicorn.service`
then serves the app on port 8000 (once there's actual app source in the
image). Re-running `systemctl restart app-config gunicorn celery-worker
celery-beat` after updating the metadata key re-applies config without
rebuilding the image.

## Notes / things to revisit

- Fill in `../gsa_opportunities` with real app source, then re-enable the
  `shell-local`/`file` provisioners in `gsa.pkr.hcl` and `scripts/05-app.sh`.
- `files/bin/bootstrap.sh`'s migration step and the systemd units'
  `ExecStart` lines assume a Django-style `manage.py` / `config.wsgi` /
  `config` Celery app layout (copied from `gratefulforu`) — update these once
  the real framework is known.
- Postgres and Redis are self-hosted on the same VM as the app. If this later
  moves to managed Cloud SQL / Memorystore, drop `scripts/03-postgres.sh` /
  `04-redis.sh` and point `app-env`'s `POSTGRES_HOST` / `CELERY_BROKER_URL` at
  those instead.
- No firewall/network resources are created here — that belongs in
  `../pulumi-infrastructure-gcp` alongside whatever provisions the
  instance/instance group that uses this image.

## CI/CD

| Trigger | Workflow | Action |
|---|---|---|
| PR into `main` | CI | `packer validate` |
| Push to `main` | CI | `packer build` (publishes image) |
| Tag `v*.*` / `v*.*.*` | Release | `packer build` (publishes image) |

Both workflows call the reusable `call-packer.yml`, which authenticates to
GCP via Workload Identity Federation and runs `make check` (fmt-check +
shellcheck), then `make validate` (PRs) or `make build` (pushes/tags) against
the `prod` GitHub Environment.

The `prod` GitHub Environment needs these repo secrets configured
(Settings → Environments):

- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_CI_SERVICE_ACCOUNT`
- `GCP_PROJECT_ID` — should be `nwrion-management` (or wherever this should
  build/publish images)

The workload identity pool/provider and CI service account (`pulumi-ci@nwrion-management.iam.gserviceaccount.com`)
are provisioned by `../pulumi-infrastructure-gcp`'s `infra/github_oidc.py`
module, which trusts both this repo (`nwrion-llc/gsa_opportunities-packer`)
and `nwrion-llc/pulumi-infrastructure-gcp` for the `prod` GitHub Environment.
After running `pulumi up` there, read the actual values with:

```
cd ../pulumi-infrastructure-gcp
make output
```

`github_oidc_service_account_email` → `GCP_CI_SERVICE_ACCOUNT`,
`github_oidc_wif_provider` → `GCP_WORKLOAD_IDENTITY_PROVIDER`.

`make tag-release TAG=v1.2.3` (must be run on `main`) tags and pushes,
triggering the Release workflow.
