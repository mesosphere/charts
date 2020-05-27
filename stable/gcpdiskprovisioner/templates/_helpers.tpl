{{/* vim: set filetype=mustache: */}}

{{/*
Switching snapshot classes api version depending on our detected Kubernetes version >= Minor 17
It works together with our csi-driver
*/}}
{{- define "gcpdiskprovisioner.snapshotclass.apiversion" -}}
{{- if or (gt (.Capabilities.KubeVersion.Minor | int) 17) (eq (.Capabilities.KubeVersion.Minor | int) 17) -}}
v1beta1
{{- else -}}
v1alpha1
{{- end -}}
{{- end -}}
