#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

readonly KIND_VERSION=v0.9.0
KINDEST_NODE_IMAGE=kindest/node
# full SHA256!
KINDEST_NODE_VERSION=v1.19.1@sha256:98cf5288864662e37115e362b23e4369c8c4a408f99cbc06e58ac30ddc721600
readonly CLUSTER_NAME=chart-testing
CT_VERSION=$1
HELM_VERSION=$2
GIT_REMOTE_NAME=${GIT_REMOTE_NAME:=origin}
CURL_RETRY_OPTS="--max-time 10 --retry 10 --retry-max-time 60 --retry-connrefused"

tmp=$(mktemp -d)

run_ct_container() {
    echo 'Running ct container...'
    teamcity_volume=()
    if [[ -n ${TEAMCITY_VERSION+x} ]]; then
        teamcity_volume=(-v /teamcity/system/git:/teamcity/system/git)
    fi
    docker run --rm --interactive --detach --network host --name ct \
        "${teamcity_volume[@]}" \
        --workdir /charts \
        "quay.io/helmpack/chart-testing:${CT_VERSION}" \
        cat
    echo

    if [[ "${HELM_VERSION}" =~ ^v2.* ]]; then
        docker cp "$(pwd)/test/helm2/ct-e2e.yaml" "ct:/etc/ct/ct.yaml"
        docker cp "$(pwd)/." "ct:/charts"
    else
        docker cp "$(pwd)/test/helm3/ct-e2e.yaml" "ct:/etc/ct/ct.yaml"
        docker cp "$(pwd)/." "ct:/charts"
    fi
    docker_exec chown -R root:root /charts
}

cleanup() {
    echo 'Removing ct container...'
    docker kill ct > /dev/null 2>&1
    "${tmp}/kind" delete cluster --name "$CLUSTER_NAME"
    git checkout $(pwd)/test/kind-config.yaml
    rm -rf "${tmp}"
    echo 'Done!'
}

docker_exec() {
    docker exec --interactive ct "$@"
}

create_kind_cluster() {
    echo 'Downloading kind...'

    curl ${CURL_RETRY_OPTS} -fsSLo "${tmp}/kind" \
        "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-$(uname)-amd64"
    chmod +x "${tmp}/kind"
    cp "$(pwd)/test/kind-entrypoint-wrapper.sh" "${tmp}/kind-entrypoint-wrapper.sh"

    # if we are running inside of a kubernetes cluster with /kubepods cgroup
    # being used for pods --> add kubeadmConfigPatches
    if tail -1 /proc/1/cgroup 2>/dev/null | grep -q /kubepods; then

      cat << EOF > tmp_dockerfile
FROM kindest/node:$KINDEST_NODE_VERSION
RUN mv /usr/local/bin/entrypoint /usr/local/bin/entrypoint-original
COPY kind-entrypoint-wrapper.sh /usr/local/bin/entrypoint
EOF

      cat <<EOF >>"$(pwd)/test/kind-config.yaml"
# These kubeadm config patches are required for running KIND inside a container.
# We started running KIND in a kubernetes pod as part of the CI transition to Dispatch.
kubeadmConfigPatches:
- |
  apiVersion: kubeadm.k8s.io/v1beta2
  kind: JoinConfiguration
  metadata:
    name: config
  nodeRegistration:
    kubeletExtraArgs:
      cgroup-root: "/kubelet"
- |
  apiVersion: kubeadm.k8s.io/v1beta2
  kind: InitConfiguration
  metadata:
    name: config
  nodeRegistration:
    kubeletExtraArgs:
      cgroup-root: "/kubelet"
EOF

      KINDEST_NODE_IMAGE=dispatch-kind
      KINDEST_NODE_VERSION=${KINDEST_NODE_VERSION%@*}
      docker build -t ${KINDEST_NODE_IMAGE}:${KINDEST_NODE_VERSION} -f tmp_dockerfile "${tmp}"
    fi

    "${tmp}/kind" create cluster --name "$CLUSTER_NAME" \
        --config test/kind-config.yaml --image "${KINDEST_NODE_IMAGE}:${KINDEST_NODE_VERSION}" \
        --wait 60s

    docker_exec mkdir -p /root/.kube

    echo 'Copying kubeconfig to container...'
    "${tmp}/kind" get kubeconfig --name "$CLUSTER_NAME" > "${tmp}/kube.config"
    docker cp "${tmp}/kube.config" ct:/root/.kube/config

    docker_exec kubectl cluster-info
    echo

    docker_exec kubectl get nodes
    echo

# TODO as of release v0.8.1 of kind there is still and mtu issue, this resolves it, should remove these lines after next release
    cat <<EOF | docker_exec kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kindnet
  namespace: kube-system
  labels:
    tier: node
    app: kindnet
    k8s-app: kindnet
spec:
  selector:
    matchLabels:
      app: kindnet
  template:
    metadata:
      labels:
        tier: node
        app: kindnet
        k8s-app: kindnet
    spec:
      hostNetwork: true
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: kindnet
      containers:
      - name: kindnet-cni
        image: kindest/kindnetd:v20200707-3aec2c7e
        env:
        - name: HOST_IP
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: POD_SUBNET
          value: "10.244.0.0/16"
        volumeMounts:
        - name: cni-cfg
          mountPath: /etc/cni/net.d
        - name: xtables-lock
          mountPath: /run/xtables.lock
          readOnly: false
        - name: lib-modules
          mountPath: /lib/modules
          readOnly: true
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
            add: ["NET_RAW", "NET_ADMIN"]
      volumes:
      - name: cni-cfg
        hostPath:
          path: /etc/cni/net.d
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      - name: lib-modules
        hostPath:
          path: /lib/modules
EOF

    echo 'Cluster ready!'
    echo
}

