#!/usr/bin/env bash

# This patch adds mesosphere specific crd upgrade .

source $(dirname "$0")/helpers.sh

set -x

SRCFILE="${BASEDIR}"/templates/crds.yaml

sed -i '' -e '/# Create mesosphere value entries/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: {{ .Release.Namespace }}
  name: gatekeeper-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
data:
{{- range $path, $bytes := .Files.Glob "crds/*.yaml" }}
  {{ $path | trimPrefix "crds/" }}: {{ $.Files.Get $path  | quote }}
{{- end }}
---
apiVersion: batch/v1
kind: Job
metadata:
  namespace: {{ .Release.Namespace }}
  name: gatekeeper-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-4"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
spec:
  template:
    spec:
      serviceAccountName: gatekeeper-crds
      containers:
        - name: gatekeeper-crds
          image: "bitnami/kubectl:1.19.7"
          volumeMounts:
            - name: gatekeeper-crds
              mountPath: /etc/gatekeeper-crds
              readOnly: true
          command: ["kubectl", "apply", "-f", "/etc/gatekeeper-crds"]
      volumes:
        - name: gatekeeper-crds
          configMap:
            name: gatekeeper-crds
      restartPolicy: OnFailure
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gatekeeper-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
rules:
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["create", "get", "list", "watch", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gatekeeper-crds
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gatekeeper-crds
subjects:
  - kind: ServiceAccount
    name: gatekeeper-crds
    namespace: {{ .Release.Namespace }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gatekeeper-crds
  namespace: {{ .Release.Namespace }}
  annotations:
    "helm.sh/hook": pre-install, pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,before-hook-creation

EOF

git_add_and_commit "${BASEDIR}"/templates/crds.yaml
