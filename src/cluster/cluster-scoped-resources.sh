#!/usr/bin/env bash

########################################
# cluster-scoped-resources.sh
#
# Inventories cluster-scoped (non-namespaced)
# resources: Nodes, PersistentVolumes,
# StorageClasses, ClusterRoles,
# ClusterRoleBindings, CRDs, APIServices, and
# the full catalog of cluster-scoped API kinds.
#
# Strictly read-only. Output: stdout summary
# + JSON report.
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
OUTPUT_FILE="${OUTPUT_DIR}/cluster-scoped-resources.json"

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

print_header "Cluster-Scoped Resources"

log_info "Collecting cluster-scoped (non-namespaced) resources"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

# Core cluster-scoped resource counts
TOTAL_NODES="$(k_node_count)"
TOTAL_NAMESPACES="$(k_namespace_count)"
TOTAL_PVS="$(k_pvs | jq_items_count)"
TOTAL_STORAGE_CLASSES="$(k_storageclasses | jq_items_count)"
TOTAL_CLUSTERROLES="$(k_clusterroles | jq_items_count)"
TOTAL_CLUSTERROLEBINDINGS="$(k_clusterrolebindings | jq_items_count)"
TOTAL_CRDS="$(k_crd_count)"
TOTAL_APISERVICES="$(k_apiservices | jq_items_count)"

# Full catalog of cluster-scoped API kinds available in the cluster.
# Sorted and normalized to a JSON array for machine-readable output.
CLUSTER_SCOPED_KINDS_JSON="$(
  k_api_resources_cluster \
    | sort -u \
    | jq -R -s 'split("\n") | map(select(length > 0))'
)"

TOTAL_CLUSTER_SCOPED_KINDS="$(
  echo "${CLUSTER_SCOPED_KINDS_JSON}" | jq_count
)"

########################################
# JSON REPORT
########################################

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,

  cluster_scoped_kinds: {
    total: $total_kinds,
    kinds: $kinds
  },

  resources: {
    nodes: $nodes,
    namespaces: $namespaces,
    persistent_volumes: $pvs,
    storage_classes: $storage_classes,
    cluster_roles: $cluster_roles,
    cluster_role_bindings: $cluster_role_bindings,
    crds: $crds,
    apiservices: $apiservices
  }
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total_kinds "${TOTAL_CLUSTER_SCOPED_KINDS}" \
  --argjson kinds "${CLUSTER_SCOPED_KINDS_JSON}" \
  --argjson nodes "${TOTAL_NODES}" \
  --argjson namespaces "${TOTAL_NAMESPACES}" \
  --argjson pvs "${TOTAL_PVS}" \
  --argjson storage_classes "${TOTAL_STORAGE_CLASSES}" \
  --argjson cluster_roles "${TOTAL_CLUSTERROLES}" \
  --argjson cluster_role_bindings "${TOTAL_CLUSTERROLEBINDINGS}" \
  --argjson crds "${TOTAL_CRDS}" \
  --argjson apiservices "${TOTAL_APISERVICES}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"

echo

log_step "Cluster-Scoped API Kinds"
report_item "Available Kinds" "${TOTAL_CLUSTER_SCOPED_KINDS}"

echo

log_step "Core Resources"
report_item "Nodes" "${TOTAL_NODES}"
report_item "Namespaces" "${TOTAL_NAMESPACES}"
report_item "PersistentVolumes" "${TOTAL_PVS}"
report_item "StorageClasses" "${TOTAL_STORAGE_CLASSES}"

echo

log_step "RBAC (Cluster-Wide)"
report_item "ClusterRoles" "${TOTAL_CLUSTERROLES}"
report_item "ClusterRoleBindings" "${TOTAL_CLUSTERROLEBINDINGS}"

echo

log_step "Extensions"
report_item "CRDs" "${TOTAL_CRDS}"
report_item "APIServices" "${TOTAL_APISERVICES}"

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
