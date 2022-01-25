#!/usr/bin/env bash

# This patch adds mesosphere specific patterns to ignore into .helmignore

source $(dirname "$0")/helpers.sh

set -xeuo pipefail

SRCFILE="${BASEDIR}"/templates/_helpers.tpl

sed -i '/# Mesosphere-specific files to ignore/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}
# Mesosphere-specific templates

{{/* Override grafana service name if applicable, only in cronjob */}}
{{- define "kube-prometheus-stack.homeDashboard.grafanaServiceName" -}}
   {{- default (printf "%s-grafana" .Release.Name ) .Values.mesosphereResources.homeDashboard.serviceNameOverride -}}
{{- end -}}
EOF

git_add_and_commit "${BASEDIR}"/templates/_helpers.tpl
