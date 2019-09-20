HELM_VERSION := v2.13.0

STABLE_CHARTS = $(wildcard stable/*/Chart.yaml)
STABLE_TARGETS = $(shell hack/chart_destination.sh $(STABLE_CHARTS))
STAGING_CHARTS = $(wildcard staging/*/Chart.yaml)
STAGING_TARGETS = $(shell hack/chart_destination.sh $(STAGING_CHARTS))

GIT_REMOTE_URL ?= https://mesosphere:$(GITHUB_USER_TOKEN)@github.com/mesosphere/charts.git

# Extract the github user from the origin remote url.
# This let's the 'publish' task work with forks.
# Supports both SSH and HTTPS git url formats:
# - https://github.com/mesosphere/charts.git
# - git@github.com:mesosphere/charts.git
GITHUB_USER := $(shell git remote get-url origin | sed -E 's|.*github.com[/:]([^/]+)/charts.*|\1|')

GIT_REF = $(shell git show-ref -s HEAD)	
LAST_COMMIT_MESSAGE := $(shell git reflog -1 | sed 's/^.*: //')

TMPDIR := $(shell mktemp -d)
HELM := $(shell bash -c "command -v helm")
ifeq ($(HELM),)
	HELM := $(TMPDIR)/helm
endif
ifeq (,$(wildcard /teamcity/system/git))
DRUN := docker run -t --rm -v ${PWD}:/charts -v ${PWD}/test/ct.yaml:/etc/ct/ct.yaml -w /charts \
			quay.io/helmpack/chart-testing:v2.3.3
else
DRUN := docker run -t --rm -v /teamcity/system/git:/teamcity/system/git -v ${PWD}:/charts \
			-v ${PWD}/test/ct.yaml:/etc/ct/ct.yaml -w /charts \
			quay.io/helmpack/chart-testing:v2.3.3
endif

.SECONDEXPANSION:

.PHONY: all
all: stagingrepo stablerepo

.PHONY: clean
clean:
	@rm -rf docs/staging/*.tgz docs/stable/*.tgz
	@git checkout 3ea869 docs/staging/index.yaml
	@git checkout 3ea869 docs/stable/index.yaml

.PHONY: stagingrepo
stagingrepo: $(STAGING_TARGETS) | docs/staging/index.yaml

.PHONY: stablerepo
stablerepo: $(STABLE_TARGETS) | docs/stable/index.yaml

.PHONY: publish
publish:
	@git remote add publish $(GIT_REMOTE_URL) >/dev/null 2>&1 || true
	@git fetch publish master
	@git checkout master
	@mv docs docs~
	@git reset --hard $(GIT_REF)
	@rm -rf docs
	@mv docs~ docs
	@make all
	@git add .
	@git commit -m "$(LAST_COMMIT_MESSAGE)"
	@git push -f publish master
	@git checkout -

$(HELM):
ifeq ($(HELM),$(TMPDIR)/helm)
	curl -Ls https://get.helm.sh/helm-$(HELM_VERSION)-linux-amd64.tar.gz | tar xz -C $(TMPDIR) --strip-components=1 'linux-amd64/helm'
endif

$(STABLE_TARGETS) $(STAGING_TARGETS): $$(wildcard $$(patsubst docs/%.tgz,%/*,$$@)) $$(wildcard $$(patsubst docs/%.tgz,%/*/*,$$@))
$(STABLE_TARGETS) $(STAGING_TARGETS): $(TMPDIR)/.helm/repository/local/index.yaml
	@mkdir -p $(shell dirname $@)
	$(HELM) --home $(TMPDIR)/.helm package $(shell echo $@ | sed 's@docs/\(.*\)-[v0-9][0-9.]*.tgz@\1@') -d $(shell dirname $@)

%/index.yaml: $(STABLE_TARGETS) $(STAGING_TARGETS)
%/index.yaml: $(TMPDIR)/.helm/repository/local/index.yaml
	@mkdir -p $(patsubst %/index.yaml,%,$@)
	$(HELM) --home $(TMPDIR)/.helm repo index $(patsubst %/index.yaml,%,$@) --url=https://$(GITHUB_USER).github.io/charts/$(patsubst docs/%index.yaml,%,$@)

$(TMPDIR)/.helm/repository/local/index.yaml: $(HELM)
	$(HELM) --home $(TMPDIR)/.helm init --client-only

.PHONY: ct.lint
ct.lint:
	$(DRUN) git fetch origin dev
	$(DRUN) ct lint
