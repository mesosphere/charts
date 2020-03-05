#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

readonly KIND_VERSION=v0.6.1
readonly CLUSTER_NAME=chart-testing
readonly K8S_VERSION=v1.16.3

tmp=$(mktemp -d)

run_ct_container() {
    echo 'Running ct container...'
    teamcity_volume=()
    if [[ -n ${TEAMCITY_VERSION+x} ]]; then
        teamcity_volume=(-v /teamcity/system/git:/teamcity/system/git)
    fi
    docker run --rm --interactive --detach --network host --name ct \
        --volume "$(pwd)/test/ct-e2e.yaml:/etc/ct/ct.yaml" \
        --volume "$(pwd):/workdir" \
        "${teamcity_volume[@]}" \
        --workdir /workdir \
        "quay.io/helmpack/chart-testing:$1" \
        cat
    echo
}

cleanup() {
    echo 'Removing ct container...'
    docker kill ct > /dev/null 2>&1
    "${tmp}/kind" delete cluster --name "$CLUSTER_NAME"
    rm -rf "${tmp}"
    echo 'Done!'
}

docker_exec() {
    docker exec --interactive ct "$@"
}

create_kind_cluster() {
    echo 'Downloading kind...'

    curl -fsSLo "${tmp}/kind" \
        "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-$(uname)-amd64"
    chmod +x "${tmp}/kind"

    # This gist link is a temporary solution until that file is contributed to github.com/kubernetes-sigs/kind.
    # See https://jira.d2iq.com/browse/D2IQ-65095
    curl -fsSLo "${tmp}/entrypoint.sh" "https://gist.githubusercontent.com/d2iq-dispatch/9f67e6a97aafac7f8524dc8d4631ae98/raw/291543d4de29c85f9699c1b11d9c4643cce0f77a/gistfile1.txt"
    chmod +x "${tmp}/entrypoint.sh"

    cat << EOF > tmp_dockerfile
FROM kindest/node:$K8S_VERSION
ADD ./entrypoint.sh /usr/local/bin/entrypoint
EOF

    docker build -t tmp-dispatch-kind:latest -f tmp_dockerfile "${tmp}"

    "${tmp}/kind" create cluster --name "$CLUSTER_NAME" \
        --config test/kind-config.yaml --image "tmp-dispatch-kind:latest" \
        --wait 60s

    docker_exec mkdir -p /root/.kube

    echo 'Copying kubeconfig to container...'
    "${tmp}/kind" get kubeconfig --name "$CLUSTER_NAME" > "${tmp}/kube.config"
    docker cp "${tmp}/kube.config" ct:/root/.kube/config

    docker_exec kubectl cluster-info
    echo

    docker_exec kubectl get nodes
    echo

    echo 'Cluster ready!'
    echo
}

install_local-path-provisioner() {
    # kind doesn't support Dynamic PVC provisioning yet, this is one ways to
    # get it working
    # https://github.com/rancher/local-path-provisioner

    # Remove default storage class. It will be recreated by
    # local-path-provisioner
    docker_exec kubectl delete storageclass standard

    echo 'Installing local-path-provisioner...'
    docker_exec kubectl apply -f \
        https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    echo
}

install_tiller() {
    echo 'Installing tiller...'
    docker_exec kubectl --namespace kube-system create serviceaccount tiller
    docker_exec kubectl create clusterrolebinding tiller-cluster-rule \
        --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    docker_exec helm init --history-max 10 --service-account tiller --wait
    echo
}

install_certmanager() {
    echo 'Generating root ca...'
    docker_exec apk add openssl
    docker_exec openssl genrsa -out /tmp/ca.key 4096
    docker_exec openssl req -x509 -new -nodes -key /tmp/ca.key \
        -sha256 -days 1 -out /tmp/ca.crt -subj "/CN=testing"
    echo

    echo 'Installing cert-manager...'
    docker_exec kubectl create namespace cert-manager
    docker_exec kubectl create secret tls kubernetes-root-ca \
        --namespace=cert-manager --cert=/tmp/ca.crt --key=/tmp/ca.key
    docker_exec helm install \
        --values staging/cert-manager-setup/ci/test-values.yaml \
        --namespace cert-manager staging/cert-manager-setup
    echo
}

install_dummylb() {
    echo 'Installing dummylb...'
    DUMMYLB_SHA="cb4c17d70e63393f8de7cfa97d186aa06e781b3cd25bfff1f374b9d57159e80f"
    DUMMYLB_REG="registry.gitlab.com/joejulian/dummylb"
    curl -sL https://gitlab.com/joejulian/dummylb/-/raw/f5c51f24e706cd4c5ebe7e5d36e688d167473f8b/dummylb.yaml |
      sed "s%image: $DUMMYLB_REG:latest%image: $DUMMYLB_REG@sha256:$DUMMYLB_SHA%" |
      docker_exec kubectl apply -f -
    echo
}

main() {
    run_ct_container "$1"
    shift
    trap cleanup EXIT

    create_kind_cluster
    install_local-path-provisioner
    install_tiller
    install_dummylb
    install_certmanager

    docker_exec ct lint-and-install --upgrade --debug "$@"
    echo
}

main "$@"
