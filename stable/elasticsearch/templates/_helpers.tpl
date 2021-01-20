{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "elasticsearch.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "elasticsearch.fullname" -}}
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
Create a default fully qualified client name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "elasticsearch.client.fullname" -}}
{{ template "elasticsearch.fullname" . }}-{{ .Values.client.name }}
{{- end -}}

{{/*
Create a default fully qualified data name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "elasticsearch.data.fullname" -}}
{{ template "elasticsearch.fullname" . }}-{{ .Values.data.name }}
{{- end -}}

{{/*
Create a default fully qualified master name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "elasticsearch.master.fullname" -}}
{{ template "elasticsearch.fullname" . }}-{{ .Values.master.name }}
{{- end -}}

{{/*
Create the name of the service account to use for the client component
*/}}
{{- define "elasticsearch.serviceAccountName.client" -}}
{{- if .Values.serviceAccounts.client.create -}}
    {{ default (include "elasticsearch.client.fullname" .) .Values.serviceAccounts.client.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccounts.client.name }}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use for the data component
*/}}
{{- define "elasticsearch.serviceAccountName.data" -}}
{{- if .Values.serviceAccounts.data.create -}}
    {{ default (include "elasticsearch.data.fullname" .) .Values.serviceAccounts.data.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccounts.data.name }}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use for the master component
*/}}
{{- define "elasticsearch.serviceAccountName.master" -}}
{{- if .Values.serviceAccounts.master.create -}}
    {{ default (include "elasticsearch.master.fullname" .) .Values.serviceAccounts.master.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccounts.master.name }}
{{- end -}}
{{- end -}}

{{/*
plugin installer template
*/}}
{{- define "plugin-installer" -}}
- name: es-plugin-install
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  securityContext:
    capabilities:
      add:
        - IPC_LOCK
        - SYS_RESOURCE
  command:
    - "sh"
    - "-c"
    - |
      {{- range .Values.cluster.plugins }}
      PLUGIN_NAME="{{ . }}"
      echo "Installing $PLUGIN_NAME..."
      if /usr/share/elasticsearch/bin/elasticsearch-plugin list | grep "$PLUGIN_NAME" > /dev/null; then
        echo "Plugin $PLUGIN_NAME already exists, skipping."
      else
        /usr/share/elasticsearch/bin/elasticsearch-plugin install -b $PLUGIN_NAME
      fi
      {{- end }}
  volumeMounts:
  - mountPath: /usr/share/elasticsearch/plugins/
    name: plugindir
{{- end -}}

{{- define "elasticsearch.masterService" -}}
{{- if empty .Values.masterService -}}
{{- if empty .Values.fullnameOverride -}}
{{- if empty .Values.nameOverride -}}
{{ .Values.cluster.name }}-master
{{- else -}}
{{ .Values.nameOverride }}-master
{{- end -}}
{{- else -}}
{{ .Values.fullnameOverride }}
{{- end -}}
{{- else -}}
{{ .Values.masterService }}
{{- end -}}
{{- end -}}

{{- define "elasticsearch.clientuname" -}}
{{- if empty .Values.fullnameOverride -}}
{{- if empty .Values.nameOverride -}}
{{ template "elasticsearch.fullname" . }}-client
{{- else -}}
{{ .Values.nameOverride }}-client
{{- end -}}
{{- else -}}
{{ .Values.fullnameOverride }}
{{- end -}}
{{- end -}}

{{- define "elasticsearch.datauname" -}}
{{- if empty .Values.fullnameOverride -}}
{{- if empty .Values.nameOverride -}}
{{ template "elasticsearch.fullname" . }}-data
{{- else -}}
{{ .Values.nameOverride }}-data
{{- end -}}
{{- else -}}
{{ .Values.fullnameOverride }}
{{- end -}}
{{- end -}}

{{- define "elasticsearch.masteruname" -}}
{{- if empty .Values.fullnameOverride -}}
{{- if empty .Values.nameOverride -}}
{{ template "elasticsearch.fullname" . }}-master
{{- else -}}
{{ .Values.nameOverride }}-master
{{- end -}}
{{- else -}}
{{ .Values.fullnameOverride }}
{{- end -}}
{{- end -}}

{{- define "elasticsearch.masterEndpoints" -}}
{{- $replicas := int (.Values.master.replicas) }}
{{- $uname := ( include "elasticsearch.masteruname" .) }}
  {{- range $i, $e := untilStep 0 $replicas 1 -}}
{{ $uname }}-{{ $i }},
  {{- end -}}
{{- end -}}

{{- define "elasticsearch.clientEndpoints" -}}
{{- $replicas := int (.Values.client.replicas) }}
{{- $uname := ( include "elasticsearch.clientuname" .) }}
  {{- range $i, $e := untilStep 0 $replicas 1 -}}
{{ $uname }}-{{ $i }},
  {{- end -}}
{{- end -}}

{{- define "elasticsearch.dataEndpoints" -}}
{{- $replicas := int (.Values.data.replicas) }}
{{- $uname := ( include "elasticsearch.datauname" .) }}
  {{- range $i, $e := untilStep 0 $replicas 1 -}}
{{ $uname }}-{{ $i }},
  {{- end -}}
{{- end -}}


{{- define "elasticsearch.esMajorVersion" -}}
{{- if .Values.esMajorVersion -}}
{{ .Values.esMajorVersion }}
{{- else -}}
{{- $version := int (index (.Values.image.tag | splitList ".") 0) -}}
  {{- if and (contains "docker.elastic.co/elasticsearch/elasticsearch" .Values.image) (not (eq $version 0)) -}}
{{ $version }}
  {{- else -}}
8
  {{- end -}}
{{- end -}}
{{- end -}}
