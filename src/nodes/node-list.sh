#!/usr/bin/env bash

########################################
# node-list.sh
#
# Lists all cluster nodes with details:
# roles, status, capacity, allocatable
# resources, kernel version, container
# runtime, and OS image.
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

OUTPUT_DIR="${OUTPUT_DIR:-output/nodes}"
OUTPUT_FILE="${OUTPUT_DIR}/node-list.json"

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

print_header "Node List"

log_info "Collecting node information"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

# Fetch all nodes in a single API call
NODES_JSON="$(k_nodes)"

# Build structured node list via jq
NODE_LIST="$(
  echo "${NODES_JSON}" | jq_transform '
    [
      .items[] | {
        name: .metadata.name,
        roles: (
          [
            .metadata.labels
            | to_entries[]
            | select(.key | startswith("node-role.kubernetes.io/"))
            | .key
            | ltrimstr("node-role.kubernetes.io/")
          ]
          | if length == 0 then ["<none>"] else . end
        ),
        status: (
          [
            .status.conditions[]
            | select(.type == "Ready")
          ][0].status
          | if . == "True" then "Ready" else "NotReady" end
        ),
        unschedulable: (.spec.unschedulable // false),
        creation_timestamp: .metadata.creationTimestamp,
        kubelet_version: .status.nodeInfo.kubeletVersion,
        container_runtime: .status.nodeInfo.containerRuntimeVersion,
        os_image: .status.nodeInfo.osImage,
        architecture: .status.nodeInfo.architecture,
        kernel_version: .status.nodeInfo.kernelVersion,
        capacity: {
          cpu: .status.capacity.cpu,
          memory: .status.capacity.memory,
          pods: .status.capacity.pods,
          ephemeral_storage: .status.capacity["ephemeral-storage"]
        },
        allocatable: {
          cpu: .status.allocatable.cpu,
          memory: .status.allocatable.memory,
          pods: .status.allocatable.pods,
          ephemeral_storage: .status.allocatable["ephemeral-storage"]
        },
        labels: (.metadata.labels // {}),
        taints: (.spec.taints // [])
      }
    ]
  '
)"

TOTAL_NODES="$(echo "${NODE_LIST}" | jq_count)"

READY_NODES="$(
  echo "${NODE_LIST}" | jq_filter_count '.status == "Ready"'
)"

NOT_READY_NODES="$(
  echo "${NODE_LIST}" | jq_filter_count '.status == "NotReady"'
)"

UNSCHEDULABLE_NODES="$(
  echo "${NODE_LIST}" | jq_filter_count '.unschedulable == true'
)"

########################################
# JSON REPORT
########################################

# Write node list to temp file to avoid "Argument list too long"
readonly TMP_NODES="$(mktemp)"
trap 'rm -f "${TMP_NODES}"' EXIT

echo "${NODE_LIST}" > "${TMP_NODES}"

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,
  summary: {
    total: $total,
    ready: $ready,
    not_ready: $not_ready,
    unschedulable: $unschedulable
  },
  nodes: $nodes[0]
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total "${TOTAL_NODES}" \
  --argjson ready "${READY_NODES}" \
  --argjson not_ready "${NOT_READY_NODES}" \
  --argjson unschedulable "${UNSCHEDULABLE_NODES}" \
  --slurpfile nodes "${TMP_NODES}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"
report_item "Total Nodes" "${TOTAL_NODES}"
report_item "Ready" "${READY_NODES}"
report_item "NotReady" "${NOT_READY_NODES}"
report_item "Unschedulable" "${UNSCHEDULABLE_NODES}"

echo

# Table header
printf "%-40s %-12s %-14s %-10s %-20s\n" \
  "NAME" "STATUS" "ROLES" "VERSION" "OS IMAGE"
printf "%-40s %-12s %-14s %-10s %-20s\n" \
  "----" "------" "-----" "-------" "--------"

# Table rows via jq_to_tsv
echo "${NODE_LIST}" | jq_to_tsv '
  [
    .name,
    (if .unschedulable then .status + ",Sched" else .status end),
    (.roles | join(",")),
    .kubelet_version,
    .os_image
  ]
' | while IFS=$'\t' read -r name status roles version os_image; do
  printf "%-40s %-12s %-14s %-10s %-20s\n" \
    "${name}" "${status}" "${roles}" "${version}" "${os_image}"
done

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
