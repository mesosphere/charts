{{- define "serving.labels" -}}
app.kubernetes.io/name: knative-serving
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{- define "serving.controller" -}}
gcr.io/knative-releases/knative.dev/net-istio/cmd/controller:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.webhook" -}}
gcr.io/knative-releases/knative.dev/net-istio/cmd/webhook:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.autoscaler" -}}
gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.autoscaler-hpa" -}}
gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler-hpa:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.queue" -}}
gcr.io/knative-releases/knative.dev/serving/cmd/queue:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.activator" -}}
gcr.io/knative-releases/knative.dev/serving/cmd/activator:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.domain-mapping" -}}
gcr.io/knative-releases/knative.dev/serving/cmd/domain-mapping:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.domain-mapping-webhook" -}}
gcr.io/knative-releases/knative.dev/serving/cmd/domain-mapping-webhook:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.domain-mapping-controller" -}}
gcr.io/knative-releases/knative.dev/serving/cmd/domain-mapping-controller:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.net-istio-webhook" -}}
gcr.io/knative-releases/knative.dev/net-istio/cmd/webhook:{{ .Chart.AppVersion }}
{{- end }}

{{- define "serving.net-istio-controller" -}}
gcr.io/knative-releases/knative.dev/net-istio/cmd/controller:{{ .Chart.AppVersion }}
{{- end }}
