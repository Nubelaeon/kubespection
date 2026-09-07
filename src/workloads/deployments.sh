#!/usr/bin/env bash

########################################
# deployments.sh
#
# Lists all Deployments with details:
# replicas (desired/ready/available),
# strategy, container images, resource
# requests/limits, and conditions.
#
# Supports --namespace and --file args.
# Without args, scans all namespaces.
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

OUTPUT_DIR="${OUTPUT_DIR:-output/workloads}"
OUTPUT_FILE="${OUTPUT_DIR}/deployments.json"

ensure_directory "${OUTPUT_DIR}"

START_TIME="$(timer_start)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

########################################
# PRECHECK
########################################

validate_cluster_access

########################################
# ARGUMENTS
########################################

NAMESPACES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACES+=("$2")
      shift 2
      ;;
    --file)
      while read -r ns; do
        [[ -z "$ns" ]] && continue
        NAMESPACES+=("$ns")
      done < "$2"
      shift 2
      ;;
    *)
      echo "invalid argument: $1"
      exit 1
      ;;
  esac
done

# Default: all namespaces
if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
  mapfile -t NAMESPACES < <(kubectl get ns --no-headers -o custom-columns=":metadata.name")
fi

########################################
# HEADER
########################################

print_header "Deployments Audit"

log_info "Inspecting deployments across ${#NAMESPACES[@]} namespace(s)"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

inspect_deployments() {
  local ns="$1"

  k_namespace_deployments "${ns}" \
  | jq_transform --arg ns "${ns}" '
    [
      .items[] | {
        namespace: $ns,
        name: .metadata.name,
        replicas: {
          desired: (.spec.replicas // 0),
          ready: (.status.readyReplicas // 0),
          available: (.status.availableReplicas // 0),
          unavailable: (.status.unavailableReplicas // 0)
        },
        strategy: (.spec.strategy.type // "RollingUpdate"),
        creation_timestamp: .metadata.creationTimestamp,
        containers: [
          .spec.template.spec.containers[] | {
            name: .name,
            image: .image,
            requests: {
              cpu: (.resources.requests.cpu // null),
              memory: (.resources.requests.memory // null)
            },
            limits: {
              cpu: (.resources.limits.cpu // null),
              memory: (.resources.limits.memory // null)
            }
          }
        ],
        conditions: [
          (.status.conditions // [])[] | {
            type: .type,
            status: .status,
            reason: (.reason // null)
          }
        ],
        labels: (.metadata.labels // {}),
        match_labels: (.spec.selector.matchLabels // {})
      }
    ]
  '
}

# Aggregate results across namespaces
ALL_DEPLOYMENTS="[]"

for ns in "${NAMESPACES[@]}"; do
  log_info "inspecting deployments: ${ns}"

  NS_DEPLOYMENTS="$(inspect_deployments "${ns}")"

  # Skip empty results
  if [[ "$(echo "${NS_DEPLOYMENTS}" | jq_count)" -eq 0 ]]; then
    continue
  fi

  ALL_DEPLOYMENTS="$(jq_merge_arrays "${ALL_DEPLOYMENTS}" "${NS_DEPLOYMENTS}")"
done

########################################
# SUMMARY CALCULATIONS
########################################

TOTAL="$(echo "${ALL_DEPLOYMENTS}" | jq_count)"

HEALTHY="$(
  echo "${ALL_DEPLOYMENTS}" | jq_filter_count \
    '.replicas.desired > 0 and .replicas.ready == .replicas.desired'
)"

DEGRADED="$(
  echo "${ALL_DEPLOYMENTS}" | jq_filter_count \
    '.replicas.desired > 0 and .replicas.ready > 0 and .replicas.ready < .replicas.desired'
)"

UNAVAILABLE="$(
  echo "${ALL_DEPLOYMENTS}" | jq_filter_count \
    '.replicas.desired > 0 and .replicas.ready == 0'
)"

ZERO_REPLICAS="$(
  echo "${ALL_DEPLOYMENTS}" | jq_filter_count \
    '.replicas.desired == 0'
)"

NO_REQUESTS="$(
  echo "${ALL_DEPLOYMENTS}" | jq_filter_count \
    'any(.containers[]; .requests.cpu == null or .requests.memory == null)'
)"

NO_LIMITS="$(
  echo "${ALL_DEPLOYMENTS}" | jq_filter_count \
    'any(.containers[]; .limits.cpu == null or .limits.memory == null)'
)"

########################################
# JSON REPORT
########################################

# Write deployments to temp file to avoid "Argument list too long"
readonly TMP_DEPLOYS="$(mktemp)"
trap 'rm -f "${TMP_DEPLOYS}"' EXIT

echo "${ALL_DEPLOYMENTS}" > "${TMP_DEPLOYS}"

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,
  summary: {
    total: $total,
    healthy: $healthy,
    degraded: $degraded,
    unavailable: $unavailable,
    zero_replicas: $zero_replicas,
    missing_resource_requests: $no_requests,
    missing_resource_limits: $no_limits
  },
  deployments: $deployments[0]
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total "${TOTAL}" \
  --argjson healthy "${HEALTHY}" \
  --argjson degraded "${DEGRADED}" \
  --argjson unavailable "${UNAVAILABLE}" \
  --argjson zero_replicas "${ZERO_REPLICAS}" \
  --argjson no_requests "${NO_REQUESTS}" \
  --argjson no_limits "${NO_LIMITS}" \
  --slurpfile deployments "${TMP_DEPLOYS}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"
report_item "Total Deployments" "${TOTAL}"
report_item "Healthy" "${HEALTHY}"
report_item "Degraded" "${DEGRADED}"
report_item "Unavailable" "${UNAVAILABLE}"
report_item "Zero Replicas" "${ZERO_REPLICAS}"
report_item "Missing Requests" "${NO_REQUESTS}"
report_item "Missing Limits" "${NO_LIMITS}"

echo

# Show degraded/unavailable deployments
if [[ "${DEGRADED}" -gt 0 ]] || [[ "${UNAVAILABLE}" -gt 0 ]]; then
  log_warn "Deployments with Issues:"
  echo

  printf "  %-40s %-20s %-10s %-10s\n" \
    "NAME" "NAMESPACE" "READY" "DESIRED"
  printf "  %-40s %-20s %-10s %-10s\n" \
    "----" "---------" "-----" "-------"

  echo "${ALL_DEPLOYMENTS}" | jq_to_tsv '
    select(.replicas.desired > 0 and .replicas.ready < .replicas.desired)
    | [.name, .namespace, (.replicas.ready | tostring), (.replicas.desired | tostring)]
  ' | while IFS=$'\t' read -r name namespace ready desired; do
    printf "  %-40s %-20s %-10s %-10s\n" \
      "${name}" "${namespace}" "${ready}" "${desired}"
  done

  echo
fi

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
