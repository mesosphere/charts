#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

readonly KIND_VERSION=v0.7.0
readonly CLUSTER_NAME=chart-testing
readonly K8S_VERSION=v1.17.5
CT_VERSION=$1
HELM_VERSION=$2

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
        "quay.io/helmpack/chart-testing:${CT_VERSION}" \
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

install_tiller() {
    echo 'Installing tiller...'

    docker_exec kubectl --namespace kube-system create serviceaccount tiller
    docker_exec kubectl create clusterrolebinding tiller-cluster-rule \
        --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    docker_exec /bin/sh -c "curl -fsSL \
        https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
            | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm \
            && helm init --history-max 10 --service-account tiller --wait"
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

install_reloader() {
    echo 'Installing reloader...'
    LATEST_TAG=$(curl -s https://api.github.com/repos/stakater/Reloader/releases/latest | awk '/tag_name/ {gsub("\"","",$2); gsub(",","",$2); print $2}')
    curl -sL https://raw.githubusercontent.com/stakater/Reloader/${LATEST_TAG}/deployments/kubernetes/reloader.yaml |
      docker_exec kubectl apply -f -
    echo
}

replace_priority_class_name_system_x_critical() {
    echo 'Replacing priorityClassName: system-X-critical'
    grep -rl "priorityClassName: system-" --exclude-dir=test . | xargs sed -i 's/system-.*-critical/null/g'
    echo
}

main() {
    run_ct_container
    shift
    trap cleanup EXIT

    create_kind_cluster
    install_tiller
    install_dummylb
    install_certmanager
    install_reloader

    docker_exec ct lint --debug "$@"

    replace_priority_class_name_system_x_critical

    docker_exec ct install --upgrade --debug "$@"
    echo
}

main "$@"
