{{/*
Expand the chart name and version into a single label value.
Usage: {{ include "nkp-etcd-maintenance.chart" . }}
*/}}
{{- define "nkp-etcd-maintenance.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
