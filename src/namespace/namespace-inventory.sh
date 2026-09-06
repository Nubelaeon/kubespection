#!/usr/bin/env bash

set -Eeuo pipefail

########################################
# CONFIG
########################################

OUTPUT_DIR="${OUTPUT_DIR:-output/namespaces}"

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

if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo "usage:"
    echo "  $0 --namespace namespace"
    echo "  $0 --file conf/namespaces.txt"
    exit 1
fi

########################################
# INVENTORY
########################################

inventory_namespace() {

    local ns="$1"

    echo "[INFO] inventory namespace: ${ns}"

    kubectl get namespace "${ns}" >/dev/null

    PODS_JSON="$(kubectl get pods -n "${ns}" -o json 2>/dev/null || echo '{"items":[]}')"

    PODS_COUNT="$(echo "${PODS_JSON}" | jq '.items | length')"

    DEPLOYMENTS_COUNT="$(
        kubectl get deploy -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    STATEFULSETS_COUNT="$(
        kubectl get sts -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    DAEMONSETS_COUNT="$(
        kubectl get ds -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    JOBS_COUNT="$(
        kubectl get jobs -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    CRONJOBS_COUNT="$(
        kubectl get cronjobs -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    REPLICASETS_COUNT="$(
        kubectl get rs -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    SERVICES_COUNT="$(
        kubectl get svc -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    INGRESS_COUNT="$(
        kubectl get ingress -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    PVC_COUNT="$(
        kubectl get pvc -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    CONFIGMAP_COUNT="$(
        kubectl get configmap -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    SECRET_COUNT="$(
        kubectl get secret -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

    SA_COUNT="$(
        kubectl get sa -n "${ns}" --no-headers 2>/dev/null \
        | wc -l | tr -d ' '
    )"

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
        kubectl get pvc \
            -n "${ns}" \
            -o json \
            2>/dev/null \
        | jq '
            [
              .items[]
              | .status.capacity.storage?
            ]
        '
    )"

    OUTPUT_FILE="${OUTPUT_DIR}/${ns}.json"

    jq -n \
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
        --argjson custom_resources "${CUSTOM_RESOURCES}" \
'
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
' > "${OUTPUT_FILE}"

    echo "  -> ${OUTPUT_FILE}"
}

########################################
# EXECUTION
########################################

for ns in "${NAMESPACES[@]}"; do
    inventory_namespace "${ns}"
done
