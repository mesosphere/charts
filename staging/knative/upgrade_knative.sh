#!/usr/bin/env bash

# This script upgrades knative by copying all the latest github release files.
#
# It then applies all the needed mesosphere changes
#
# To upgrade, simply run:
#   ./upgrade_knative.sh

set -xeuo pipefail
shopt -s dotglob

# Tags for current version of knative
SERVING_TAG=1.10.2
EVENTING_TAG=1.10.1

# Two basic patches needed for helm linter
PATCH_1=$'# eg. \'{{.Name}}-{{.Namespace}}.{{ index .Annotations "sub"}}.{{.Domain}}\''
PATCH_1_FIX=$'# eg. \'{{ `{{.Name}}-{{.Namespace}}.{{ index .Annotations "sub"}}.{{.Domain}}` }}\''

PATCH_2=$'logging.request-log-template: \'{"httpRequest": {"requestMethod": "{{.Request.Method}}", "requestUrl": "{{js .Request.RequestURI}}", "requestSize": "{{.Request.ContentLength}}", "status": {{.Response.Code}}, "responseSize": "{{.Response.Size}}", "userAgent": "{{js .Request.UserAgent}}", "remoteIp": "{{js .Request.RemoteAddr}}", "serverIp": "{{.Revision.PodIP}}", "referer": "{{js .Request.Referer}}", "latency": "{{.Response.Latency}}s", "protocol": "{{.Request.Proto}}"}, "traceId": "{{index .Request.Header "X-B3-Traceid"}}"}\''
PATCH_2_FIX=$'logging.request-log-template: \'{"httpRequest": {"requestMethod": "{{ `{{.Request.Method}}", "requestUrl": "{{js .Request.RequestURI}}", "requestSize": "{{.Request.ContentLength}}", "status": {{.Response.Code}}, "responseSize": "{{.Response.Size}}", "userAgent": "{{js .Request.UserAgent}}", "remoteIp": "{{js .Request.RemoteAddr}}", "serverIp": "{{.Revision.PodIP}}", "referer": "{{js .Request.Referer}}", "latency": "{{.Response.Latency}}s", "protocol": "{{.Request.Proto}}"}, "traceId": "{{index .Request.Header "X-B3-Traceid"}}` }}"}\''

# Base URLs
SERVING_URL=https://github.com/knative/serving/releases/download/knative-v${SERVING_TAG}
EVENTING_URL=https://github.com/knative/eventing/releases/download/knative-v${EVENTING_TAG}

# Get all files, auto-apply PodDisruptionBudget patches
curl -sSL ${SERVING_URL}/serving-crds.yaml > charts/serving/crds/serving-crds.yaml
curl -sSL ${SERVING_URL}/serving-core.yaml | sed -e 's/minAvailable: 80%/maxUnavailable: 1/g' > charts/serving/templates/serving-core-1.yaml
curl -sSL ${SERVING_URL}/serving-hpa.yaml > charts/serving/templates/serving-hpa-temp.yaml

curl -sSL ${EVENTING_URL}/eventing-crds.yaml > charts/eventing/crds/eventing-crds.yaml
curl -sSL ${EVENTING_URL}/eventing.yaml | sed -e 's/minAvailable: 80%/maxUnavailable: 1/g' > charts/eventing/templates/eventing-temp.yaml

# Apply patches to fix helm linter
sed "s/${PATCH_1}/${PATCH_1_FIX}/g" charts/serving/templates/serving-core-1.yaml | sed -e "s/${PATCH_2}/${PATCH_2_FIX}/g" > charts/serving/templates/serving-core-temp.yaml

# Apply airgapped image patches
sed "s/@sha256.*/:v${SERVING_TAG}/g" charts/serving/templates/serving-core-temp.yaml > charts/serving/templates/serving-core.yaml
sed "s/@sha256.*/:v${SERVING_TAG}/g" charts/serving/templates/serving-hpa-temp.yaml > charts/serving/templates/serving-hpa.yaml
sed "s/@sha256.*/:v${EVENTING_TAG}/g" charts/eventing/templates/eventing-temp.yaml > charts/eventing/templates/eventing.yaml

# Remove junk files
rm charts/serving/templates/serving-core-1.yaml
rm charts/serving/templates/serving-core-temp.yaml
rm charts/serving/templates/serving-hpa-temp.yaml
rm charts/eventing/templates/eventing-temp.yaml

# Bump app version
sed "s/appVersion:.*/appVersion: \"v${SERVING_TAG}\"/g" Chart.yaml > Chart.yaml.temp
sed "s/appVersion:.*/appVersion: \"v${SERVING_TAG}\"/g" charts/serving/Chart.yaml > charts/serving/Chart.yaml.temp
sed "s/appVersion:.*/appVersion: \"v${EVENTING_TAG}\"/g" charts/eventing/Chart.yaml > charts/eventing/Chart.yaml.temp
mv Chart.yaml.temp Chart.yaml
mv charts/serving/Chart.yaml.temp charts/serving/Chart.yaml
mv charts/eventing/Chart.yaml.temp charts/eventing/Chart.yaml

# Commit changes
 git add .
 git commit -am "chore: bump Knative Serving to \"v${SERVING_TAG}\""

# Finish
echo "Done upgrading knative!"
echo "Please remember to bump version numbers in Chart and sub-Charts manually"
