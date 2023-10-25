#!/usr/bin/env bash

set -euo pipefail

## If execution env is CI value will be "true"
CI="${CI:-false}"

## If value is "true" then script will skip committing and pushing charts and will only print the diff
DRY_RUN="${DRY_RUN:-true}"

## CT related variables to be used in the script.
CT_CHART_DIRS="${CT_CHART_DIRS:-"stable,staging"}"
CT_TARGET_BRANCH="${CT_TARGET_BRANCH:-"master"}"
CT_SINCE="${CT_SINCE:-"HEAD~1"}"

## Repository related variables to be used in the script.
BRANCH=${BRANCH:-"gh-pages"}
GIT_REMOTE_URL=${GIT_REMOTE_URL:-$(git config --get remote.origin.url)}

## Git related variables to be used in the script.
COMMIT_USERNAME=${COMMIT_USERNAME:-"D2iQ CI"}
COMMIT_EMAIL=${COMMIT_EMAIL:-"ci@mesosphere.com"}
COMMIT_MESSAGE=${COMMIT_MESSAGE:-$(git log -1 --no-show-signature --pretty=format:'%B')} # Use the commit message from the last commit

## Helm related variables to be used in the script.
HELM_LINT=${HELM_LINT:-"false"}
HELM_DEP_UPDATE=${HELM_DEP_UPDATE:-"false"}
HELM_CHARTS_URL=${HELM_CHARTS_URL:-"https://mesosphere.github.io/charts"}

## Runtime variables to be used in the script.
CHARTS=()
CHARTS_TMP_DIR=$(mktemp -d -t charts-XXXXXXXXXX)

## log group start, this is used to group logs in CI. For non CI envs this is just a regular echo
logGroupStart() {
  if [[ "${CI}" == "true" ]]; then
    echo "::group::${1}"
  else
    echo "================================================================================"
    echo "$1"
    echo "================================================================================"
  fi
}

## log group end, this is used to group logs in CI. For non CI envs this is no-op
logGroupEnd() {
  if [[ "${CI}" == "true" ]]; then
    echo "::endgroup::"
  fi
}

## Finds changed charts since a given CT_TARGET_BRANCH and CT_SINCE ref.
findChangedCharts() {
  logGroupStart "Finding changed charts"

  while IFS= read -r chart; do
    echo "Adding ${chart} to charts list"
    CHARTS+=("${chart}")
  done < <(ct list-changed --chart-dirs "$CT_CHART_DIRS" --target-branch "$CT_TARGET_BRANCH" --since "$CT_SINCE")

  logGroupEnd
}

## Creates new helm package for each chart in CHARTS array.
package() {
  logGroupStart "Packaging charts"

  for chart in "${CHARTS[@]}"; do
    helm package "$chart" --destination "${CHARTS_TMP_DIR}/$(dirname "$chart")"
  done

  logGroupEnd
}

## Lints each chart in CHARTS array.
lint() {
  logGroupStart "Linting charts"

  helm lint "${CHARTS[@]}"

  logGroupEnd
}

## Updates dependencies for each chart in CHARTS array.
depUpdate() {
  logGroupStart "Updating dependencies"

  for chart in "${CHARTS[@]}"; do
    helm dep update "$chart"
  done

  logGroupEnd
}

## Uploads built charts to the charts repository.
upload() {
  logGroupStart "Uploading charts"

  tmpDir=$(mktemp -d)
  pushd "${tmpDir}" >/dev/null

  git clone "$GIT_REMOTE_URL" "repo"
  cd "repo"
  git checkout "$BRANCH"

  git config user.name "${COMMIT_USERNAME}"
  git config user.email "${COMMIT_EMAIL}"
  git remote set-url origin "${GIT_REMOTE_URL}"

  # Update chart repo for each chart directory
  echo "${CT_CHART_DIRS}" | tr "," "\n" | while read -r chartDir; do
    if [[ ! -d "${CHARTS_TMP_DIR}/${chartDir}" ]]; then
      echo "No charts found for ${chartDir}. Skipping..."
      continue
    fi

    mkdir -p "${chartDir}"

    # Copy all charts from the temporary directory to the charts repository and update the index
    if [[ -f "${chartDir}/index.yaml" ]]; then
      echo "Found index for ${chartDir}. merging changes..."
      helm repo index "${CHARTS_TMP_DIR}" --url "${HELM_CHARTS_URL}" --merge "${chartDir}/index.yaml"
      mv -f "${CHARTS_TMP_DIR}/${chartDir}"/*.tgz "${chartDir}"
      mv -f "${CHARTS_TMP_DIR}/index.yaml" "${chartDir}/index.yaml"
    else
      echo "No index found, generating a new one for ${chartDir}..."
      mv -f "${CHARTS_TMP_DIR}/${chartDir}"/*.tgz "${chartDir}"
      helm repo index "${chartDir}" --url "${HELM_CHARTS_URL}"
    fi

    git add "${chartDir}"
    git add "${chartDir}/index.yaml"
  done

  # print the diff before committing and pushing
  git diff HEAD | cat

  # if DRY_RUN is set to "true" then skip committing and pushing changes
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry run, skipping commit and push"
    exit 0
  fi

  # commit and push changes
  git commit -m "${COMMIT_MESSAGE}"
  git push origin "$BRANCH"

  popd >&/dev/null
  rm -rf "$tmpDir"

  logGroupEnd
}

## Executes the script.
run_cmd() {
  findChangedCharts

  if [[ "${#CHARTS[@]}" -eq 0 ]]; then
    echo "No charts to package and upload"
    exit 0
  fi

  if [[ "${HELM_LINT}" == "true" ]]; then
    lint
  fi

  if [[ "${HELM_DEP_UPDATE}" == "true" ]]; then
    depUpdate
  fi

  package
  upload
}

run_cmd "$@"
