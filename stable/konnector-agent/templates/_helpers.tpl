{{/*
Return the namespace
*/}}
{{- define "k8s-agent.namespace" -}}
{{- .Values.agent.namespaceOverride | default "ntnx-system" }}
{{- end }}

{{/*
Return the name of the Prism Central credentials Secret.
Honors the user-supplied `prismCredentialsSecretName` (bring-your-own secret);
otherwise uses a chart-managed name. The "-v2" suffix intentionally differs from
the legacy "<release>-prism-credentials" name: older releases created that Secret
as `type: kubernetes.io/basic-auth`, and a Secret's `type` is immutable, so reusing
the name would break `helm upgrade` when the type changes to `Opaque`. Using a new
name lets Helm create the new Opaque Secret and garbage-collect the legacy one.
*/}}
{{- define "k8s-agent.prismCredentialsSecretName" -}}
{{- .Values.prismCredentialsSecretName | default (printf "%s-prism-credentials-v2" .Release.Name) }}
{{- end }}

{{/*
Return the ConfigMap name for trust bundle
*/}}
{{- define "k8s-agent.trustBundleConfigMapName" -}}
{{- .Values.additionalTrustBundleConfigMapName | default "ntnx-additional-trust-bundle-konnector-agent" }}
{{- end }}

{{/*
Check if trust bundle volume should be mounted
*/}}
{{- define "k8s-agent.shouldMountTrustBundle" -}}
{{- $configMapName := include "k8s-agent.trustBundleConfigMapName" . }}
{{- $namespace := include "k8s-agent.namespace" . }}
{{- $existingConfigMap := lookup "v1" "ConfigMap" $namespace $configMapName }}
{{- if or (ne .Values.pc.additionalTrustBundle "") (ne .Values.additionalTrustBundleConfigMapName "") $existingConfigMap }}
true
{{- end }}
{{- end }}

{{/*
Check if ConfigMap should be created or updated
Returns "true" if ConfigMap should be created/updated
*/}}
{{- define "k8s-agent.shouldCreateTrustBundleConfigMap" -}}
{{- if ne .Values.pc.additionalTrustBundle "" }}
{{- $configMapName := include "k8s-agent.trustBundleConfigMapName" . }}
{{- $namespace := include "k8s-agent.namespace" . }}
{{- $existingConfigMap := lookup "v1" "ConfigMap" $namespace $configMapName }}
{{- if not $existingConfigMap }}
true
{{- else if and $existingConfigMap.metadata.labels (hasKey $existingConfigMap.metadata.labels "app.kubernetes.io/managed-by") }}
{{- if eq (index $existingConfigMap.metadata.labels "app.kubernetes.io/managed-by") "Helm" }}
true
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate trust bundle configuration
Fails if insecure is false but no trust bundle or ConfigMap is available
*/}}
{{- define "k8s-agent.validateTrustBundle" -}}
{{- if not .Values.pc.insecure }}
{{- $configMapName := include "k8s-agent.trustBundleConfigMapName" . }}
{{- $namespace := include "k8s-agent.namespace" . }}
{{- $existingConfigMap := lookup "v1" "ConfigMap" $namespace $configMapName }}
{{- if and (eq .Values.pc.additionalTrustBundle "") (not $existingConfigMap) }}
{{- fail (printf "Error: When insecure is false and additionalTrustBundle is not provided, ConfigMap '%s' must already exist in namespace '%s'" $configMapName $namespace) }}
{{- end }}
{{- end }}
{{- end }}
