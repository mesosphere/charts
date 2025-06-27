{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "registry-syncer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "registry-syncer.fullname" -}}
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

{{- define "registry-syncer.deployment.configmap.name" -}}
{{- printf "%s-deployment-config" (include "registry-syncer.fullname" .) -}}
{{- end -}}

{{- define "registry-syncer.job.configmap.name" -}}
{{- printf "%s-job-config" (include "registry-syncer.fullname" .) -}}
{{- end -}}


{{- define "registry-syncer.deployment.volumeMounts" -}}
- name: "config"
  mountPath: "/config/"
{{- with .Values.extraVolumeMounts }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "registry-syncer.deployment.volumes" -}}
- name: config
  configMap:
    name: {{ template "registry-syncer.deployment.configmap.name" . }}
{{- with .Values.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "registry-syncer.job.volumeMounts" -}}
- name: "config"
  mountPath: "/config/"
{{- with .Values.extraVolumeMounts }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "registry-syncer.job.volumes" -}}
- name: config
  configMap:
    name: {{ template "registry-syncer.job.configmap.name" . }}
{{- with .Values.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end -}}
