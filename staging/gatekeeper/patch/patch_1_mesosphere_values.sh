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
EOF

git_add_and_commit "${BASEDIR}"/values.yaml
