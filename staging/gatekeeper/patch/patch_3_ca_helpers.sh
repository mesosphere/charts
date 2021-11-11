#!/usr/bin/env bash

# This patch adds mesosphere specific chart values.
# These are the values we reference in our custom templates.

source $(dirname "$0")/helpers.sh

set -x

SRCFILE="${BASEDIR}"/templates/_helpers.tpl

sed -i '' -e '/# Create mesosphere value entries/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}


{{- define "gatekeeper.selfSignedIssuer" -}}
{{ printf "%s-selfsign" (include "gatekeeper.fullname" .) }}
{{- end -}}

{{- define "gatekeeper.rootCAIssuer" -}}
{{ printf "%s-ca" (include "gatekeeper.fullname" .) }}
{{- end -}}

{{- define "gatekeeper.rootCACertificate" -}}
{{ printf "%s-ca" (include "gatekeeper.fullname" .) }}
{{- end -}}

{{- define "gatekeeper.servingCertificate" -}}
{{ printf "%s-webhook-tls" (include "gatekeeper.fullname" .) }}
{{- end -}}
EOF

git_add_and_commit ${SRCFILE}
