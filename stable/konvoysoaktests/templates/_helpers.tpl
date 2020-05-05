{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "konvoysoaktests.name" -}}
{{- default (printf "%s" .Chart.Name) .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "konvoysoaktests.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "konvoysoaktests.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return instance and name labels.
*/}}
{{- define "konvoysoaktests.instance-name" -}}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/name: {{ include "konvoysoaktests.name" . | quote }}
{{- end -}}

{{/*
Return labels, including instance and name.
*/}}
{{- define "konvoysoaktests.labels" -}}
{{ include "konvoysoaktests.instance-name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
helm.sh/chart: {{ include "konvoysoaktests.chart" . | quote }}
{{- end -}}

{{/*
Return the service account name used by the pod.
*/}}
{{- define "serviceaccount.name" -}}
{{- if and .Values.rbac.create .Values.rbac.serviceAccount.create -}}
{{ include "konvoysoaktests.fullname" . }}
{{- else -}}
{{ .Values.rbac.serviceAccount.name }}
{{- end -}}
{{- end -}}
