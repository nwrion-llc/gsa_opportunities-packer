# Single-environment project (no dev/prod split) — everything targets prod.
# 318224876302 is nwrion-management's numeric project number.
PROJECT_ID ?= 318224876302
VAR_FILE   ?=

PACKER_VARS := $(if $(PROJECT_ID),-var project_id=$(PROJECT_ID))
PACKER_VARS += $(if $(VAR_FILE),-var-file=$(VAR_FILE))

.PHONY: help init fmt fmt-check shellcheck check validate build build-debug clean tag-release

help:
	@echo "Available targets:"
	@echo "  init          Install/update required Packer plugins"
	@echo "  fmt           Reformat all .pkr.hcl files"
	@echo "  fmt-check     Check formatting without modifying files"
	@echo "  shellcheck    Lint provisioning scripts with shellcheck"
	@echo "  check         Run fmt-check + shellcheck (run this before committing)"
	@echo "  validate      Validate the Packer config (needs PROJECT_ID or VAR_FILE)"
	@echo "  build         Build the GCE image (needs PROJECT_ID or VAR_FILE)"
	@echo "  build-debug   Build with Packer debug mode (pauses between steps, keeps VM on failure)"
	@echo "  clean         Remove build scratch state (crash logs, manifests)"
	@echo "  tag-release TAG=v1.2.3   # Tag and push a release (triggers the Production workflow)"
	@echo ""
	@echo "PROJECT_ID defaults to 318224876302 (nwrion-management). Override with PROJECT_ID=<gcp-project>"
	@echo "or point at a var file with VAR_FILE=<file>."
	@echo ""
	@echo "Usage: make validate"
	@echo "       make build"
	@echo "       make build PROJECT_ID=some-other-project"
	@echo "       make build VAR_FILE=local.pkrvars.hcl"

init:
	packer init .

fmt:
	packer fmt .

fmt-check:
	packer fmt -check -diff .

shellcheck:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "error: shellcheck not found (brew install shellcheck / apt-get install shellcheck)" >&2; exit 1; \
	fi
	shellcheck scripts/*.sh files/bin/*.sh

check: fmt-check shellcheck

validate: fmt-check
	@if [ -z "$(PROJECT_ID)" ] && [ -z "$(VAR_FILE)" ]; then \
		echo "error: no PROJECT_ID or VAR_FILE given" >&2; \
		echo "       set PROJECT_ID=<gcp-project>, or VAR_FILE=<file>" >&2; \
		exit 1; \
	fi
	packer validate $(PACKER_VARS) .

build:
	@if [ -z "$(PROJECT_ID)" ] && [ -z "$(VAR_FILE)" ]; then \
		echo "error: no PROJECT_ID or VAR_FILE given" >&2; \
		echo "       set PROJECT_ID=<gcp-project>, or VAR_FILE=<file>" >&2; \
		exit 1; \
	fi
	packer build $(PACKER_VARS) .

build-debug:
	@if [ -z "$(PROJECT_ID)" ] && [ -z "$(VAR_FILE)" ]; then \
		echo "error: no PROJECT_ID or VAR_FILE given" >&2; \
		echo "       set PROJECT_ID=<gcp-project>, or VAR_FILE=<file>" >&2; \
		exit 1; \
	fi
	packer build -debug $(PACKER_VARS) .

clean:
	rm -rf crash.log packer-manifest.json

tag-release:
	@if [ "$$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then \
	  echo "Error: tag-release can only be run on the main branch."; \
	  exit 1; \
	fi; \
	if [ -z "$(TAG)" ]; then \
	  TAG=$$(git tag --list 'v*.*.*' | sort -V | tail -n1); \
	  if [ -z "$$TAG" ]; then \
	    TAG=v1.0.0; \
	  else \
	    MAJOR=$$(echo $$TAG | cut -d. -f1 | tr -d 'v'); \
	    MINOR=$$(echo $$TAG | cut -d. -f2); \
	    PATCH=$$(echo $$TAG | cut -d. -f3); \
	    PATCH=$$((PATCH + 1)); \
	    TAG="v$${MAJOR}.$${MINOR}.$${PATCH}"; \
	  fi; \
	  echo "No TAG provided, using next tag: $$TAG"; \
	fi; \
	git tag -a $$TAG -m "Release $$TAG"; \
	git push origin $$TAG
