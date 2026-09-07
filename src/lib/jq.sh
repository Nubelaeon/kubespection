#!/usr/bin/env bash

#
# lib/jq.sh
#
# Centralized jq helper functions for JSON
# processing and transformation.
#
# Provides reusable wrappers for common jq
# patterns used across kubespection scripts.
#

########################################
# COUNT
########################################

# Count elements in a JSON array from stdin
# Usage: echo "$json_array" | jq_count
jq_count() {
  jq 'length'
}

# Count .items from kubectl JSON output (stdin)
# Usage: echo "$kubectl_json" | jq_items_count
jq_items_count() {
  jq '.items | length'
}

########################################
# FILTER + COUNT
########################################

# Filter array elements by a jq expression and count results
# Usage: echo "$json_array" | jq_filter_count '.replicas.desired > 0'
jq_filter_count() {
  local filter_expr="$1"

  jq "[.[] | select(${filter_expr})] | length"
}

# Filter .items[] from kubectl JSON by a jq expression and count results
# Usage: echo "$kubectl_json" | jq_items_filter_count '.status.phase=="Pending"'
jq_items_filter_count() {
  local filter_expr="$1"

  jq "[.items[] | select(${filter_expr})] | length"
}

########################################
# AGGREGATION
########################################

# Sum a numeric expression across .items[] from kubectl JSON
# Usage: echo "$kubectl_json" | jq_items_sum '.status.capacity.cpu | tonumber'
jq_items_sum() {
  local expr="$1"

  jq "[.items[] | ${expr}] | add"
}

########################################
# MERGE
########################################

# Merge two JSON arrays into one
# Usage: jq_merge_arrays "$array1" "$array2"
jq_merge_arrays() {
  local array1="$1"
  local array2="$2"

  echo "${array1}" "${array2}" | jq -s '.[0] + .[1]'
}

########################################
# EXTRACT
########################################

# Extract a single field value (raw output)
# Usage: echo "$json" | jq_extract '.serverVersion.gitVersion'
jq_extract() {
  local path="$1"

  jq -r "${path}"
}

# Extract an array of names from .items[].metadata.name
# Usage: echo "$kubectl_json" | jq_extract_names
jq_extract_names() {
  jq '[.items[].metadata.name]'
}

########################################
# TSV OUTPUT
########################################

# Convert JSON array to TSV using a jq field expression
# Usage: echo "$json_array" | jq_to_tsv '[.name, .namespace, .status]'
jq_to_tsv() {
  local fields="$1"

  jq -r ".[] | ${fields} | @tsv"
}

########################################
# REPORT BUILDING
########################################

# Write a JSON report to file using jq -n with
# dynamically constructed arguments.
#
# Usage:
#   jq_build_report output_file jq_expression \
#     --arg key val \
#     --argjson key val \
#     --slurpfile key file
#
jq_build_report() {
  local output_file="$1"
  local expression="$2"
  shift 2

  jq -n "$@" "${expression}" > "${output_file}"
}

########################################
# TRANSFORM
########################################

# Apply a jq transformation to stdin and return result
# Supports extra jq flags before the expression.
# Usage: echo "$json" | jq_transform '.items[] | .metadata.name'
# Usage: echo "$json" | jq_transform --arg ns "$ns" '.items[]'
jq_transform() {
  jq "$@"
}

# Apply a jq transformation with raw output
# Supports extra jq flags before the expression.
# Usage: echo "$json" | jq_transform_raw '.field'
# Usage: echo "$json" | jq_transform_raw --arg k v '.[$k]'
jq_transform_raw() {
  jq -r "$@"
}
