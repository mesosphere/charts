#!/usr/bin/env bash

# The old CRD didn't have the alertmanagerConfigNamespaceSelector field. Defining
# this causes the chart to create the unused entry which causes a validation failure.
# Removing this avoids this problem for now.

# shellcheck disable=SC1090
source "$(dirname "$0")/helpers.sh"

set -xeuo pipefail

SRCFILE="${BASEDIR}"/values.yaml

sed -i '/^    alertmanagerConfigNamespaceSelector: {}$/d' "${SRCFILE}"
sed -i '/^    alertmanagerConfigSelector: {}$/d' "${SRCFILE}"

patch -d "${BASEDIR}" -p3 --no-backup-if-mismatch <<EOF
diff --git a/staging/prometheus-operator/templates/alertmanager/alertmanager.yaml b/staging/prometheus-operator/templates/alertmanager/alertmanager.yaml
index 1115e6145..9f0602e8d 100644
--- a/staging/prometheus-operator/templates/alertmanager/alertmanager.yaml
+++ b/staging/prometheus-operator/templates/alertmanager/alertmanager.yaml
@@ -47,14 +47,10 @@ spec:
 {{- if .Values.alertmanager.alertmanagerSpec.alertmanagerConfigSelector }}
   alertmanagerConfigSelector:
 {{ toYaml .Values.alertmanager.alertmanagerSpec.alertmanagerConfigSelector | indent 4}}
-{{ else }}
-  alertmanagerConfigSelector: {}
 {{- end }}
 {{- if .Values.alertmanager.alertmanagerSpec.alertmanagerConfigNamespaceSelector }}
   alertmanagerConfigNamespaceSelector:
 {{ toYaml .Values.alertmanager.alertmanagerSpec.alertmanagerConfigNamespaceSelector | indent 4}}
-{{ else }}
-  alertmanagerConfigNamespaceSelector: {}
 {{- end }}
 {{- if .Values.alertmanager.alertmanagerSpec.resources }}
   resources:
EOF

git_add_and_commit "${BASEDIR}"
