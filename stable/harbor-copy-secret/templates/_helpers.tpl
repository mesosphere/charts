{{/*
Expand the name of the chart.
*/}}
{{- define "harbor-copy-secret.name" -}}
{{- default .Chart.Name .Values.harborCopySecret.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "harbor-copy-secret.fullname" -}}
{{- if .Values.harborCopySecret.fullnameOverride }}
{{- .Values.harborCopySecret.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.harborCopySecret.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "harbor-copy-secret.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "harbor-copy-secret.labels" -}}
helm.sh/chart: {{ include "harbor-copy-secret.chart" . }}
{{ include "harbor-copy-secret.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "harbor-copy-secret.selectorLabels" -}}
app.kubernetes.io/name: {{ include "harbor-copy-secret.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "harbor-copy-secret.serviceAccountName" -}}
{{- if .Values.harborCopySecret.serviceAccount.create }}
{{- default (include "harbor-copy-secret.fullname" .) .Values.harborCopySecret.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.harborCopySecret.serviceAccount.name }}
{{- end }}
{{- end }}
