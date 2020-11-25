{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "aws-ebs-csi-driver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "aws-ebs-csi-driver.fullname" -}}
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
{{- define "aws-ebs-csi-driver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "aws-ebs-csi-driver.labels" -}}
app.kubernetes.io/name: {{ include "aws-ebs-csi-driver.name" . }}
helm.sh/chart: {{ include "aws-ebs-csi-driver.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Convert the `--extra-volume-tags` command line arg from a map.
*/}}
{{- define "aws-ebs-csi-driver.extra-volume-tags" -}}
{{- $result := dict "pairs" (list) -}}
{{- range $key, $value := .Values.extraVolumeTags -}}
{{- $noop := printf "%s=%s" $key $value | append $result.pairs | set $result "pairs" -}}
{{- end -}}
{{- if gt (len $result.pairs) 0 -}}
- --extra-volume-tags={{- join "," $result.pairs -}}
{{- end -}}
{{- end -}}

{{/*
To keep compability we need to set snapshotter tag to the same tag as snapshot-controller.
They are released in combination and depend on each other on newer kubernetes versions >= Minor 17
*/}}
{{- define "aws-ebs-csi-driver.snapshotter.tag" -}}
{{- if and .Values.snapshotter.enabled (or (gt (.Capabilities.KubeVersion.Minor | int) 17) (eq (.Capabilities.KubeVersion.Minor | int) 17)) -}}
{{- .Values.snapshotController.image.tag -}}
{{- else -}}
{{- .Values.snapshotter.image.tag -}}
{{- end -}}
{{- end -}}

{{/*
To keep compability we need to set csi-attacher matching on kubernetes versions >= Minor 17
*/}}
{{- define "aws-ebs-csi-driver.csi-attacher.tag" -}}
{{- if (or (gt (.Capabilities.KubeVersion.Minor | int) 17) (eq (.Capabilities.KubeVersion.Minor | int) 17)) -}}
{{- .Values.attacher.image.tagK8sUpMinor17 -}}
{{- else -}}
{{- .Values.attacher.image.tag -}}
{{- end -}}
{{- end -}}

{{/*
To keep compability we need to set csi-provisioner matching on kubernetes versions >= Minor 17
*/}}
{{- define "aws-ebs-csi-driver.csi-provisioner.tag" -}}
{{- if (or (gt (.Capabilities.KubeVersion.Minor | int) 17) (eq (.Capabilities.KubeVersion.Minor | int) 17)) -}}
{{- .Values.provisioner.image.tagK8sUpMinor17 -}}
{{- else -}}
{{- .Values.provisioner.image.tag -}}
{{- end -}}
{{- end -}}
