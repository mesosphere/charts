{{/* vim: set filetype=mustache: */}}

{{/* labels for helm resources */}}
{{- define "gcpdisk.labels" -}}
labels:
  heritage: "{{ .Release.Service }}"
  release: "{{ .Release.Name }}"
  revision: "{{ .Release.Revision }}"
  chart: "{{ .Chart.Name }}"
  chartVersion: "{{ .Chart.Version }}"
{{- end -}}

{{/*
As the official docs say 0.7.0 is compatible up from kubernetes versions >= Minor 16
so we define it here to use the higher version only then.
*/}}
{{- define "gcpdisk.image.tag" -}}
{{- if or (gt (.Capabilities.KubeVersion.Minor | int) 16) (eq (.Capabilities.KubeVersion.Minor | int) 16) }}
{{- .Values.image.tagK8sMinor16 -}}
{{- else -}}
{{- .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{/*
To keep compability we need to set snapshotter tag to the same tag as snapshot-controller.
They are released in combination and depend on each other on newer kubernetes versions >= Minor 17
*/}}
{{- define "gcpdisk.snapshotter.image.tag" -}}
{{- if or (gt (.Capabilities.KubeVersion.Minor | int) 17) (eq (.Capabilities.KubeVersion.Minor | int) 17) }}
{{- .Values.snapshotController.image.tag -}}
{{- else -}}
{{- .Values.snapshotter.image.tag -}}
{{- end -}}
{{- end -}}
