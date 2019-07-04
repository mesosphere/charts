HELM_VERSION := v2.13.0

STABLE_CHARTS = $(wildcard stable/*/Chart.yaml)
STABLE_TARGETS = $(shell hack/chart_destination.sh $(STABLE_CHARTS))
STAGING_CHARTS = $(wildcard staging/*/Chart.yaml)
STAGING_TARGETS = $(shell hack/chart_destination.sh $(STAGING_CHARTS))

GIT_REMOTE_URL := $(shell git remote get-url origin)
# Extract the github user from the origin remote url.
# This let's the 'publish' task work with forks.
# Supports both SSH and HTTPS git url formats:
# - https://github.com/mesosphere/charts.git
# - git@github.com:mesosphere/charts.git
GITHUB_USER := $(shell git remote get-url origin | sed -E 's|.*github.com[/:]([^/]+)/charts.*|\1|')

LAST_COMMIT_MESSAGE := $(shell git reflog -1 | sed 's/^.*: //')

TMPDIR := $(shell mktemp -d)
HELM := $(shell bash -c "command -v helm")
ifeq ($(HELM),)
	HELM := $(TMPDIR)/helm
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
	@git branch -d master >/dev/null 2>&1 || true
	@git checkout -B master
	@make all
	@git add .
	@git commit -m "$(LAST_COMMIT_MESSAGE)"
	@ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts
	@chmod 0644 /etc/ssh/ssh_known_hosts
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
