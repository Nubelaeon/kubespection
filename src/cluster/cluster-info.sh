#!/usr/bin/env bash

########################################
# cluster-info.sh
#
# Collects high-level cluster metrics:
# context, Kubernetes version, node counts
# (total/ready/not-ready), namespace count,
# storage classes, CRDs, APIServices, and
# Metrics Server availability.
#
# Runs globally at cluster scope without
# namespace parameters.
#
# Output: stdout summary + JSON report
########################################

set -Eeuo pipefail

########################################
# PATHS
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${ROOT_DIR}/src/lib/logger.sh"
source "${ROOT_DIR}/src/lib/validations.sh"
source "${ROOT_DIR}/src/lib/kubectl.sh"
source "${ROOT_DIR}/src/lib/jq.sh"

register_error_trap

########################################
# CONFIG
########################################

OUTPUT_DIR="${OUTPUT_DIR:-output/cluster}"
OUTPUT_FILE="${OUTPUT_DIR}/cluster-info.json"

ensure_directory "${OUTPUT_DIR}"

START_TIME="$(timer_start)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

########################################
# PRECHECK
########################################

validate_cluster_access

########################################
# HEADER
########################################

print_header "Cluster Information"

log_info "Collecting cluster information"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

K8S_VERSION="$(
  k_version | jq_extract '.serverVersion.gitVersion'
)"

NODES_JSON="$(k_nodes)"

TOTAL_NODES="$(k_node_count)"

READY_NODES="$(
  echo "${NODES_JSON}" | jq_transform '.items' | jq_filter_count '
    any(
      .status.conditions[];
      .type=="Ready" and .status=="True"
    )
  '
)"

NOT_READY_NODES=$((TOTAL_NODES - READY_NODES))

TOTAL_NAMESPACES="$(k_namespace_count)"

TOTAL_CRDS="$(k_crd_count)"

TOTAL_APISERVICES="$(
  k_apiservices | jq_items_count
)"

STORAGE_CLASSES="$(
  k_storageclasses | jq_extract_names
)"

STORAGE_CLASSES_COUNT="$(
  echo "${STORAGE_CLASSES}" | jq_count
)"

if k_metrics_available; then
  METRICS_SERVER=true
else
  METRICS_SERVER=false
fi

########################################
# JSON REPORT
########################################

jq_build_report "${OUTPUT_FILE}" '
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
' \
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
  --argjson metrics_server "${METRICS_SERVER}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"
report_item "Kubernetes Version" "${K8S_VERSION}"

echo

report_item "Total Nodes" "${TOTAL_NODES}"
report_item "Ready Nodes" "${READY_NODES}"
report_item "Not Ready Nodes" "${NOT_READY_NODES}"

echo

report_item "Namespaces" "${TOTAL_NAMESPACES}"
report_item "Storage Classes" "${STORAGE_CLASSES_COUNT}"
report_item "CRDs" "${TOTAL_CRDS}"
report_item "APIServices" "${TOTAL_APISERVICES}"
report_item "Metrics Server" "${METRICS_SERVER}"

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
