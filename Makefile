SHELL := /bin/bash -euo pipefail

PLATFORM = $(shell uname | tr [A-Z] [a-z])

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

CT_VERSION ?= v3.5.1
HELM_VERSION ?= v3.6.3
HELM_BIN ?= bin/$(GOOS)/$(GOARCH)/helm-$(HELM_VERSION)

export HELM_CONFIG_HOME=$(HELM_DIR)/config
export HELM_CACHE_HOME=$(HELM_DIR)/cache
export HELM_DATA_HOME=$(HELM_DIR)/data

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
# Docker configuration
# ----------------------------------------------------------------------------------------------------------------------

ifeq (,$(wildcard /teamcity/system/git))
DRUN := docker run -t --rm \
			-v $(TMPDIR):/.helm \
			-v ${PWD}:/charts \
			-v ${PWD}/test/ct.yaml:/etc/ct/ct.yaml \
			-v ${PWD}/$(HELM_BIN):/usr/local/bin/helm \
			-w /charts \
			quay.io/helmpack/chart-testing:$(CT_VERSION)
else
DRUN := docker run -t --rm \
            -v /teamcity/system/git:/teamcity/system/git \
			-v ${PWD}:/charts \
			-v ${PWD}/test/ct.yaml:/etc/ct/ct.yaml \
			-v ${PWD}/$(HELM_BIN):/usr/local/bin/helm \
			-w /charts \
			quay.io/helmpack/chart-testing:$(CT_VERSION)
endif

# ----------------------------------------------------------------------------------------------------------------------
# Targets
# ----------------------------------------------------------------------------------------------------------------------

.SECONDEXPANSION:

.PHONY: all
all: stagingrepo stablerepo

.PHONY: clean
clean:
	rm -rf gh-pages bin .local

.PHONY: stagingrepo
stagingrepo: $(STAGING_TARGETS) | gh-pages/staging/index.yaml

.PHONY: stablerepo
stablerepo: $(STABLE_TARGETS) | gh-pages/stable/index.yaml

.PHONY: publish
publish: export LC_COLLATE := C
publish: export TZ := UTC
publish:
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
$(STABLE_TARGETS) $(STAGING_TARGETS): $(HELM_BIN) $$(shell find $$(shell echo $$@ | sed -E 's|gh-pages/((stable\|staging)/.+)-([0-9]+.?)+\.tgz|\1|') -type f)
	@mkdir -p $(shell dirname $@)
	$(eval PACKAGE_SRC := $(shell echo $@ | sed 's@gh-pages/\(.*\)-[v0-9][0-9.]*.tgz@\1@'))
	$(eval UNPACKED_TMP := $(shell mktemp -d))
	$(HELM_BIN) package $(PACKAGE_SRC) -d $(shell dirname $@)
	tar -xzmf $@ -C $(UNPACKED_TMP)
	tar -c \
			--owner=root:0 --group=root:0 --numeric-owner \
			--no-recursion \
			--mtime="@$(shell git log -1 --no-show-signature --format="%at" $(GIT_REF) -- $(PACKAGE_SRC))" \
			-C $(UNPACKED_TMP) \
			$$(find $(UNPACKED_TMP) -printf '%P\n' | sort) | gzip -n > $@
	rm -rf $(UNPACKED_TMP)

%/index.yaml: $(HELM_BIN) $(STABLE_TARGETS) $(STAGING_TARGETS)
%/index.yaml: $$(wildcard $$(dir $$@)*.tgz)
	@mkdir -p $(patsubst %/index.yaml,%,$@)
	$(HELM_BIN) repo index $(patsubst %/index.yaml,%,$@) --url=$(REPO_BASE_URL)/$(patsubst gh-pages/%index.yaml,%,$@)

.PHONY: ct.lint
ct.lint: $(HELM_BIN)
ifneq (,$(wildcard /teamcity/system/git))
	$(DRUN) git fetch ${GIT_REMOTE_NAME} master
endif
	$(DRUN) ct lint --remote=${GIT_REMOTE_NAME} --debug

.PHONY: ct.test
ct.test: $(HELM_BIN)
ifneq (,$(wildcard /teamcity/system/git))
	$(DRUN) git fetch ${GIT_REMOTE_NAME} master
endif
	GIT_REMOTE_NAME=$(GIT_REMOTE_NAME) test/e2e-kind.sh $(CT_VERSION) $(HELM_VERSION) --remote=$(GIT_REMOTE_NAME)

.PHONY: lint
lint: ct.lint

.PHONY: test.helm
test.helm: ct.test

.PHONY: test
test: ct.test

# ----------------------------------------------------------------------------------------------------------------------
# Download Tools
# ----------------------------------------------------------------------------------------------------------------------

ifneq (,$(filter tar (GNU tar)%, $(shell tar --version)))
WILDCARDS := --wildcards
endif

.PHONY: helm
helm: $(HELM_BIN)

# download helm
$(HELM_BIN):
	mkdir -p $(dir $@) _build
	curl -Ls https://get.helm.sh/helm-$(subst helm-,,$(notdir $@))-$(GOOS)-$(GOARCH).tar.gz | tar xz -C _build $(WILDCARDS) --strip=1 '*/helm'
	mv _build/helm $@
