{{/*
Expand the name of the chart.
*/}}
{{- define "multus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "multus.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "multus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "multus.labels" -}}
helm.sh/chart: {{ include "multus.chart" . }}
{{ include "multus.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "multus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "multus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "multus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "multus.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Multus configuration JSON
*/}}
{{- define "multus.config" -}}
{
    "chrootDir": "{{ .Values.daemonConfig.chrootDir }}",
    "cniVersion": "{{ .Values.daemonConfig.cniVersion }}",
    "logLevel": "{{ .Values.daemonConfig.logLevel }}",
    "logToStderr": {{ .Values.daemonConfig.logToStderr }},
    "cniConfigDir": "{{ .Values.daemonConfig.cniConfigDir }}",
    {{- if .Values.daemonConfig.readinessIndicatorFile }}
    "readinessIndicatorFile": "{{ .Values.daemonConfig.readinessIndicatorFile }}",
    {{- end }}
    "multusAutoconfigDir": "{{ .Values.daemonConfig.multusAutoconfigDir }}",
    "multusConfigFile": "{{ .Values.daemonConfig.multusConfigFile }}",
    "socketDir": "{{ .Values.daemonConfig.socketDir }}"
}
{{- end }}

{{/*
Init container volume mounts for installing CNI binaries
*/}}
{{- define "multus.initContainerVolumeMounts" -}}
- name: cnibin
  mountPath: /host/opt/cni/bin
  mountPropagation: Bidirectional
{{- end }}

{{/*
Core CNI volume mounts - essential for CNI operations
*/}}
{{- define "multus.coreVolumeMounts" -}}
- name: cni
  mountPath: /host/etc/cni/net.d
- name: cnibin
  mountPath: /opt/cni/bin
- name: multus-daemon-config
  mountPath: /etc/cni/net.d/multus.d
  readOnly: true
- name: multus-conf-dir
  mountPath: /etc/cni/multus/net.d
{{ end }}

{{/*
Host filesystem volume mounts - for accessing host resources
*/}}
{{- define "multus.hostVolumeMounts" -}}
- name: hostroot
  mountPath: /hostroot
  mountPropagation: HostToContainer
- name: host-run
  mountPath: /host/run
- name: host-var-lib-cni-multus
  mountPath: /var/lib/cni/multus
- name: host-var-lib-kubelet
  mountPath: /var/lib/kubelet
  mountPropagation: HostToContainer
- name: host-run-k8s-cni-cncf-io
  mountPath: /run/k8s.cni.cncf.io
- name: host-run-netns
  mountPath: /run/netns
  mountPropagation: HostToContainer
{{ end }}

{{/*
Dynamic primary CNI socket mount - configured by the client.
Only included when readinessIndicatorFile is defined
*/}}
{{- define "multus.primaryCNISocketMount" -}}
{{- if .Values.daemonConfig.readinessIndicatorFile }}
- name: primary-cni-sock
  mountPath: {{ .Values.daemonConfig.readinessIndicatorFile }}
  readOnly: true
{{ end }}
{{- end }}

{{/*
All volume mounts for main container
*/}}
{{- define "multus.volumeMounts" -}}
{{- include "multus.coreVolumeMounts" . }}
{{- include "multus.hostVolumeMounts" . }}
{{- include "multus.primaryCNISocketMount" . }}
{{- end }}

{{/*
All volumes definition
*/}}
{{- define "multus.volumes" -}}
- name: cni
  hostPath:
    path: /etc/cni/net.d
- name: cnibin
  hostPath:
    path: /opt/cni/bin
- name: hostroot
  hostPath:
    path: /
- name: multus-daemon-config
  configMap:
    name: {{ include "multus.fullname" . }}-config
- name: host-run
  hostPath:
    path: /run
- name: host-var-lib-cni-multus
  hostPath:
    path: /var/lib/cni/multus
- name: host-var-lib-kubelet
  hostPath:
    path: /var/lib/kubelet
- name: host-run-k8s-cni-cncf-io
  hostPath:
    path: /run/k8s.cni.cncf.io
- name: host-run-netns
  hostPath:
    path: /run/netns/
- name: multus-conf-dir
  hostPath:
    path: /etc/cni/multus/net.d
{{- if .Values.daemonConfig.readinessIndicatorFile }}
- name: primary-cni-sock
  hostPath:
    path: {{ .Values.daemonConfig.readinessIndicatorFile }}
    type: Socket
{{- end }}
{{- end }}

{{/*
Create the image tag for Multus
*/}}
{{- define "multus.imageTag" -}}
{{- if .Values.image.tag }}
{{- .Values.image.tag }}
{{- else if .Values.image.suffix }}
{{- .Chart.AppVersion }}{{ .Values.image.suffix }}
{{- else }}
{{- .Chart.AppVersion }}
{{- end }}
{{- end }}
