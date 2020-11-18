#!/bin/bash
set -ex
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
DEFAULT_KOMMANDER_PATH='/workspace/ui-git'
DEFAULT_OUTPUT_PATH='/workspace/output/artifacts'
NEW_UUID=$(openssl rand -base64 12 | tr -dc a-z)

KOMMANDER_REPO_PATH="${KOMMANDER_REPO_PATH:-$DEFAULT_KOMMANDER_PATH}"
OUTPUT_PATH="${OUTPUT_PATH:-$DEFAULT_OUTPUT_PATH}"

if [ ! -d "$KOMMANDER_REPO_PATH" ]; then
  echo "Expected KOMMANDER_REPO_PATH to be set to the kommander repo"
  echo "$KOMMANDER_REPO_PATH was no directory"
  exit 1
fi

if [ ! -d "$OUTPUT_PATH" ]; then
  echo "Expected OUTPUT_PATH to be set to an existing directory"
  echo "$OUTPUT_PATH was no directory"
  exit 1
fi

if [ ! -d "$KOMMANDER_REPO_PATH/system-tests" ]; then
  echo "KOMMANDER_REPO_PATH did not contain the system-tests"
  echo "$KOMMANDER_REPO_PATH/system-tests was no directory"
  exit 1
fi

if [ -z "$COMMIT_INFO_BRANCH" ]; then
  echo "We need a the branch of the PR"
  exit 1
fi

if [ -z "$AWS_ACCESS_KEY" ]; then
  echo "Please provide the AWS_ACCESS_KEY env var"
  exit 1
fi

if [ -z "$AWS_SECRET_KEY" ]; then
  echo "Please provide the AWS_SECRET_KEY env var"
  exit 1
fi

if [ -z "$LICENSE" ]; then
  echo "Please provide the LICENSE env var"
  exit 1
fi

function teardown() {
  export KUBECONFIG=$PROJECT_ROOT/admin.conf
  mv "$KOMMANDER_REPO_PATH/system-tests/cypress/videos" "$OUTPUT_PATH/cypress-videos" || echo "No videos"
  mv "$KOMMANDER_REPO_PATH/system-tests/cypress/screenshots" "$OUTPUT_PATH/cypress-screenshots" || echo "No screenshots"

  cd "$PROJECT_ROOT"
  # Delete provisioned clusters
  kubectl delete konvoycluster --all-namespaces --all --wait
  ./konvoy down --yes

  rm -f clustername-ssh.{pem,pub}
  rm -f inventory.yaml
}

# install cypress dependencies
apt-get update && apt-get install -y libgbm-dev

# install system test dependencies in the background
cd "$KOMMANDER_REPO_PATH"
npm install >"$OUTPUT_PATH/kommander-install.log" 2>&1 &
KOMMANDER_INSTALL_PID=$!
cd "$KOMMANDER_REPO_PATH/system-tests"
npm install >"$OUTPUT_PATH/system-test-install.log" 2>&1 &
INSTALL_PID=$!

cd "$PROJECT_ROOT"

echo "Install Konvoy"
source ${PROJECT_ROOT}/test/e2e-kommander/install-konvoy.sh v1.6.0

# Generate SSH Keys
echo "Generate SSH Keys"
rm -f e2e-ssh.{pem,pub}
ssh-keygen -t rsa -N '' -f ./e2e-ssh
mv ./e2e-ssh ./e2e-ssh.pem

# Update cluster.yaml to define the Helm version we're using
echo "Create cluster.yaml for $COMMIT_INFO_BRANCH with name e2e-$NEW_UUID"
cat <<EOF > cluster.yaml
kind: ClusterProvisioner
apiVersion: konvoy.mesosphere.io/v1beta2
metadata:
  name: e2e-$NEW_UUID
  creationTimestamp: "2020-11-18T13:50:07Z"
spec:
  provider: aws
  aws:
    region: us-west-2
    vpc:
      overrideDefaultRouteTable: true
      enableInternetGateway: true
      enableVPCEndpoints: false
    availabilityZones:
      - us-west-2c
    elb:
      apiServerPort: 6443
    tags:
      owner: mesosphere/charts
      expiration: 90m
  nodePools:
    - name: worker
      count: 2
      machine:
        imageID: ami-0a248ce88bcc7bd23
        rootVolumeSize: 80
        rootVolumeType: gp2
        imagefsVolumeEnabled: true
        imagefsVolumeSize: 160
        imagefsVolumeType: gp2
        imagefsVolumeDevice: xvdb
        type: m5.2xlarge
    - name: control-plane
      controlPlane: true
      count: 1
      machine:
        imageID: ami-0a248ce88bcc7bd23
        rootVolumeSize: 80
        rootVolumeType: io1
        rootVolumeIOPS: 1000
        imagefsVolumeEnabled: true
        imagefsVolumeSize: 160
        imagefsVolumeType: gp2
        imagefsVolumeDevice: xvdb
        type: m5.xlarge
    - name: bastion
      bastion: true
      count: 0
      machine:
        imageID: ami-0a248ce88bcc7bd23
        rootVolumeSize: 10
        rootVolumeType: gp2
        imagefsVolumeEnabled: false
        type: m5.large
  sshCredentials:
    user: centos
    publicKeyFile: e2e-ssh.pub
    privateKeyFile: e2e-ssh.pem
  version: v1.6.0
