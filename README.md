# gsa_opportunities-packer

Packer project that builds a GCE image for `gsa_opportunities`. Modeled on
`gratefulforu`'s `api-packer`: gunicorn, a Celery worker, Celery beat,
PostgreSQL, Redis, and nginx (reverse proxy + TLS via certbot) all run
natively (no Docker) on the same VM, managed by systemd.

Unlike `gratefulforu`'s `api` + separate `frontend` repo/build, there's no
separate frontend here — `gsa_opportunities` is a normal Django app that
renders its own templates and serves its own static files, so nginx's only
job is reverse-proxying to gunicorn and serving `/static/` directly. Also
unlike `gratefulforu`, this project targets a single environment (`prod`) —
no dev/prod split.

## What gets baked in

- Ubuntu 22.04 LTS base
- Python 3.13 (via deadsnakes PPA) + a venv at `/opt/app/venv`
- PostgreSQL 16 (via the PGDG apt repo), listening on localhost only
- Redis 7 (Ubuntu's packaged version), listening on localhost only
- nginx + certbot (reverse proxy to gunicorn, TLS via Let's Encrypt)
- systemd units: `app-config.service` (oneshot bootstrap), `gunicorn.service`,
  `celery-worker.service`, `celery-beat.service`, `webproxy-setup.service`,
  `app-deploy-check.timer` (self-healing redeploy checks)

**App source isn't baked into the image.** `bootstrap.sh` clones
`FedRank/gsa_opportunities` from GitHub at boot, over SSH using a read-only
deploy key fetched from Secret Manager (see
`../pulumi-infrastructure-gcp/infra/secrets.py`). This means a normal `git
push` to the tracked branch (`app-git-ref` instance metadata, default `main`)
is enough to ship a change — `app-deploy-check.timer` picks it up within 5
minutes without needing a rebuild/replace, and `pulumi up` (which replaces
the instance for a new *image*) always re-clones the latest commit on that
branch regardless.

**Secrets and runtime config are never baked into the image.** They're
fetched at boot from an `app-env` instance metadata key by
`/opt/app/bin/bootstrap.sh` (falling back to a self-generated dev config
persisted on the pgdata disk if that key isn't set), which then creates the
Postgres role/database, runs `manage.py migrate`, and `manage.py
collectstatic` before gunicorn/Celery are allowed to start (systemd
`After=`/`Requires=` on `app-config.service` enforces the order).

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
make validate   # PROJECT_ID defaults to nwrion-management's project number
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

This is normally handled entirely by `../pulumi-infrastructure-gcp`'s
`infra/compute.py` (`githubTokenAccess`, `appGitRef`, `hostnames` instance
config), which wires up the deploy-key secret access, `app-git-ref` and
`web-hostnames` metadata, and DNS records automatically. Doing it by hand:

```
gcloud compute instances create gsa-opportunities-1 \
  --image-family=gsa-opportunities-app \
  --image-project=nwrion-management \
  --machine-type=e2-medium \
  --metadata-from-file=app-env=./production.env \
  --metadata=app-git-ref=main,github-deploy-key-secret-id=<secret-id>,web-hostnames='{"api":"api.nwrion.com","app":"app.nwrion.com"}',letsencrypt-email=admin@nwrion.com \
  --service-account=<sa-with-secretAccessor-on-the-deploy-key-secret>
```

On first boot, `app-config.service` clones the app, fetches the `app-env`
metadata key to `/opt/app/.env`, provisions the Postgres role/database, and
runs migrations + collectstatic; `webproxy-setup.service` configures nginx
+ TLS for each hostname in `web-hostnames`; `gunicorn.service` then serves
the app behind nginx. Push a new commit to the tracked branch and
`app-deploy-check.timer` redeploys it within 5 minutes — no rebuild needed.

## Notes / things to revisit

- Postgres and Redis are self-hosted on the same VM as the app. If this later
  moves to managed Cloud SQL / Memorystore, drop `scripts/03-postgres.sh` /
  `04-redis.sh` and point `app-env`'s `POSTGRES_HOST` / `CELERY_BROKER_URL` at
  those instead.
- No firewall/network/DNS resources are created here — that belongs in
  `../pulumi-infrastructure-gcp`, which also owns the deploy-key Secret
  Manager secret and the instance that uses this image.

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
module, which trusts both this repo (`FedRank/gsa_opportunities-packer`)
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
