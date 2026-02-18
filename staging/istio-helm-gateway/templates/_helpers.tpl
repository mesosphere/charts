{{/*
Create chart name and version as used by the helm.sh/chart label.
*/}}
{{- define "gateways.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Gateway labels.
Context: dict with .gw, .Chart, .Release
*/}}
{{- define "gateways.labels" -}}
helm.sh/chart: {{ include "gateways.chart" . }}
{{ include "gateways.selectorLabels" . }}
app.kubernetes.io/name: {{ .gw.name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $val := .gw.labels }}
{{- if and (ne $key "app") (ne $key "istio") }}
{{ $key | quote }}: {{ $val | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Gateway selector labels used for Deployment matchLabels and Service selector.
Context: dict with .gw
*/}}
{{- define "gateways.selectorLabels" -}}
app: {{ (.gw.labels.app | quote) | default .gw.name }}
istio: {{ (.gw.labels.istio | quote) | default (.gw.name | trimPrefix "istio-") }}
{{- end }}

{{/*
Sidecar injection labels.
Context: dict with .gw
*/}}
{{- define "gateways.sidecarInjectionLabels" -}}
sidecar.istio.io/inject: "true"
{{- with .gw.revision }}
istio.io/rev: {{ . | quote }}
{{- end }}
{{- end }}

{{/*
Service account name.
Context: dict with .gw
*/}}
{{- define "gateways.serviceAccountName" -}}
{{- if .gw.serviceAccount.create }}
{{- .gw.serviceAccount.name | default .gw.name }}
{{- else }}
{{- .gw.serviceAccount.name | default "default" }}
{{- end }}
{{- end }}