---
kind: ClusterConfiguration
apiVersion: konvoy.mesosphere.io/v1beta2
metadata:
  name: e2e-$NEW_UUID
  creationTimestamp: "2020-11-18T13:50:07Z"
spec:
  kubernetes:
    version: 1.18.10
    networking:
      podSubnet: 192.168.0.0/16
      serviceSubnet: 10.0.0.0/18
      iptables:
        addDefaultRules: false
    cloudProvider:
      provider: aws
    admissionPlugins:
      enabled:
        - AlwaysPullImages
        - NodeRestriction
  containerNetworking:
    calico:
      version: v3.16.4
      encapsulation: ipip
      mtu: 1480
  containerRuntime:
    containerd:
      version: 1.3.7
  osPackages:
    enableAdditionalRepositories: true
  nodePools:
    - name: worker
  addons:
    - configRepository: https://github.com/mesosphere/kubernetes-base-addons
      configVersion: stable-1.18-3.0.0
      addonsList:
        - name: ambassador # Ambassador is currently in Preview
          enabled: false
        - name: awsebscsiprovisioner
          enabled: true
        - name: awsebsprovisioner
          enabled: false
          values: |
            storageclass:
              isDefault: false
        - name: cert-manager
          enabled: true
        - name: dashboard
          enabled: true
        - name: defaultstorageclass-protection
          enabled: true
        - name: dex
          enabled: true
        - name: dex-k8s-authenticator
          enabled: true
        - name: elasticsearch
          enabled: false
        - name: elasticsearch-curator
          enabled: false
        - name: elasticsearchexporter
          enabled: false
        - name: external-dns
          enabled: false
        - name: flagger
          enabled: false
        - name: fluentbit
          enabled: false
        - name: gatekeeper
          enabled: true
        - name: istio # Istio is currently in Preview
          enabled: false
        - name: kibana
          enabled: false
        - name: konvoyconfig
          enabled: true
        - name: kube-oidc-proxy
          enabled: true
        - name: localvolumeprovisioner
          enabled: false
          values: |
            storageclasses:
              - name: localvolumeprovisioner
                dirName: disks
                isDefault: false
                reclaimPolicy: Delete
                volumeBindingMode: WaitForFirstConsumer
        - name: nvidia
          enabled: false
        - name: opsportal
          enabled: true
        - name: prometheus
          enabled: false
        - name: prometheusadapter
          enabled: false
        - name: reloader
          enabled: true
        - name: traefik
          enabled: true
        - name: traefik-forward-auth
          enabled: true
        - name: velero
          enabled: false
    - configRepository: https://github.com/mesosphere/kubeaddons-dispatch
      configVersion: stable-1.18-1.3.0
      addonsList:
        - name: dispatch
          enabled: false
  version: v1.6.0
EOF

# Start the cluster
trap teardown EXIT
./konvoy up --yes

# Install kommander chart
export KUBECONFIG=$PROJECT_ROOT/admin.conf
docker run --network host -v "$PROJECT_ROOT:/charts" -e="KUBECONFIG=/charts/admin.conf" dtzar/helm-kubectl:3.4.0 helm install kubeaddons-kommander /charts/stable/kommander -n kommander --create-namespace --debug
kubectl apply -f "$PROJECT_ROOT/test/e2e-kommander/kommander-cluster-addon.yaml"

# Setup for tests
export KUBECONFIG=$PROJECT_ROOT/admin.conf
export CLUSTER_URL=https://$(kubectl -n kubeaddons get svc traefik-kubeaddons -o jsonpath={.status.loadBalancer.ingress[0].hostname})
export OPS_PORTAL_USER=$(kubectl get -n kubeaddons secret ops-portal-credentials -o jsonpath='{.data.username}' | base64 -d)
export OPS_PORTAL_PASSWORD=$(kubectl get -n kubeaddons secret ops-portal-credentials -o jsonpath='{.data.password}' | base64 -d)

# Run system tests against the cluster
cd "$KOMMANDER_REPO_PATH/system-tests"
wait $INSTALL_PID
wait $KOMMANDER_INSTALL_PID

kubectl -n kommander set env deploy/kommander-kubeaddons-kommander-ui LOG_LEVEL=debug
kubectl -n kommander wait deploy kommander-kubeaddons-kommander-ui --for condition=available --timeout=300s
kubectl logs -n kommander deploy/kommander-kubeaddons-kommander-ui --ignore-errors -f > "$OUTPUT_PATH/kommander-deploy.log" &

NEW_UUID=$NEW_UUID CLUSTER_URL=$CLUSTER_URL OPS_PORTAL_USER=$OPS_PORTAL_USER OPS_PORTAL_PASSWORD=$OPS_PORTAL_PASSWORD AWS_ACCESS_KEY=$AWS_ACCESS_KEY AWS_SECRET_KEY=$AWS_SECRET_KEY LICENSE=$LICENSE ADDONS="cassandra,jenkins,kafka,spark,zookeeper" npm test
