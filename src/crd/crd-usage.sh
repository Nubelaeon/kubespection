#!/usr/bin/env bash

########################################
# crd-usage.sh
#
# Counts live instances of every installed
# CustomResourceDefinition across all
# namespaces, ranking CRDs by usage. Useful
# for capacity planning and spotting heavily
# vs. lightly used extensions.
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
OUTPUT_FILE="${OUTPUT_DIR}/crd-usage.json"

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

print_header "CRD Usage"

log_info "Counting instances per CustomResourceDefinition"

########################################
# DATA COLLECTION
########################################

CURRENT_CONTEXT="$(k_context)"

TOTAL_CRDS="$(k_crd_count)"

# Accumulate one JSON object per CRD with its live instance count.
# k_crd_specs emits: fullname<TAB>group<TAB>plural<TAB>scope<TAB>kind
USAGE_ROWS=""

while IFS="$(printf '\t')" read -r fullname group plural scope kind; do

  [[ -n "${fullname}" ]] || continue

  instances="$(k_crd_instance_count "${fullname}")"

  row="$(
    jq -n \
      --arg name "${fullname}" \
      --arg group "${group}" \
      --arg kind "${kind}" \
      --arg scope "${scope}" \
      --argjson count "${instances}" \
      '{ name: $name, group: $group, kind: $kind, scope: $scope, instances: $count }'
  )"

  USAGE_ROWS="${USAGE_ROWS}${row}"$'\n'

done < <(k_crd_specs)

# Slurp all rows into a single array sorted by instance count (desc).
USAGE_JSON="$(
  echo "${USAGE_ROWS}" | jq -s 'sort_by(-.instances)'
)"

TOTAL_INSTANCES="$(
  echo "${USAGE_JSON}" | jq '[.[].instances] | add // 0'
)"

USED_CRDS="$(
  echo "${USAGE_JSON}" | jq '[.[] | select(.instances > 0)] | length'
)"

UNUSED_CRDS="$(
  echo "${USAGE_JSON}" | jq '[.[] | select(.instances == 0)] | length'
)"

########################################
# JSON REPORT
########################################

jq_build_report "${OUTPUT_FILE}" '
{
  timestamp: $timestamp,
  context: $context,
  summary: {
    total_crds: $total,
    used: $used,
    unused: $unused,
    total_instances: $instances
  },
  usage: $usage
}
' \
  --arg timestamp "${TIMESTAMP}" \
  --arg context "${CURRENT_CONTEXT}" \
  --argjson total "${TOTAL_CRDS}" \
  --argjson used "${USED_CRDS}" \
  --argjson unused "${UNUSED_CRDS}" \
  --argjson instances "${TOTAL_INSTANCES}" \
  --argjson usage "${USAGE_JSON}"

########################################
# HUMAN REPORT
########################################

report_item "Context" "${CURRENT_CONTEXT}"

echo

log_step "Summary"
report_item "Total CRDs" "${TOTAL_CRDS}"
report_item "Used (>=1 instance)" "${USED_CRDS}"
report_item "Unused (0 instances)" "${UNUSED_CRDS}"
report_item "Total Instances" "${TOTAL_INSTANCES}"

echo

log_step "Top CRDs by Instance Count"
printf "%-10s %s\n" "COUNT" "CRD"
echo "${USAGE_JSON}" \
  | jq -r '.[] | select(.instances > 0) | "\(.instances)\t\(.name)"' \
  | head -n 15 \
  | tr -d '\r' \
  | while IFS="$(printf '\t')" read -r count name; do
      printf "%-10s %s\n" "${count}" "${name}"
    done

echo

report_file "${OUTPUT_FILE}"

report_duration "$(timer_end "${START_TIME}")"

print_footer
