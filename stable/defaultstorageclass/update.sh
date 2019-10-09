#!/usr/bin/env bash

if [ -z "$1" ]
  then
    echo "Usage: ${0} tag"
    exit 1
fi
TAG=${1}

# script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

TEMP="$(mktemp -d)"
OBJECTS_DIR="${TEMP}/objects.yaml"

git clone git@github.com:mesosphere/defaultstorageclass.git ${TEMP}
cd ${TEMP}
git checkout "tags/${TAG}"
cd config/default
kustomize edit set namespace namespace-to-replace
kustomize edit set nameprefix "prefix-replace-"
kustomize build . -o ${OBJECTS_DIR}

cd ${DIR}
go build -o bin/update cmd/update/main.go

rm templates/*.yaml
./bin/update ${OBJECTS_DIR}

rm -rf ${TEMP}
# causes errors in helm
rm bin/update
