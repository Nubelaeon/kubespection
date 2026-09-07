#!/usr/bin/env bash

########################################
# orphaned-crds.sh
#
# Identifies orphaned CustomResourceDefinitions:
# CRDs that are installed but have zero live
# instances across all namespaces. These are
# candidates for cleanup / decommissioning
# (leftover operators, uninstalled charts).
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
OUTPUT_FILE="${OUTPUT_DIR}/orphaned-crds.json"

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

print_header "Orphaned CRDs"

log_info "Detecting CRDs with zero live instances"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

CRDS_JSON="$(k_crds)"

TOTAL_CRDS="$(echo "${CRDS_JSON}" | jq_items_count)"

# Map fullname -> creationTimestamp for enrichment of orphan records.
CREATION_MAP="$(
  echo "${CRDS_JSON}" | jq '
    reduce .items[] as $c ({}; .[$c.metadata.name] = $c.metadata.creationTimestamp)
  '
)"

# Walk every CRD, keep only those with zero live instances.
# k_crd_specs emits: fullname<TAB>group<TAB>plural<TAB>scope<TAB>kind
ORPHAN_ROWS=""

while IFS="$(printf '\t')" read -r fullname group plural scope kind; do

  [[ -n "${fullname}" ]] || continue

  instances="$(k_crd_instance_count "${fullname}")"

  [[ "${instances}" -eq 0 ]] || continue

  created="$(
    echo "${CREATION_MAP}" | jq -r --arg n "${fullname}" '.[$n] // ""'
  )"

  row="$(
    jq -n \
      --arg name "${fullname}" \
      --arg group "${group}" \
      --arg kind "${kind}" \
      --arg scope "${scope}" \
      --arg created "${created}" \
      '{ name: $name, group: $group, kind: $kind, scope: $scope, created: $created }'
  )"

  ORPHAN_ROWS="${ORPHAN_ROWS}${row}"$'\n'

done < <(k_crd_specs)

# Slurp orphan rows into a sorted array (by group then name).
ORPHANS_JSON="$(
  echo "${ORPHAN_ROWS}" | jq -s 'sort_by(.group, .name)'
)"

ORPHAN_COUNT="$(echo "${ORPHANS_JSON}" | jq_count)"

ACTIVE_COUNT=$((TOTAL_CRDS - ORPHAN_COUNT))

########################################
# JSON REPORT
########################################

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,
  summary: {
    total_crds: $total,
    active: $active,
    orphaned: $orphaned
  },
  orphaned_crds: $orphans
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total "${TOTAL_CRDS}" \
  --argjson active "${ACTIVE_COUNT}" \
  --argjson orphaned "${ORPHAN_COUNT}" \
  --argjson orphans "${ORPHANS_JSON}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"

echo

log_step "Summary"
report_item "Total CRDs" "${TOTAL_CRDS}"
report_item "Active (>=1 instance)" "${ACTIVE_COUNT}"
report_item "Orphaned (0 instances)" "${ORPHAN_COUNT}"

echo

if [[ "${ORPHAN_COUNT}" -gt 0 ]]; then
  log_step "Orphaned CRDs (cleanup candidates)"
  printf "%-45s %s\n" "CRD" "GROUP"
  echo "${ORPHANS_JSON}" \
    | jq -r '.[] | "\(.name)\t\(.group)"' \
    | tr -d '\r' \
    | while IFS="$(printf '\t')" read -r name group; do
        printf "%-45s %s\n" "${name}" "${group:-<core>}"
      done
else
  log_success "No orphaned CRDs found"
fi

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
