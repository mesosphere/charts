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
TEST_NAMESPACE="kubeaddons"

git clone git@github.com:mesosphere/defaultstorageclass.git ${TEMP}
cd ${TEMP}
git checkout "tags/${TAG}"

KUBECONFIG=$(kind get kubeconfig-path --name=kind)

make setup-deploy

KUBECONFIG=${KUBECONFIG} kubectl create serviceaccount tiller -n kube-system
KUBECONFIG=${KUBECONFIG} kubectl create clusterrolebinding tiller --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
KUBECONFIG=${KUBECONFIG} helm init --service-account tiller
# wait for tiller
NAMESPACE=kube-system make wait-for-pods
# tiller needs more sleeping time...
sleep 5

KUBECONFIG=${KUBECONFIG} kubectl create namespace ${TEST_NAMESPACE}
KUBECONFIG=${KUBECONFIG} kubectl create -f - <<EOF
apiVersion: certmanager.k8s.io/v1alpha1
kind: Issuer
metadata:
  creationTimestamp: null
  name: dstorageclass-selfsigned-issuer
  namespace: ${TEST_NAMESPACE}
spec:
  selfSigned: {}
status: {}
EOF

KUBECONFIG=${KUBECONFIG} helm install ${DIR} --namespace=${TEST_NAMESPACE} -f - <<EOF
issuer:
    name: dstorageclass-selfsigned-issuer
EOF
NAMESPACE=${TEST_NAMESPACE} make wait-for-pods

make run-e2e

rm -rf ${TEMP}
