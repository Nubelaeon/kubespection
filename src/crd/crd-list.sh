#!/usr/bin/env bash

########################################
# crd-list.sh
#
# Inventories all CustomResourceDefinitions
# installed in the cluster, grouping them by
# API group and reporting scope (Namespaced /
# Cluster) and served versions.
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

OUTPUT_DIR="${OUTPUT_DIR:-output/crd}"
OUTPUT_FILE="${OUTPUT_DIR}/crd-list.json"

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

print_header "CRD Inventory"

log_info "Collecting CustomResourceDefinitions"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

CRDS_JSON="$(k_crds)"

TOTAL_CRDS="$(echo "${CRDS_JSON}" | jq_items_count)"

NAMESPACED_CRDS="$(
  echo "${CRDS_JSON}" | jq_items_filter_count '.spec.scope=="Namespaced"'
)"

CLUSTER_CRDS="$(
  echo "${CRDS_JSON}" | jq_items_filter_count '.spec.scope=="Cluster"'
)"

# Distinct API groups that own the installed CRDs.
TOTAL_GROUPS="$(
  echo "${CRDS_JSON}" | jq '[.items[].spec.group] | unique | length'
)"

########################################
# JSON REPORT
########################################

# Build a normalized per-CRD list plus a group histogram.
CRD_ITEMS="$(
  echo "${CRDS_JSON}" | jq '
    [
      .items[]
      | {
          name: .metadata.name,
          group: .spec.group,
          kind: .spec.names.kind,
          plural: .spec.names.plural,
          scope: .spec.scope,
          versions: [.spec.versions[]?.name]
        }
    ]
    | sort_by(.name)
  '
)"

GROUP_HISTOGRAM="$(
  echo "${CRDS_JSON}" | jq '
    [.items[].spec.group]
    | group_by(.)
    | map({ group: .[0], count: length })
    | sort_by(-.count)
  '
)"

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,
  summary: {
    total: $total,
    namespaced: $namespaced,
    cluster: $cluster,
    api_groups: $groups
  },
  by_group: $histogram,
  crds: $items
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total "${TOTAL_CRDS}" \
  --argjson namespaced "${NAMESPACED_CRDS}" \
  --argjson cluster "${CLUSTER_CRDS}" \
  --argjson groups "${TOTAL_GROUPS}" \
  --argjson histogram "${GROUP_HISTOGRAM}" \
  --argjson items "${CRD_ITEMS}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"

echo

log_step "Summary"
report_item "Total CRDs" "${TOTAL_CRDS}"
report_item "Namespaced" "${NAMESPACED_CRDS}"
report_item "Cluster-Scoped" "${CLUSTER_CRDS}"
report_item "API Groups" "${TOTAL_GROUPS}"

echo

log_step "Top API Groups"
printf "%-8s %s\n" "COUNT" "GROUP"
echo "${GROUP_HISTOGRAM}" \
  | jq -r '.[] | "\(.count)\t\(.group)"' \
  | head -n 10 \
  | tr -d '\r' \
  | while IFS="$(printf '\t')" read -r count group; do
      printf "%-8s %s\n" "${count}" "${group}"
    done

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
