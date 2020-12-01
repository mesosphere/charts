{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "kommander-karma.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kommander-karma.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kommander-karma.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a truncated name suitable for resources that need shorter names, such as addons.
*/}}
{{- define "kommander-karma.short-name-prefix" -}}
{{- include "kommander-karma.fullname" . | trunc 36 -}}
{{- end -}}

{{/*
Create a service account name for hooks running in the chart.
*/}}
{{- define "kommander-karma.sa-name" -}}
{{- include "kommander-karma.fullname" . -}}-hook
{{- end -}}

{{/*
Generate the karma configmap name.
*/}}
{{- define "kommander-karma.configmap-name" -}}
{{ .Release.Name }}-config
{{- end -}}

{{/*
Common labels
*/}}
{{- define "kommander-karma.labels" -}}
app.kubernetes.io/name: {{ include "kommander-karma.name" . }}
helm.sh/chart: {{ include "kommander-karma.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
