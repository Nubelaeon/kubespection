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

readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

########################################
# CONFIG
########################################

OUTPUT_DIR="${OUTPUT_DIR:-output/workloads}"

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
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(kubectl config current-context)"

inspect_deployments() {
  local ns="$1"

  kubectl get deploy -n "${ns}" -o json 2>/dev/null \
  | jq --arg ns "${ns}" '
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
  echo "[INFO] inspecting deployments: ${ns}" >&2

  NS_DEPLOYMENTS="$(inspect_deployments "${ns}")"

  # Skip empty results
  if [[ "$(echo "${NS_DEPLOYMENTS}" | jq 'length')" -eq 0 ]]; then
    continue
  fi

  ALL_DEPLOYMENTS="$(
    echo "${ALL_DEPLOYMENTS}" "${NS_DEPLOYMENTS}" \
    | jq -s '.[0] + .[1]'
  )"
done

########################################
# SUMMARY CALCULATIONS
########################################

TOTAL="$(echo "${ALL_DEPLOYMENTS}" | jq 'length')"

HEALTHY="$(
  echo "${ALL_DEPLOYMENTS}" | jq '
    [.[] | select(.replicas.desired > 0 and .replicas.ready == .replicas.desired)]
    | length
  '
)"

DEGRADED="$(
  echo "${ALL_DEPLOYMENTS}" | jq '
    [.[] | select(.replicas.desired > 0 and .replicas.ready > 0 and .replicas.ready < .replicas.desired)]
    | length
  '
)"

UNAVAILABLE="$(
  echo "${ALL_DEPLOYMENTS}" | jq '
    [.[] | select(.replicas.desired > 0 and .replicas.ready == 0)]
    | length
  '
)"

ZERO_REPLICAS="$(
  echo "${ALL_DEPLOYMENTS}" | jq '
    [.[] | select(.replicas.desired == 0)]
    | length
  '
)"

NO_REQUESTS="$(
  echo "${ALL_DEPLOYMENTS}" | jq '
    [.[] | select(
      any(.containers[]; .requests.cpu == null or .requests.memory == null)
    )]
    | length
  '
)"

NO_LIMITS="$(
  echo "${ALL_DEPLOYMENTS}" | jq '
    [.[] | select(
      any(.containers[]; .limits.cpu == null or .limits.memory == null)
    )]
    | length
  '
)"

########################################
# JSON OUTPUT
########################################

OUTPUT_FILE="${OUTPUT_DIR}/deployments.json"

# Write deployments to temp file to avoid "Argument list too long"
readonly TMP_DEPLOYS="$(mktemp)"
trap 'rm -f "${TMP_DEPLOYS}"' EXIT

echo "${ALL_DEPLOYMENTS}" > "${TMP_DEPLOYS}"

jq -n \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total "${TOTAL}" \
  --argjson healthy "${HEALTHY}" \
  --argjson degraded "${DEGRADED}" \
  --argjson unavailable "${UNAVAILABLE}" \
  --argjson zero_replicas "${ZERO_REPLICAS}" \
  --argjson no_requests "${NO_REQUESTS}" \
  --argjson no_limits "${NO_LIMITS}" \
  --slurpfile deployments "${TMP_DEPLOYS}" \
'
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
' > "${OUTPUT_FILE}"

########################################
# STDOUT SUMMARY
########################################

echo
echo "Deployments Audit"
echo "================="
echo "Context.............: ${CURRENT_CONTEXT}"
echo "Total Deployments...: ${TOTAL}"
echo "Healthy.............: ${HEALTHY}"
echo "Degraded............: ${DEGRADED}"
echo "Unavailable.........: ${UNAVAILABLE}"
echo "Zero Replicas.......: ${ZERO_REPLICAS}"
echo "Missing Requests....: ${NO_REQUESTS}"
echo "Missing Limits......: ${NO_LIMITS}"
echo

# Show degraded/unavailable deployments
if [[ "${DEGRADED}" -gt 0 ]] || [[ "${UNAVAILABLE}" -gt 0 ]]; then
  echo "⚠ Deployments with Issues:"
  echo

  printf "  %-40s %-20s %-10s %-10s\n" \
    "NAME" "NAMESPACE" "READY" "DESIRED"
  printf "  %-40s %-20s %-10s %-10s\n" \
    "----" "---------" "-----" "-------"

  echo "${ALL_DEPLOYMENTS}" | jq -r '
    .[]
    | select(.replicas.desired > 0 and .replicas.ready < .replicas.desired)
    | [.name, .namespace, (.replicas.ready | tostring), (.replicas.desired | tostring)]
    | @tsv
  ' | while IFS=$'\t' read -r name namespace ready desired; do
    printf "  %-40s %-20s %-10s %-10s\n" \
      "${name}" "${namespace}" "${ready}" "${desired}"
  done

  echo
fi

echo "JSON report: ${OUTPUT_FILE}"
