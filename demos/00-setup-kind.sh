#!/usr/bin/env bash
# Bootstrap kind cluster + CNPG operator + Barman Cloud plugin sidecar + SeaweedFS + kube-prometheus-stack.
# Idempotent. Re-run safe.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-hafen}"
CNPG_VERSION="${CNPG_VERSION:-1.30.0}"
PLUGIN_VERSION="${PLUGIN_VERSION:-0.14.0}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.1}"
SEAWEEDFS_VERSION="${SEAWEEDFS_VERSION:-4.44}"
AWSCLI_VERSION="${AWSCLI_VERSION:-2.36.31}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-hafenmeister}"
S3_SECRET_KEY="${S3_SECRET_KEY:-schuppen52rules}"
GRAFANA_DASHBOARD_ID="${GRAFANA_DASHBOARD_ID:-20417}"

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

blue "==> kind cluster: ${CLUSTER_NAME}"
if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
EOF
else
  green "kind cluster ${CLUSTER_NAME} already exists"
fi

blue "==> cert-manager (required by Barman plugin)"
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s

blue "==> CNPG operator ${CNPG_VERSION}"
kubectl apply --server-side -f \
  "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v${CNPG_VERSION}/cnpg-${CNPG_VERSION}.yaml"
kubectl -n cnpg-system rollout status deploy/cnpg-controller-manager --timeout=180s

blue "==> Barman Cloud plugin ${PLUGIN_VERSION} (sidecar)"
kubectl apply -f \
  "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${PLUGIN_VERSION}/manifest.yaml"
kubectl -n cnpg-system rollout status deploy/barman-cloud --timeout=180s

blue "==> SeaweedFS ${SEAWEEDFS_VERSION} (in-cluster S3, Apache-2.0)"
# Why not MinIO: MinIO is AGPLv3 and its community console was gutted upstream.
# SeaweedFS is Apache-2.0 and its S3 gateway is well exercised by backup tooling.
# `weed server -s3` runs master+volume+filer+s3 in a single container.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata: { name: seaweedfs }
---
apiVersion: v1
kind: ConfigMap
metadata: { name: seaweedfs-s3-config, namespace: seaweedfs }
data:
  s3.json: |
    {
      "identities": [
        {
          "name": "hafenmeister",
          "credentials": [
            { "accessKey": "${S3_ACCESS_KEY}", "secretKey": "${S3_SECRET_KEY}" }
          ],
          "actions": ["Admin", "Read", "List", "Tagging", "Write"]
        }
      ]
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: seaweedfs, namespace: seaweedfs }
spec:
  replicas: 1
  selector: { matchLabels: { app: seaweedfs } }
  template:
    metadata: { labels: { app: seaweedfs } }
    spec:
      containers:
      - name: seaweedfs
        image: chrislusf/seaweedfs:${SEAWEEDFS_VERSION}
        args:
          - server
          - -dir=/data
          - -s3
          - -s3.port=9000
          - -s3.config=/etc/seaweedfs/s3.json
          - -master.volumeSizeLimitMB=1024
        ports:
        - { name: s3,    containerPort: 9000 }
        - { name: filer, containerPort: 8888 }
        volumeMounts:
        - { name: data,   mountPath: /data }
        - { name: config, mountPath: /etc/seaweedfs }
        readinessProbe:
          tcpSocket: { port: 9000 }
          initialDelaySeconds: 5
          periodSeconds: 3
      volumes:
      - { name: data, emptyDir: {} }
      - { name: config, configMap: { name: seaweedfs-s3-config } }
---
apiVersion: v1
kind: Service
metadata: { name: seaweedfs, namespace: seaweedfs }
spec:
  selector: { app: seaweedfs }
  ports:
  - { name: s3,    port: 9000, targetPort: 9000 }
  - { name: filer, port: 8888, targetPort: 8888 }
EOF
kubectl -n seaweedfs rollout status deploy/seaweedfs --timeout=180s

blue "==> Create bucket 'hafen-backups' (AWS CLI, Apache-2.0 — not MinIO's AGPL 'mc')"
kubectl -n seaweedfs delete job bucket-setup --ignore-not-found
kubectl -n seaweedfs apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata: { name: bucket-setup, namespace: seaweedfs }
spec:
  backoffLimit: 5
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: awscli
        image: amazon/aws-cli:${AWSCLI_VERSION}
        env:
        - { name: AWS_ACCESS_KEY_ID,     value: "${S3_ACCESS_KEY}" }
        - { name: AWS_SECRET_ACCESS_KEY, value: "${S3_SECRET_KEY}" }
        - { name: AWS_DEFAULT_REGION,    value: "us-east-1" }
        command: ["/bin/sh", "-c"]
        args:
          - |
            until aws --endpoint-url http://seaweedfs:9000 s3 ls >/dev/null 2>&1; do
              echo "waiting for seaweedfs s3 ..."; sleep 3
            done
            aws --endpoint-url http://seaweedfs:9000 s3 mb s3://hafen-backups || true
            aws --endpoint-url http://seaweedfs:9000 s3 ls
EOF
kubectl -n seaweedfs wait --for=condition=complete job/bucket-setup --timeout=180s

blue "==> kube-prometheus-stack (for Grafana + Prometheus)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.adminPassword=hafen \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --wait

blue "==> Monitoring wiring: operator PodMonitor + CNPG dashboard ${GRAFANA_DASHBOARD_ID}"
kubectl apply -f "$(dirname "$0")/monitoring/podmonitor-operator.yaml"
# instance metrics — enablePodMonitor is deprecated since 1.30, so we manage these ourselves
kubectl apply -f "$(dirname "$0")/monitoring/podmonitor.yaml"

# Grafana's sidecar picks up any ConfigMap labelled grafana_dashboard=1. The published
# dashboard ships with ${DS_PROMETHEUS} placeholders from grafana.com's import flow;
# unresolved they render as "Missing request" panels, so substitute the real datasource uid.
DASH_JSON="$(mktemp)"
if curl -sfL "https://grafana.com/api/dashboards/${GRAFANA_DASHBOARD_ID}/revisions/latest/download" -o "${DASH_JSON}"; then
  python3 - "${DASH_JSON}" <<'PYEOF'
import json, sys
p = sys.argv[1]
raw = open(p).read().replace('${DS_PROMETHEUS}', 'prometheus').replace('${DS_EXPRESSION}', '__expr__')
d = json.loads(raw)
d.pop('__inputs', None)
d.pop('__requires', None)
d['title'] = 'CloudNativePG'
json.dump(d, open(p, 'w'))
PYEOF
  kubectl -n monitoring create configmap cnpg-dashboard \
    --from-file=cnpg.json="${DASH_JSON}" --dry-run=client -o yaml \
    | kubectl label -f- --local --dry-run=client -o yaml grafana_dashboard=1 \
    | kubectl apply -f -
  green "dashboard ${GRAFANA_DASHBOARD_ID} provisioned"
else
  red "could not download dashboard ${GRAFANA_DASHBOARD_ID} - import it by hand in Grafana"
fi
rm -f "${DASH_JSON}"

green "==> All set."
echo
echo "Grafana:  kubectl -n monitoring port-forward svc/kps-grafana 3000:80   (admin/hafen)"
echo "SeaweedFS: kubectl -n seaweedfs port-forward svc/seaweedfs 8888:8888   (filer UI, browse the bucket)"
echo
echo "Next: kubectl apply -f 01-cluster.yaml"
