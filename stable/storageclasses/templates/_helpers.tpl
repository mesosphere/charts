{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "storageclasses.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "storageclasses.fullname" -}}
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
{{- define "storageclasses.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Validate StorageClass types
*/}}
{{- define "storageclasses.validateTypes" -}}
  {{- range .Values.storageClasses -}}
    {{- if has (.type | lower) (list "local" "aws" "awsebscsi") | not -}}
      {{- printf "%s is not a supported type" .type | fail -}}
    {{- end -}}
  {{- end -}}
{{- end -}}


{{/*
Determine if "local" type is used
*/}}
{{- define "storageclasses.localUsed" -}}
  {{- $is_local := false -}}
  {{- range .Values.storageClasses -}}
    {{- if eq (.type | lower) "local" -}}
      {{- $is_local = true -}}
    {{- end -}}
  {{- end -}}
{{ $is_local }}
{{- end -}}
