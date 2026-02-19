{{- define "additional.gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "additional.gateway.labels" -}}
helm.sh/chart: {{ include "additional.gateway.chart" . }}
{{ include "additional.gateway.selectorLabels" . }}
app.kubernetes.io/name: {{ .gw.name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $val := .gw.labels }}
{{- if and (ne $key "app") (ne $key "istio") }}
{{ $key | quote }}: {{ $val | quote }}
{{- end }}
{{- end }}
{{- end }}

{{- define "additional.gateway.selectorLabels" -}}
app: {{ (.gw.labels.app | quote) | default .gw.name }}
istio: {{ (.gw.labels.istio | quote) | default (.gw.name | trimPrefix "istio-") }}
{{- end }}

{{- define "additional.gateway.sidecarInjectionLabels" -}}
sidecar.istio.io/inject: "true"
{{- with .gw.revision }}
istio.io/rev: {{ . | quote }}
{{- end }}
{{- end }}

{{- define "additional.gateway.serviceAccountName" -}}
{{- if .gw.serviceAccount.create }}
{{- .gw.serviceAccount.name | default .gw.name }}
{{- else }}
{{- .gw.serviceAccount.name | default "default" }}
{{- end }}
{{- end }}
