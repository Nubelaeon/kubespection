#!/usr/bin/env bash

########################################
# namespace-inventory.sh
#
# Generates a full resource inventory for
# one or more namespaces.
#
# Supports --namespace and --file args.
#
# Output: JSON file per namespace
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

OUTPUT_DIR="${OUTPUT_DIR:-output/namespaces}"

ensure_directory "${OUTPUT_DIR}"

START_TIME="$(timer_start)"

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

if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
  echo "usage:"
  echo "  $0 --namespace namespace"
  echo "  $0 --file conf/namespaces.txt"
  exit 1
fi

########################################
# HEADER
########################################

print_header "Namespace Inventory"

log_info "Inventorying ${#NAMESPACES[@]} namespace(s)"

########################################
# INVENTORY
########################################

inventory_namespace() {
  local ns="$1"

  log_info "inventory namespace: ${ns}"

  validate_namespace "${ns}"

  PODS_JSON="$(k_namespace_pods "${ns}")"
  PODS_COUNT="$(echo "${PODS_JSON}" | jq_items_count)"

  DEPLOYMENTS_COUNT="$(k_count_namespace "${ns}" deploy)"
  STATEFULSETS_COUNT="$(k_count_namespace "${ns}" sts)"
  DAEMONSETS_COUNT="$(k_count_namespace "${ns}" ds)"
  JOBS_COUNT="$(k_count_namespace "${ns}" jobs)"
  CRONJOBS_COUNT="$(k_count_namespace "${ns}" cronjobs)"
  REPLICASETS_COUNT="$(k_count_namespace "${ns}" rs)"
  SERVICES_COUNT="$(k_count_namespace "${ns}" svc)"
  INGRESS_COUNT="$(k_count_namespace "${ns}" ingress)"
  PVC_COUNT="$(k_count_namespace "${ns}" pvc)"
  CONFIGMAP_COUNT="$(k_count_namespace "${ns}" configmap)"
  SECRET_COUNT="$(k_count_namespace "${ns}" secret)"
  SA_COUNT="$(k_count_namespace "${ns}" sa)"

  ####################################
  # CRDs PRESENTES NO NAMESPACE
  ####################################

  CUSTOM_RESOURCES="$(
    kubectl api-resources \
      --verbs=list \
      --namespaced \
      -o name \
    | while read -r resource; do

      count="$(
        kubectl get "${resource}" \
          -n "${ns}" \
          --ignore-not-found \
          --no-headers 2>/dev/null \
        | wc -l
      )"

      if [[ "${count}" -gt 0 ]]; then
        echo "${resource}"
      fi

    done \
    | jq -R . \
    | jq -s .
  )"

  ####################################
  # PVC CAPACITY
  ####################################

  PVC_CAPACITY="$(
    k_namespace_pvcs "${ns}" | jq_transform '
      [.items[] | .status.capacity.storage?]
    '
  )"

  ####################################
  # JSON OUTPUT
  ####################################

  local output_file="${OUTPUT_DIR}/${ns}.json"

  jq_build_report "${output_file}" '
{
  namespace: $namespace,
  workloads: {
    pods: $pods,
    deployments: $deployments,
    statefulsets: $statefulsets,
    daemonsets: $daemonsets,
    jobs: $jobs,
    cronjobs: $cronjobs,
    replicasets: $replicasets
  },
  network: {
    services: $services,
    ingresses: $ingresses
  },
  storage: {
    pvcs: $pvcs
  },
  security: {
    serviceaccounts: $serviceaccounts,
    secrets: $secrets
  },
  configuration: {
    configmaps: $configmaps
  },
  custom_resources: $custom_resources
}
' \
    --arg namespace "${ns}" \
    --argjson pods "${PODS_COUNT}" \
    --argjson deployments "${DEPLOYMENTS_COUNT}" \
    --argjson statefulsets "${STATEFULSETS_COUNT}" \
    --argjson daemonsets "${DAEMONSETS_COUNT}" \
    --argjson jobs "${JOBS_COUNT}" \
    --argjson cronjobs "${CRONJOBS_COUNT}" \
    --argjson replicasets "${REPLICASETS_COUNT}" \
    --argjson services "${SERVICES_COUNT}" \
    --argjson ingresses "${INGRESS_COUNT}" \
    --argjson pvcs "${PVC_COUNT}" \
    --argjson configmaps "${CONFIGMAP_COUNT}" \
    --argjson secrets "${SECRET_COUNT}" \
    --argjson serviceaccounts "${SA_COUNT}" \
    --argjson custom_resources "${CUSTOM_RESOURCES}"

  report_file "${output_file}"
}

########################################
# EXECUTION
########################################

for ns in "${NAMESPACES[@]}"; do
  inventory_namespace "${ns}"
done

echo

report_duration "$(timer_end "${START_TIME}")"

print_footer
