{{/* vim: set filetype=mustache: */}}

{{/* labels for helm resources */}}
{{- define "azuredisk.labels" -}}
labels:
  heritage: "{{ .Release.Service }}"
  release: "{{ .Release.Name }}"
  revision: "{{ .Release.Revision }}"
  chart: "{{ .Chart.Name }}"
  chartVersion: "{{ .Chart.Version }}"
{{- end -}}

{{/*
To keep compability we need to set snapshotter tag to the same tag as snapshot-controller.
They are released in combination and depend on each other on newer kubernetes versions >= Minor 17
*/}}
{{- define "azuredisk.csiSnapshotter.tag" -}}
{{- if and .Values.snapshot.enabled (or (gt (.Capabilities.KubeVersion.Minor | int) 17) (eq (.Capabilities.KubeVersion.Minor | int) 17)) }}
{{- .Values.image.csiSnapshotController.tag -}}
{{- else -}}
{{- .Values.image.csiSnapshotter.tag -}}
{{- end -}}
{{- end -}}

{{/* pull secrets for containers */}}
{{- define "azuredisk.pullSecrets" -}}
{{- if .Values.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end -}}
