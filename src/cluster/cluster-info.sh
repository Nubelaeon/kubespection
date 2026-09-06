#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

OUTPUT_DIR="${OUTPUT_DIR:-output}"
OUTPUT_FILE="${OUTPUT_DIR}/cluster-info.json"

mkdir -p "${OUTPUT_DIR}"

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl not found"
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "jq not found"
  exit 1
}

CURRENT_CONTEXT="$(kubectl config current-context)"

K8S_VERSION="$(kubectl version -o json | jq -r '.serverVersion.gitVersion')"

TOTAL_NODES="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"

READY_NODES="$(
kubectl get nodes \
-o json \
| jq '[.items[]
| select(any(.status.conditions[];
      .type=="Ready" and .status=="True"))]
| length'
)"

NOT_READY_NODES="$((TOTAL_NODES-READY_NODES))"

TOTAL_NAMESPACES="$(
kubectl get ns --no-headers \
| wc -l \
| tr -d ' '
)"

TOTAL_CRDS="$(
kubectl get crd --no-headers 2>/dev/null \
| wc -l \
| tr -d ' '
)"

TOTAL_APISERVICES="$(
kubectl get apiservice --no-headers 2>/dev/null \
| wc -l \
| tr -d ' '
)"

STORAGE_CLASSES="$(
kubectl get storageclass -o json \
| jq -r '[.items[].metadata.name]'
)"

if kubectl top nodes >/dev/null 2>&1; then
  METRICS_SERVER=true
else
  METRICS_SERVER=false
fi

jq -n \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --arg version "${K8S_VERSION}" \
  --argjson total_nodes "${TOTAL_NODES}" \
  --argjson ready_nodes "${READY_NODES}" \
  --argjson not_ready_nodes "${NOT_READY_NODES}" \
  --argjson namespaces "${TOTAL_NAMESPACES}" \
  --argjson crds "${TOTAL_CRDS}" \
  --argjson apiservices "${TOTAL_APISERVICES}" \
  --argjson storage_classes "${STORAGE_CLASSES}" \
  --argjson metrics_server "${METRICS_SERVER}" \
'
{
  timestamp: $timestamp,
  context: $context,
  server_version: $version,
  nodes: {
    total: $total_nodes,
    ready: $ready_nodes,
    not_ready: $not_ready_nodes
  },
  namespaces: $namespaces,
  storage_classes: $storage_classes,
  crds: $crds,
  apiservices: $apiservices,
  metrics_server: $metrics_server
}
' > "${OUTPUT_FILE}"

echo
echo "Cluster Audit Summary"
echo "====================="
echo "Context.............: ${CURRENT_CONTEXT}"
echo "Version.............: ${K8S_VERSION}"
echo "Nodes...............: ${READY_NODES}/${TOTAL_NODES} Ready"
echo "Namespaces..........: ${TOTAL_NAMESPACES}"
echo "StorageClasses......: $(echo "${STORAGE_CLASSES}" | jq length)"
echo "CRDs................: ${TOTAL_CRDS}"
echo "APIServices.........: ${TOTAL_APISERVICES}"
echo "Metrics Server......: ${METRICS_SERVER}"
echo
echo "JSON report: ${OUTPUT_FILE}"
