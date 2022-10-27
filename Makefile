SHELL := /bin/bash -euo pipefail

PLATFORM = $(shell uname | tr [A-Z] [a-z])

# ----------------------------------------------------------------------------------------------------------------------
# Make Configuration
# ----------------------------------------------------------------------------------------------------------------------

ifndef VERBOSE
.SILENT:
endif

INTERACTIVE := $(shell [ -t 0 ] && echo 1)
ifeq ($(INTERACTIVE),1)
M := $(shell printf "\033[34;1m▶\033[0m")
else
M := =>
endif

# The CI system will set this to true if it is running in a CI environment.
export CI ?= false

# If value is true, than publish charts to remote repo would be skipped.
export DRY_RUN ?= false

# ----------------------------------------------------------------------------------------------------------------------
# Directories
# ----------------------------------------------------------------------------------------------------------------------

REPO_ROOT := $(CURDIR)

LOCAL_DIR   := $(REPO_ROOT)/.local
HELM_DIR    := $(LOCAL_DIR)/.helm
HACK_DIR    := $(REPO_ROOT)/hack

# ----------------------------------------------------------------------------------------------------------------------
# Go configuration
# ----------------------------------------------------------------------------------------------------------------------

GOARCH ?= $(shell go env GOARCH)
GOOS ?= $(shell go env GOOS)

# Explicitly override GOBIN so it does not inherit from the environment - this allows for a truly
# self-contained build environment for the project.
override GOBIN := $(LOCAL_DIR)/bin
export GOBIN
export PATH := $(GOBIN):$(PATH)

# ----------------------------------------------------------------------------------------------------------------------
# Helm configuration
# ----------------------------------------------------------------------------------------------------------------------

export HELM_CONFIG_HOME=$(HELM_DIR)/config
export HELM_CACHE_HOME=$(HELM_DIR)/cache
export HELM_DATA_HOME=$(HELM_DIR)/data

# ----------------------------------------------------------------------------------------------------------------------
# Chart Testing configuration
# ----------------------------------------------------------------------------------------------------------------------

export CT_LINT_CONF=config/ct/lintconf.yaml
export CT_CHART_YAML_SCHEMA=config/ct/chart_schema.yaml

# ----------------------------------------------------------------------------------------------------------------------
# Git configuration
# ----------------------------------------------------------------------------------------------------------------------

GIT_REF ?= $(shell git rev-parse HEAD)
GIT_REMOTE_NAME ?= origin
GIT_REMOTE_URL ?= $(shell git remote get-url ${GIT_REMOTE_NAME})

# Extract the github user from the ${GIT_REMOTE_NAME} remote url.
# This let's the 'publish' task work with forks.
# Supports both SSH and HTTPS git url formats:
# - https://github.com/mesosphere/charts.git
# - git@github.com:mesosphere/charts.git
GITHUB_USER := $(shell git remote get-url ${GIT_REMOTE_NAME} | sed -E 's|.*github.com[/:]([^/]+)/charts.*|\1|')

# ----------------------------------------------------------------------------------------------------------------------
# Charts configuration
# ----------------------------------------------------------------------------------------------------------------------

STABLE_CHARTS = $(wildcard stable/*/Chart.yaml)
STABLE_TARGETS = $(shell hack/chart_destination.sh $(STABLE_CHARTS))
STAGING_CHARTS = $(wildcard staging/*/Chart.yaml)
STAGING_TARGETS = $(shell hack/chart_destination.sh $(STAGING_CHARTS))

REPO_BASE_URL := https://$(GITHUB_USER).github.io/charts

# ----------------------------------------------------------------------------------------------------------------------
# Asdf configuration
# ----------------------------------------------------------------------------------------------------------------------

ifeq ($(shell command -v asdf),)
  $(error "This repo requires asdf - see https://asdf-vm.com/guide/getting-started.html for instructions to install")
endif

## (aweris) Quick and dirty solution to be able to run the test/e2e-kind.sh script with out changing the script.
## Space end of the variable is important. I was too lazy to write a regex to match "helm" and "helm-ct" properly.
## TODO: Remove this once update the test/e2e-kind.sh script to use the asdf version
HELM_VERSION := v$(shell cat .tool-versions | grep "helm " | cut -d' ' -f2)
CT_VERSION := v$(shell cat .tool-versions | grep "helm-ct " | cut -d' ' -f2)

# ----------------------------------------------------------------------------------------------------------------------
# Scripts
# ----------------------------------------------------------------------------------------------------------------------

# publish script specific variables, duplicated from publish.sh to allow customizing them
DRY_RUN          ?= true
BRANCH           ?= gh-pages
CT_CHART_DIRS    ?= stable,staging
CT_TARGET_BRANCH ?= master
CT_SINCE         ?= HEAD~1
COMMIT_USERNAME  ?= $(shell git config user.name)
COMMIT_EMAIL 	 ?= $(shell git config user.email)
COMMIT_MESSAGE   ?= $(shell git log -1 --no-show-signature --pretty=format:'%B') # Use the commit message from the last commit
HELM_LINT        ?= true
HELM_DEP_UPDATE  ?= true