install_helm() {
    echo 'Installing helm...'

    if [[ "${HELM_VERSION}" =~ ^v2.* ]]; then
        echo 'Installing tiller...'
        docker_exec kubectl --namespace kube-system create serviceaccount tiller
        docker_exec kubectl create clusterrolebinding tiller-cluster-rule \
            --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
        echo 'Installing helm v2...'
        docker_exec /bin/sh -c "curl ${CURL_RETRY_OPTS} -fsSL \
            https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
                | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm \
                && helm init --debug --history-max 10 --service-account tiller --wait"
    else
        echo 'Installing helm v3...'
        docker_exec /bin/sh -c "curl ${CURL_RETRY_OPTS} -fsSL \
            https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
                | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm"
    fi

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

    if [[ "${HELM_VERSION}" =~ ^v2.* ]]; then
        docker_exec helm install --debug \
            --values stable/cert-manager-setup/ci/test-values.yaml \
            --namespace cert-manager stable/cert-manager-setup
    else
        docker_exec helm install cert-manager --debug \
            --values stable/cert-manager-setup/ci/test-values.yaml \
            --namespace cert-manager stable/cert-manager-setup
    fi

    echo
}

install_dummylb() {
    echo 'Installing dummylb...'
    DUMMYLB_SHA="cb4c17d70e63393f8de7cfa97d186aa06e781b3cd25bfff1f374b9d57159e80f"
    DUMMYLB_REG="registry.gitlab.com/joejulian/dummylb"
    curl ${CURL_RETRY_OPTS} -sL https://gitlab.com/joejulian/dummylb/-/raw/f5c51f24e706cd4c5ebe7e5d36e688d167473f8b/dummylb.yaml |
      sed "s%image: $DUMMYLB_REG:latest%image: $DUMMYLB_REG@sha256:$DUMMYLB_SHA%" |
      docker_exec kubectl apply -f -
      docker_exec kubectl wait --timeout=180s --for=condition=Available --selector=app=dummylb deploy
    echo
}

install_reloader() {
    echo 'Installing reloader...'
    LATEST_TAG=$(set -o pipefail; curl ${CURL_RETRY_OPTS} -s https://api.github.com/repos/stakater/Reloader/releases/latest | awk '/tag_name/ {gsub("\"","",$2); gsub(",","",$2); print $2}')
    curl ${CURL_RETRY_OPTS} -sL "https://raw.githubusercontent.com/stakater/Reloader/$LATEST_TAG/deployments/kubernetes/reloader.yaml" |
      docker_exec kubectl apply -f -
      docker_exec kubectl wait --for=condition=Available --selector=app=reloader-reloader deploy
    echo
}

replace_priority_class_name_system_x_critical() {
    # only change if needed
    set +o pipefail
    REPLACE_CHARTS=$(set -o pipefail; git diff --name-only "$(git merge-base $GIT_REMOTE_NAME/master HEAD)" -- stable staging | { grep -E "(stable/)(aws|local|azure|gcp)" || test $? = 1; } | xargs -I {} dirname {} | sort | uniq)
    set -o pipefail
    if [[ -n ${REPLACE_CHARTS} ]]; then
      echo 'Replacing priorityClassName: system-X-critical'
      grep -rl "priorityClassName: system-" ${REPLACE_CHARTS} | xargs sed -i 's/system-.*-critical/null/g' 2>/dev/null || echo "Nothing to update"
    fi
    echo
}

main() {
    run_ct_container
    shift
    trap cleanup EXIT

    create_kind_cluster
    install_helm
    install_dummylb
    install_certmanager
    install_reloader

    replace_priority_class_name_system_x_critical

    docker_exec ct install --upgrade --debug "$@"
    echo
}

main "$@"
