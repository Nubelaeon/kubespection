#!/usr/bin/env bash

########################################
# cluster-health.sh
#
# Evaluates overall cluster health by
# inspecting nodes, pods, workloads,
# storage, ingress, and API services.
#
# Produces a health score: HEALTHY,
# WARNING, or CRITICAL.
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
OUTPUT_FILE="${OUTPUT_DIR}/cluster-health.json"

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

print_header "Cluster Health"

log_info "Evaluating cluster health"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

NODES_JSON="$(k_nodes)"
PODS_JSON="$(k_pods)"
DEPLOYMENTS_JSON="$(k_deployments)"
STATEFULSETS_JSON="$(k_statefulsets)"
DAEMONSETS_JSON="$(k_daemonsets)"
PVCS_JSON="$(k_pvcs)"
INGRESS_JSON="$(k_ingresses)"
APISERVICE_JSON="$(k_apiservices)"

########################################
# NODES
########################################

TOTAL_NODES="$(echo "${NODES_JSON}" | jq_items_count)"

READY_NODES="$(
  echo "${NODES_JSON}" | jq_items_filter_count '
    any(.status.conditions[]; .type=="Ready" and .status=="True")
  '
)"

NOT_READY_NODES=$((TOTAL_NODES - READY_NODES))

MEMORY_PRESSURE="$(
  echo "${NODES_JSON}" | jq_items_filter_count '
    any(.status.conditions[]; .type=="MemoryPressure" and .status=="True")
  '
)"

DISK_PRESSURE="$(
  echo "${NODES_JSON}" | jq_items_filter_count '
    any(.status.conditions[]; .type=="DiskPressure" and .status=="True")
  '
)"

PID_PRESSURE="$(
  echo "${NODES_JSON}" | jq_items_filter_count '
    any(.status.conditions[]; .type=="PIDPressure" and .status=="True")
  '
)"

########################################
# PODS
########################################

TOTAL_PODS="$(echo "${PODS_JSON}" | jq_items_count)"

PENDING_PODS="$(
  echo "${PODS_JSON}" | jq_items_filter_count '.status.phase=="Pending"'
)"

FAILED_PODS="$(
  echo "${PODS_JSON}" | jq_items_filter_count '.status.phase=="Failed"'
)"

CRASHLOOP_PODS="$(
  echo "${PODS_JSON}" | jq_transform '
    [.items[] | .status.containerStatuses[]? | select(.state.waiting.reason=="CrashLoopBackOff")]
    | length
  '
)"

IMAGE_PULL_ERRORS="$(
  echo "${PODS_JSON}" | jq_transform '
    [.items[] | .status.containerStatuses[]?
      | select(.state.waiting.reason=="ImagePullBackOff" or .state.waiting.reason=="ErrImagePull")]
    | length
  '
)"

########################################
# PVC
########################################

PENDING_PVCS="$(
  echo "${PVCS_JSON}" | jq_items_filter_count '.status.phase!="Bound"'
)"

########################################
# DEPLOYMENTS
########################################

DEGRADED_DEPLOYMENTS="$(
  echo "${DEPLOYMENTS_JSON}" | jq_items_filter_count '
    (.status.readyReplicas // 0) != (.status.replicas // 0)
  '
)"

########################################
# STATEFULSETS
########################################

DEGRADED_STATEFULSETS="$(
  echo "${STATEFULSETS_JSON}" | jq_items_filter_count '
    (.status.readyReplicas // 0) != (.spec.replicas // 0)
  '
)"

########################################
# DAEMONSETS
########################################

DEGRADED_DAEMONSETS="$(
  echo "${DAEMONSETS_JSON}" | jq_items_filter_count '
    (.status.numberReady // 0) != (.status.desiredNumberScheduled // 0)
  '
)"

########################################
# APISERVICES
########################################

BROKEN_APISERVICES="$(
  echo "${APISERVICE_JSON}" | jq_items_filter_count '
    any(.status.conditions[]; .type=="Available" and .status=="False")
  '
)"

########################################
# INGRESS
########################################

INGRESS_WITHOUT_ADDRESS="$(
  echo "${INGRESS_JSON}" | jq_items_filter_count '
    (.status.loadBalancer.ingress // []) | length == 0
  '
)"

########################################
# METRICS SERVER
########################################

if k_metrics_available; then
  METRICS_SERVER=true
else
  METRICS_SERVER=false
fi

########################################
# HEALTH SCORE
########################################

HEALTH="HEALTHY"

if [[ "${NOT_READY_NODES}" -gt 0 ]]; then
  HEALTH="CRITICAL"
fi

