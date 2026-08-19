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

readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

########################################
# CONFIG
########################################

OUTPUT_DIR="${OUTPUT_DIR:-output/nodes}"
OUTPUT_FILE="${OUTPUT_DIR}/node-list.json"

mkdir -p "${OUTPUT_DIR}"

########################################
# VALIDATION
########################################

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing dependency: $1"
    exit 1
  }
}

require kubectl
require jq

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(kubectl config current-context)"

# Fetch all nodes in a single API call
NODES_JSON="$(kubectl get nodes -o json)"

# Build structured node list via jq
NODE_LIST="$(
  echo "${NODES_JSON}" | jq '
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

TOTAL_NODES="$(echo "${NODE_LIST}" | jq 'length')"

READY_NODES="$(
  echo "${NODE_LIST}" | jq '[.[] | select(.status == "Ready")] | length'
)"

NOT_READY_NODES="$(
  echo "${NODE_LIST}" | jq '[.[] | select(.status == "NotReady")] | length'
)"

UNSCHEDULABLE_NODES="$(
  echo "${NODE_LIST}" | jq '[.[] | select(.unschedulable == true)] | length'
)"

########################################
# JSON OUTPUT
########################################

# Write node list to temp file to avoid "Argument list too long"
readonly TMP_NODES="$(mktemp)"
trap 'rm -f "${TMP_NODES}"' EXIT

echo "${NODE_LIST}" > "${TMP_NODES}"

jq -n \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total "${TOTAL_NODES}" \
  --argjson ready "${READY_NODES}" \
  --argjson not_ready "${NOT_READY_NODES}" \
  --argjson unschedulable "${UNSCHEDULABLE_NODES}" \
  --slurpfile nodes "${TMP_NODES}" \
'
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
' > "${OUTPUT_FILE}"

########################################
# STDOUT SUMMARY
########################################

echo
echo "Node List"
echo "========="
echo "Context.............: ${CURRENT_CONTEXT}"
echo "Total Nodes.........: ${TOTAL_NODES}"
echo "Ready...............: ${READY_NODES}"
echo "NotReady............: ${NOT_READY_NODES}"
echo "Unschedulable.......: ${UNSCHEDULABLE_NODES}"
echo

# Table header
printf "%-40s %-12s %-14s %-10s %-20s\n" \
  "NAME" "STATUS" "ROLES" "VERSION" "OS IMAGE"
printf "%-40s %-12s %-14s %-10s %-20s\n" \
  "----" "------" "-----" "-------" "--------"

# Table rows
echo "${NODE_LIST}" | jq -r '
  .[] |
  [
    .name,
    (if .unschedulable then .status + ",Sched" else .status end),
    (.roles | join(",")),
    .kubelet_version,
    .os_image
  ] | @tsv
' | while IFS=$'\t' read -r name status roles version os_image; do
  printf "%-40s %-12s %-14s %-10s %-20s\n" \
    "${name}" "${status}" "${roles}" "${version}" "${os_image}"
done

echo
echo "JSON report: ${OUTPUT_FILE}"
