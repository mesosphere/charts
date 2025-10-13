{{/*
Expand the name of the chart.
*/}}
{{- define "multus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "multus.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
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
{{- define "multus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "multus.labels" -}}
helm.sh/chart: {{ include "multus.chart" . }}
{{ include "multus.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "multus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "multus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{/*
Multus configuration JSON
*/}}
{{- define "multus.config" -}}
{
    "chrootDir": "{{ .Values.daemonConfig.chrootDir }}",
    "cniVersion": "{{ .Values.daemonConfig.cniVersion }}",
    "logLevel": "{{ .Values.daemonConfig.logLevel }}",
    "logToStderr": {{ .Values.daemonConfig.logToStderr }},
    "cniConfigDir": "{{ .Values.daemonConfig.cniConfigDir }}",
    "readinessIndicatorFile": "{{ .Values.daemonConfig.readinessIndicatorFile }}",
    "multusAutoconfigDir": "{{ .Values.daemonConfig.multusAutoconfigDir }}",
    "multusConfigFile": "{{ .Values.daemonConfig.multusConfigFile }}",
    "socketDir": "{{ .Values.daemonConfig.socketDir }}"
}
{{- end }}
