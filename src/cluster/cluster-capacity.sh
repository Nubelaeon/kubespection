#!/usr/bin/env bash

########################################
# cluster-capacity.sh
#
# Collects total cluster capacity and
# allocatable resources: CPU, memory,
# and pod limits per node.
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
OUTPUT_FILE="${OUTPUT_DIR}/cluster-capacity.json"

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

print_header "Cluster Capacity"

log_info "Collecting cluster capacity data"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"
NODES_JSON="$(k_nodes)"

TOTAL_NODES="$(echo "${NODES_JSON}" | jq_items_count)"

READY_NODES="$(
  echo "${NODES_JSON}" | jq_items_filter_count '
    any(.status.conditions[]; .type=="Ready" and .status=="True")
  '
)"

########################################
# CPU
########################################

CPU_CAPACITY="$(
  echo "${NODES_JSON}" | jq_items_sum '
    .status.capacity.cpu
    | if endswith("m") then
        (sub("m$";"") | tonumber) / 1000
      else
        tonumber
      end
  '
)"

CPU_ALLOCATABLE="$(
  echo "${NODES_JSON}" | jq_items_sum '
    .status.allocatable.cpu
    | if endswith("m") then
        (sub("m$";"") | tonumber) / 1000
      else
        tonumber
      end
  '
)"

########################################
# MEMORY
########################################

MEMORY_CAPACITY_KIB="$(
  echo "${NODES_JSON}" | jq_items_sum '
    .status.capacity.memory | sub("Ki$"; "") | tonumber
  '
)"

MEMORY_ALLOCATABLE_KIB="$(
  echo "${NODES_JSON}" | jq_items_sum '
    .status.allocatable.memory | sub("Ki$"; "") | tonumber
  '
)"

MEMORY_CAPACITY_GIB="$(
  awk "BEGIN { printf \"%.2f\", ${MEMORY_CAPACITY_KIB}/1024/1024 }"
)"

MEMORY_ALLOCATABLE_GIB="$(
  awk "BEGIN { printf \"%.2f\", ${MEMORY_ALLOCATABLE_KIB}/1024/1024 }"
)"

########################################
# PODS
########################################

PODS_CAPACITY="$(
  echo "${NODES_JSON}" | jq_items_sum '.status.capacity.pods | tonumber'
)"

PODS_ALLOCATABLE="$(
  echo "${NODES_JSON}" | jq_items_sum '.status.allocatable.pods | tonumber'
)"

########################################
# JSON REPORT
########################################

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,

  nodes: {
    total: $total_nodes,
    ready: $ready_nodes,
    not_ready: ($total_nodes - $ready_nodes)
  },

  capacity: {
    cpu_cores: $cpu_capacity,
    memory_gib: ($mem_capacity | tonumber),
    pods: $pods_capacity
  },

  allocatable: {
    cpu_cores: $cpu_allocatable,
    memory_gib: ($mem_allocatable | tonumber),
    pods: $pods_allocatable
  }
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total_nodes "${TOTAL_NODES}" \
  --argjson ready_nodes "${READY_NODES}" \
  --argjson cpu_capacity "${CPU_CAPACITY}" \
  --argjson cpu_allocatable "${CPU_ALLOCATABLE}" \
  --arg mem_capacity "${MEMORY_CAPACITY_GIB}" \
  --arg mem_allocatable "${MEMORY_ALLOCATABLE_GIB}" \
  --argjson pods_capacity "${PODS_CAPACITY}" \
  --argjson pods_allocatable "${PODS_ALLOCATABLE}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"

echo

log_step "Nodes"
report_item "Total" "${TOTAL_NODES}"
report_item "Ready" "${READY_NODES}"
report_item "Not Ready" "$((TOTAL_NODES - READY_NODES))"

echo

log_step "CPU"
report_item "Capacity" "${CPU_CAPACITY} cores"
report_item "Allocatable" "${CPU_ALLOCATABLE} cores"

echo

log_step "Memory"
report_item "Capacity" "${MEMORY_CAPACITY_GIB} GiB"
report_item "Allocatable" "${MEMORY_ALLOCATABLE_GIB} GiB"

echo

log_step "Pods"
report_item "Capacity" "${PODS_CAPACITY}"
report_item "Allocatable" "${PODS_ALLOCATABLE}"

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
