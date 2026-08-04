packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

locals {
  build_timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
  image_name      = "gsa-opportunities-app-${local.build_timestamp}"
}

source "googlecompute" "app" {
  project_id              = var.project_id
  zone                    = var.zone
  network                 = var.network
  subnetwork              = var.subnetwork
  use_internal_ip         = var.use_internal_ip
  source_image_family     = var.source_image_family
  source_image_project_id = [var.source_image_project]
  machine_type            = var.machine_type
  disk_size               = var.disk_size
  disk_type               = "pd-ssd"

  image_name        = local.image_name
  image_family      = var.image_family
  image_description = "Self-contained VM image for gsa_opportunities: gunicorn + Celery worker/beat + local PostgreSQL ${var.postgres_version} + Redis + nginx (reverse proxy), all managed by systemd."
  image_labels = {
    app   = "gsa-opportunities-app"
    built = replace(local.build_timestamp, "-", "")
  }

  ssh_username             = var.ssh_username
  ssh_file_transfer_method = "sftp"
  tags                     = ["packer-build", "gsa-opportunities-app"]
}

build {
  sources = ["source.googlecompute.app"]

  # Packer's SSH communicator connects as soon as sshd is up, which can race
  # ahead of cloud-init's first-boot finalization - notably, cloud-init is
  # what rewrites /etc/apt/sources.list to GCE's fast zone-local mirror
  # (us-central1.gce.archive.ubuntu.com); running apt-get before that's done
  # can hit an inconsistent/incomplete package index (e.g. build-essential
  # resolving with no candidate) even though apt-get update itself succeeds.
  provisioner "shell" {
    inline = ["sudo cloud-init status --wait"]
  }

  # App source isn't baked into the image - bootstrap.sh clones it from
  # GitHub at boot over SSH (read-only deploy key), see app-config.service.
  # This also sidesteps needing cross-repo checkout auth in this repo's CI,
  # since Packer never touches ../gsa_opportunities at all.

  # SFTP (unlike SCP) won't create the destination directory for a directory
  # upload, so it has to exist before the "file" provisioner below runs.
  provisioner "shell" {
    inline = ["mkdir -p /tmp/systemd"]
  }

  provisioner "file" {
    source      = "files/systemd/"
    destination = "/tmp/systemd"
  }

  provisioner "file" {
    source      = "files/bin/bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "file" {
    source      = "files/bin/pgdata-disk.sh"
    destination = "/tmp/pgdata-disk.sh"
  }

  provisioner "file" {
    source      = "files/bin/webproxy-setup.sh"
    destination = "/tmp/webproxy-setup.sh"
  }

  provisioner "file" {
    source      = "files/bin/deploy-check.sh"
    destination = "/tmp/deploy-check.sh"
  }

  provisioner "file" {
    source      = "files/bin/lib-github-deploy-key.sh"
    destination = "/tmp/lib-github-deploy-key.sh"
  }

  provisioner "file" {
    source      = "files/gunicorn/gunicorn.conf.py"
    destination = "/tmp/gunicorn.conf.py"
  }

  provisioner "shell" {
    scripts = [
      "scripts/01-system.sh",
      "scripts/02-python.sh",
      "scripts/03-postgres.sh",
      "scripts/04-redis.sh",
      "scripts/05-webproxy.sh",
      "scripts/06-systemd.sh",
    ]
    environment_vars = [
      "PYTHON_VERSION=${var.python_version}",
      "POSTGRES_VERSION=${var.postgres_version}",
    ]
    execute_command = "sudo -E bash '{{.Path}}'"
  }

  provisioner "shell" {
    scripts         = ["scripts/99-cleanup.sh"]
    execute_command = "sudo -E bash '{{.Path}}'"
  }
}
