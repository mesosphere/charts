#!/usr/bin/env bash

# This patch adds mesosphere specific chart values.
# These are the values we reference in our custom templates.

source $(dirname "$0")/helpers.sh

set -x

SRCFILE="${BASEDIR}"/values.yaml

sed -i '' -e '/# Create mesosphere value entries/,$d' ${SRCFILE}

cat << EOF >> ${SRCFILE}
# ProxySettings
proxySettings:
  noProxy:
  httpProxy:
  httpsProxy:

# enable mutations
mutations:
  enable: false

  # proxy settings
  enablePodProxy: false

  podProxySettings:
    noProxy:
    httpProxy:
    httpsProxy:

  # apply mutations on objects whose labels match namespace labels
  namespaceSelectorForProxy: {}

  # disable the following namespaces
  excludeNamespacesFromProxy: []

# Adds a namespace selector to the validation controller webhook
admissionControllerNamespaceSelector:
  matchExpressions: []

# Adds an object selector to the validation controller webhook
admissionControllerObjectSelector:
  matchExpressions: []
  # - {key: foo, operator: NotIn, values: ["bar"]}
  matchLabels: []
  # - foo: bar

# Webhook configuration
webhook:
  # Setup the webhook using cert-manager
  certManager:
    enabled: false
EOF

# install yq and format the file or else ct.lint target will fail with follwing error:
#   <too many spaces inside braces  (braces)>
yq e -i ${SRCFILE}

git_add_and_commit "${BASEDIR}"/values.yaml
