CERT_MANAGER_VERSION ?= v1.16.1

update: update-crds update-version

.PHONY: update-crds
update-crds:
	curl -L https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.crds.yaml -o crds/cert-manager.crds.yaml

update-version:
	sed -E -i '' 's/version: "v?[\.0-9]+"/version: "$(CERT_MANAGER_VERSION)"/g' Chart.yaml
	sed -E -i '' 's/appVersion: "v[\.0-9]+"/appVersion: "$(CERT_MANAGER_VERSION)"/g' Chart.yaml