PUBLISH_ENV := CI="$(CI)" \
	DRY_RUN="$(DRY_RUN)" \
	CT_CHART_DIRS="$(CT_CHART_DIRS)" \
	CT_TARGET_BRANCH="$(CT_TARGET_BRANCH)" \
	CT_SINCE="$(CT_SINCE)" \
	BRANCH="$(BRANCH)" \
	GIT_REMOTE_URL="$(GIT_REMOTE_URL)" \
	COMMIT_USERNAME="$(COMMIT_USERNAME)" \
	COMMIT_EMAIL="$(COMMIT_EMAIL)" \
	COMMIT_MESSAGE="$(COMMIT_MESSAGE)" \
	HELM_LINT="$(HELM_LINT)" \
	HELM_DEP_UPDATE="$(HELM_DEP_UPDATE)" \
	HELM_CHARTS_URL="$(REPO_BASE_URL)"

# ----------------------------------------------------------------------------------------------------------------------
# Targets
# ----------------------------------------------------------------------------------------------------------------------

.SECONDEXPANSION:

.DEFAULT_GOAL := help

.PHONY: clean
clean: ## Remove all build artifacts
clean: ; $(info $(M) cleaning build artifacts)
	rm -rf gh-pages bin .local

.PHONY: publish
publish: ## Publishes changed helm charts to gh-pages
publish: export LC_COLLATE := C
publish: export TZ := UTC
publish: tools.install.helm tools.install.helm-ct ; $(info $(M) publishing charts)
	$(HACK_DIR)/charts/publish.sh $(PUBLISH_ENV)

.PHONY: ct.lint
ct.lint: ## Run chart-testing (ct) linter against charts.
ct.lint: tools.install.helm ; $(info $(M) running ct lint)
ifneq (,$(wildcard /teamcity/system/git))
	git fetch ${GIT_REMOTE_NAME} master
endif
	ct lint --remote=${GIT_REMOTE_NAME} --debug

.PHONY: ct.test
ct.test: ## Runs e2e tests for charts
ct.test: tools.install.helm ; $(info $(M) running e2e test(kind))
ifneq (,$(wildcard /teamcity/system/git))
	git fetch ${GIT_REMOTE_NAME} master
endif
	GIT_REMOTE_NAME=$(GIT_REMOTE_NAME) test/e2e-kind.sh $(CT_VERSION) $(HELM_VERSION) --remote=$(GIT_REMOTE_NAME)

.PHONY: help
help: ## Shows this help message
	awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_\-.]+:.*?##/ { printf "  \033[36m%-15s\033[0m\t %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ----------------------------------------------------------------------------------------------------------------------
# Tools
# ----------------------------------------------------------------------------------------------------------------------

define install_tool
	$(if $(1), \
		(asdf plugin list 2>/dev/null | grep -E '^$(1)$$' &>/dev/null) || asdf plugin add $(1), \
		grep -Eo '^[^#]\S+' $(REPO_ROOT)/.tool-versions | \
			xargs $(if $(VERBOSE),--verbose) -I{} bash -ec '(asdf plugin list 2>/dev/null | grep -E "^{}$$" &>/dev/null) || \
														asdf plugin add {}' \
	)
	asdf install $1
endef

.PHONY: tools.install
tools.install: ## Install all tools
tools.install: ; $(info $(M) installing all tools)
	$(call install_tool,)

.PHONY: tools.install.%
tools.install.%: ## Install specific tool
tools.install.%: ; $(info $(M) installing $*)
	$(call install_tool,$*)

.PHONY: tools.upgrade
# ASDF plugins use different env vars for GitHub authentication when querying releases. Try to
# handle this nicely by specifying some of the known env vars to prevent rate limiting.
ifdef GITHUB_USER_TOKEN
tools.upgrade: export GITHUB_API_TOKEN=$(GITHUB_USER_TOKEN)
else
ifdef GITHUB_TOKEN
tools.upgrade: export GITHUB_API_TOKEN=$(GITHUB_TOKEN)
endif
endif
tools.upgrade: export OAUTH_TOKEN=$(GITHUB_API_TOKEN)
tools.upgrade: ## Upgrades all tools to latest available versions
tools.upgrade: ; $(info $(M) upgrading all tools to latest available versions)
	grep -Eo '^[^#]\S+' $(REPO_ROOT)/.tool-versions | \
						xargs $(if $(VERBOSE),--verbose) -I{} bash -ec '(asdf plugin list 2>/dev/null | grep -E "^{}$$" &>/dev/null) || \
																 asdf plugin add {}'
	grep -v '# FREEZE' $(REPO_ROOT)/.tool-versions | \
		grep -Eo '^[^#]\S+' | \
		xargs $(if $(VERBOSE),--verbose) -I{} bash -ec '\
			export VERSION="$$( \
				asdf list all {} | \
				grep -vE "(^Available versions:|-src|-dev|-latest|-stm|[-\\.]rc|-alpha|-beta|[-\\.]pre|-next|(a|b|c)[0-9]+|snapshot|master)" | \
				tail -1 \
			)" && asdf install {} $${VERSION} && asdf local {} $${VERSION}'