if [[ "${CRASHLOOP_PODS}" -gt 0 ]]; then
  HEALTH="CRITICAL"
fi

if [[ "${BROKEN_APISERVICES}" -gt 0 ]]; then
  HEALTH="CRITICAL"
fi

if [[ "${HEALTH}" != "CRITICAL" ]]; then
  WARNINGS=$(
    (
      echo "${PENDING_PODS}"
      echo "${FAILED_PODS}"
      echo "${IMAGE_PULL_ERRORS}"
      echo "${PENDING_PVCS}"
      echo "${DEGRADED_DEPLOYMENTS}"
      echo "${DEGRADED_STATEFULSETS}"
      echo "${DEGRADED_DAEMONSETS}"
      echo "${INGRESS_WITHOUT_ADDRESS}"
    ) | awk '{s+=$1} END {print s+0}'
  )

  if [[ "${WARNINGS}" -gt 0 ]]; then
    HEALTH="WARNING"
  fi
fi

########################################
# JSON REPORT
########################################

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,
  health: $health,

  nodes: {
    total: $total_nodes,
    ready: $ready_nodes,
    not_ready: $not_ready_nodes,
    memory_pressure: $memory_pressure,
    disk_pressure: $disk_pressure,
    pid_pressure: $pid_pressure
  },

  workloads: {
    pending: $pending_pods,
    crashloop: $crashloop_pods,
    failed: $failed_pods,
    image_pull_errors: $image_pull_errors,
    degraded_deployments: $degraded_deployments,
    degraded_statefulsets: $degraded_statefulsets,
    degraded_daemonsets: $degraded_daemonsets
  },

  storage: {
    pending_pvcs: $pending_pvcs
  },

  network: {
    ingress_without_address: $ingress_without_address
  },

  apiservices: {
    broken: $broken_apiservices
  },

  observability: {
    metrics_server: $metrics_server
  }
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --arg health "${HEALTH}" \
  --argjson total_nodes "${TOTAL_NODES}" \
  --argjson ready_nodes "${READY_NODES}" \
  --argjson not_ready_nodes "${NOT_READY_NODES}" \
  --argjson pending_pods "${PENDING_PODS}" \
  --argjson crashloop_pods "${CRASHLOOP_PODS}" \
  --argjson failed_pods "${FAILED_PODS}" \
  --argjson image_pull_errors "${IMAGE_PULL_ERRORS}" \
  --argjson pending_pvcs "${PENDING_PVCS}" \
  --argjson degraded_deployments "${DEGRADED_DEPLOYMENTS}" \
  --argjson degraded_statefulsets "${DEGRADED_STATEFULSETS}" \
  --argjson degraded_daemonsets "${DEGRADED_DAEMONSETS}" \
  --argjson broken_apiservices "${BROKEN_APISERVICES}" \
  --argjson ingress_without_address "${INGRESS_WITHOUT_ADDRESS}" \
  --argjson memory_pressure "${MEMORY_PRESSURE}" \
  --argjson disk_pressure "${DISK_PRESSURE}" \
  --argjson pid_pressure "${PID_PRESSURE}" \
  --argjson metrics_server "${METRICS_SERVER}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"
report_item "Health" "${HEALTH}"

echo

log_step "Nodes"
report_item "Total" "${TOTAL_NODES}"
report_item "Ready" "${READY_NODES}"
report_item "Not Ready" "${NOT_READY_NODES}"
report_item "Memory Pressure" "${MEMORY_PRESSURE}"
report_item "Disk Pressure" "${DISK_PRESSURE}"
report_item "PID Pressure" "${PID_PRESSURE}"

echo

log_step "Workloads"
report_item "Total Pods" "${TOTAL_PODS}"
report_item "Pending Pods" "${PENDING_PODS}"
report_item "Failed Pods" "${FAILED_PODS}"
report_item "CrashLoopBackOff" "${CRASHLOOP_PODS}"
report_item "ImagePull Errors" "${IMAGE_PULL_ERRORS}"
report_item "Degraded Deployments" "${DEGRADED_DEPLOYMENTS}"
report_item "Degraded StatefulSets" "${DEGRADED_STATEFULSETS}"
report_item "Degraded DaemonSets" "${DEGRADED_DAEMONSETS}"

echo

log_step "Storage & Network"
report_item "Pending PVCs" "${PENDING_PVCS}"
report_item "Ingress Without Address" "${INGRESS_WITHOUT_ADDRESS}"

echo

log_step "API & Observability"
report_item "Broken APIServices" "${BROKEN_APISERVICES}"
report_item "Metrics Server" "${METRICS_SERVER}"

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
