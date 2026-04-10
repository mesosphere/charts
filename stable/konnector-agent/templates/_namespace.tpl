{{/*
Allow the release namespace to be overridden
*/}}
{{- define "k8s-agent.namespace" -}}
  {{- if .Values.agent.namespaceOverride -}}
    {{- .Values.agent.namespaceOverride -}}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}