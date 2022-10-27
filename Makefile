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

# ----------------------------------------------------------------------------------------------------------------------
# Directories
# ----------------------------------------------------------------------------------------------------------------------

REPO_ROOT := $(CURDIR)

LOCAL_DIR := $(REPO_ROOT)/.local
HELM_DIR  := $(LOCAL_DIR)/.helm

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
# Targets
# ----------------------------------------------------------------------------------------------------------------------

.SECONDEXPANSION:

.PHONY: all
all: ## Builds all chart repositories
all: stagingrepo stablerepo

.PHONY: clean
clean: ## Remove all build artifacts
clean: ; $(info $(M) cleaning build artifacts)
	rm -rf gh-pages bin .local

.PHONY: stagingrepo
stagingrepo: ## Build the staging repository
stagingrepo: $(STAGING_TARGETS) | gh-pages/staging/index.yaml ; $(info $(M) finished building staging charts)

.PHONY: stablerepo
stablerepo: ## Build the stablerepo repository
stablerepo: $(STABLE_TARGETS) | gh-pages/stable/index.yaml ; $(info $(M) finished building stable charts)

.PHONY: publish
publish: ## Publishes changed helm charts to gh-pages
publish: export LC_COLLATE := C
publish: export TZ := UTC
publish: ; $(info $(M) publishing charts)
ifeq ($(PLATFORM),darwin)
	$(warning The publish task uses the GNU executables 'tar' and 'find', macOS ships with BSD ones installed by default.)
endif

	-git remote add publish $(GIT_REMOTE_URL) &>/dev/null
	rm -rf gh-pages
	git fetch publish gh-pages
	git worktree add gh-pages/ publish/gh-pages
	$(MAKE) GIT_REF=$(GIT_REF) all
# Check if any existing files other than repo index.yamls have been modified or deleted and exit if
# there are, showing the list of changed files for easier troubleshooting.
	cd gh-pages && \
		export CHANGED=$$(git ls-files -md | grep -v index.yaml) && \
		( \
			[[ -z "$${CHANGED}" ]] || \
			(printf "Aborting: following changed or deleted files:\n\n$${CHANGED}" && exit 1) \
		)

# Be doubly safe by only adding new files and index.yaml files to prevent overwrites.
	export LAST_COMMIT_MESSAGE="$$(git log -1 --no-show-signature --pretty=format:'%B')" && \
	cd gh-pages && \
		git add $$(git ls-files -o --exclude-standard) staging/index.yaml stable/index.yaml && \
		git commit -m "$${LAST_COMMIT_MESSAGE}" && \
		git push publish HEAD:gh-pages
	git worktree remove gh-pages/
	rm -rf gh-pages

# Deterministically create helm packages by:
#
# - Using `helm package` to create the initial package (useful for including chart dependencies
#   properly)
# - Untarring the package
# - Recreate the package using `tar`, speficying time of the last git commit to the package
#   source as the files' mtime, as well as ordering files deterministically, meaning that unchanged
#   content will result in the same output package
# - Use `gzip -n` to prevent any timestamps being added to `gzip` headers in archive.
$(STABLE_TARGETS) $(STAGING_TARGETS): tools.install.helm $$(shell find $$(shell echo $$@ | sed -E 's|gh-pages/((stable\|staging)/.+)-([0-9]+.?)+\.tgz|\1|') -type f)
	@mkdir -p $(shell dirname $@)
	$(eval PACKAGE_SRC := $(shell echo $@ | sed 's@gh-pages/\(.*\)-[v0-9][0-9.]*.tgz@\1@'))
	$(eval UNPACKED_TMP := $(shell mktemp -d))
	$(info $(M)$(M) building $(PACKAGE_SRC))
	helm package $(PACKAGE_SRC) -d $(shell dirname $@)
	tar -xzmf $@ -C $(UNPACKED_TMP)
	tar -c \
			--owner=root:0 --group=root:0 --numeric-owner \
			--no-recursion \
			--mtime="@$(shell git log -1 --no-show-signature --format="%at" $(GIT_REF) -- $(PACKAGE_SRC))" \
			-C $(UNPACKED_TMP) \
			$$(find $(UNPACKED_TMP) -printf '%P\n' | sort) | gzip -n > $@
	rm -rf $(UNPACKED_TMP)

%/index.yaml: tools.install.helm $(STABLE_TARGETS) $(STAGING_TARGETS)
%/index.yaml: $$(wildcard $$(dir $$@)*.tgz)
	@mkdir -p $(patsubst %/index.yaml,%,$@)
	helm repo index $(patsubst %/index.yaml,%,$@) --url=$(REPO_BASE_URL)/$(patsubst gh-pages/%index.yaml,%,$@)

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

.PHONY: lint
lint: ## Alias for ct.lint
lint: ct.lint

.PHONY: test.helm
test.helm: ## Alias for ct.test
test.helm: ct.test

.PHONY: test
test: ## Alias for ct.test
test: ct.test

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
