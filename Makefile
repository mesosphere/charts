HELM_VERSION ?= v3.3.0

STABLE_CHARTS = $(wildcard stable/*/Chart.yaml)
STABLE_TARGETS = $(shell hack/chart_destination.sh $(STABLE_CHARTS))
STAGING_CHARTS = $(wildcard staging/*/Chart.yaml)
STAGING_TARGETS = $(shell hack/chart_destination.sh $(STAGING_CHARTS))

GIT_REMOTE_NAME ?= origin
GIT_REMOTE_URL ?= $(shell git remote get-url ${GIT_REMOTE_NAME})

# Extract the github user from the ${GIT_REMOTE_NAME} remote url.
# This let's the 'publish' task work with forks.
# Supports both SSH and HTTPS git url formats:
# - https://github.com/mesosphere/charts.git
# - git@github.com:mesosphere/charts.git
GITHUB_USER := $(shell git remote get-url ${GIT_REMOTE_NAME} | sed -E 's|.*github.com[/:]([^/]+)/charts.*|\1|')

GIT_REF ?= $(shell git rev-parse HEAD)
LAST_COMMIT_MESSAGE := $(shell git log -1 --pretty=format:'%B')
CT_VERSION ?= v3.0.0

TMPDIR := $(shell mktemp -d)
ifeq ($(shell uname),Darwin)
	# OSX requires /private prefix as symlink doesn't work when
	# mounting /var/folders/
	TMPDIR := /private${TMPDIR}
endif
export HELM_CONFIG_HOME=$(TMPDIR)/.helm/config
export HELM_CACHE_HOME=$(TMPDIR)/.helm/cache
export HELM_DATA_HOME=$(TMPDIR)/.helm/data

HELM := $(shell bash -c "command -v helm")
ifeq ($(HELM),)
	HELM := $(TMPDIR)/helm
endif
ifeq (,$(wildcard /teamcity/system/git))
DRUN := docker run -t --rm -u $(shell id -u):$(shell id -g) \
			-v ${PWD}:/charts -v ${PWD}/test/ct.yaml:/etc/ct/ct.yaml -v $(TMPDIR):/.helm \
			-w /charts quay.io/helmpack/chart-testing:$(CT_VERSION)
else
DRUN := docker run -t --rm -v /teamcity/system/git:/teamcity/system/git -v ${PWD}:/charts \
			-v ${PWD}/test/ct.yaml:/etc/ct/ct.yaml -w /charts \
			quay.io/helmpack/chart-testing:$(CT_VERSION)
endif

.SECONDEXPANSION:

.PHONY: all
all: stagingrepo stablerepo

.PHONY: clean
clean:
	rm -rf gh-pages

.PHONY: stagingrepo
stagingrepo: $(STAGING_TARGETS) | gh-pages/staging/index.yaml

.PHONY: stablerepo
stablerepo: $(STABLE_TARGETS) | gh-pages/stable/index.yaml

.PHONY: publish
publish: export LC_COLLATE := C
publish:
	-git remote add publish $(GIT_REMOTE_URL) >/dev/null 2>&1
	rm -rf gh-pages
	git fetch publish gh-pages
	git worktree add gh-pages/ publish/gh-pages
	$(MAKE) GIT_REF=$(GIT_REF) all
	cd gh-pages && \
		git add -A . && \
		git commit -m "$(LAST_COMMIT_MESSAGE)" && \
		git push publish HEAD:gh-pages
	git worktree remove gh-pages/
	rm -rf gh-pages

$(HELM):
ifeq ($(HELM),$(TMPDIR)/helm)
	curl -Ls https://get.helm.sh/helm-$(HELM_VERSION)-linux-amd64.tar.gz | tar xz -C $(TMPDIR) --strip-components=1 'linux-amd64/helm'
endif

# Deterministically create helm packages by:
#
# - Using `helm package` to create the initial package (useful for including chart dependencies
#   properly)
# - Untarring the package
# - Recreate the package using `tar`, speficying time of the last git commit to the package
#   source as the files' mtime, as well as ordering files deterministically, meaning that unchanged
#   content will result in the same output package
# - Use `gzip -n` to prevent any timestamps being added to `gzip` headers in archive.
$(STABLE_TARGETS) $(STAGING_TARGETS): $$(wildcard $$(patsubst gh-pages/%.tgz,%/*,$$@)) $$(wildcard $$(patsubst gh-pages/%.tgz,%/*/*,$$@))
$(STABLE_TARGETS) $(STAGING_TARGETS): $(HELM) $(TMPDIR)/.helm/repository/local/index.yaml
	@mkdir -p $(shell dirname $@)
	$(eval PACKAGE_SRC := $(shell echo $@ | sed 's@gh-pages/\(.*\)-[v0-9][0-9.]*.tgz@\1@'))
	$(eval UNPACKED_TMP := $(shell mktemp -d))
	$(HELM) package $(PACKAGE_SRC) -d $(shell dirname $@)
	tar -xzmf $@ -C $(UNPACKED_TMP)
	tar -c \
			--owner=root:0 --group=root:0 --numeric-owner \
			--no-recursion \
			--mtime="@$(shell git log -1 --format="%at" $(GIT_REF) -- $(PACKAGE_SRC))" \
			-C $(UNPACKED_TMP) \
			$$(find $(UNPACKED_TMP) -printf '%P\n' | sort) | gzip -n > $@
	rm -rf $(UNPACKED_TMP)

%/index.yaml: $(HELM) $(STABLE_TARGETS) $(STAGING_TARGETS)
%/index.yaml:
	@mkdir -p $(patsubst %/index.yaml,%,$@)
	$(HELM) repo index $(patsubst %/index.yaml,%,$@) --url=https://$(GITHUB_USER).github.io/charts/$(patsubst gh-pages/%index.yaml,%,$@)

.PHONY: ct.lint
ct.lint:
ifneq (,$(wildcard /teamcity/system/git))
	$(DRUN) git fetch ${GIT_REMOTE_NAME} master
endif
	$(DRUN) ct lint --remote=${GIT_REMOTE_NAME} --debug

.PHONY: ct.test
ct.test:
ifneq (,$(wildcard /teamcity/system/git))
	$(DRUN) git fetch ${GIT_REMOTE_NAME} master
endif
	GIT_REMOTE_NAME=$(GIT_REMOTE_NAME) test/e2e-kind.sh $(CT_VERSION) $(HELM_VERSION) --remote=$(GIT_REMOTE_NAME)

.PHONY: lint
lint: ct.lint

.PHONY: test.helm2
test.helm2: HELM_VERSION = v2.16.9
test.helm2: CT_VERSION = v2.4.1
test.helm2: ct.test

.PHONY: test.helm3
test.helm3: HELM_VERSION = v3.3.0
test.helm3: CT_VERSION = v3.0.0
test.helm3: ct.test

.PHONY: test
test: ct.test

