#!/usr/bin/env bash

#
# lib/validations.sh
#
# Validações compartilhadas do kube-audit-toolkit
#

set -Eeuo pipefail

########################################
# Executable validation
########################################

require() {
    local binary="$1"

    command -v "${binary}" >/dev/null 2>&1 || {
        echo "ERROR: dependency not found: ${binary}" >&2
        return 1
    }
}

require_many() {
    local dependency

    for dependency in "$@"; do
        require "${dependency}"
    done
}

########################################
# File validation
########################################

require_file() {
    local file="$1"

    [[ -f "${file}" ]] || {
        echo "ERROR: file not found: ${file}" >&2
        return 1
    }
}

########################################
# Directory validation
########################################

require_directory() {
    local directory="$1"

    [[ -d "${directory}" ]] || {
        echo "ERROR: directory not found: ${directory}" >&2
        return 1
    }
}

########################################
# Output directory validation
########################################

ensure_directory() {
    local directory="$1"

    mkdir -p "${directory}"
}

########################################
# Kubernetes context validation
########################################

validate_kubeconfig() {
    kubectl config current-context >/dev/null 2>&1 || {
        echo "ERROR: unable to read kubeconfig" >&2
        return 1
    }
}

########################################
# Kubernetes API connectivity
########################################

validate_cluster_connection() {
    kubectl cluster-info >/dev/null 2>&1 || {
        echo "ERROR: unable to connect to Kubernetes API" >&2
        return 1
    }
}

########################################
# Current context validation
########################################

validate_context() {
    local context

    context="$(kubectl config current-context 2>/dev/null || true)"

    [[ -n "${context}" ]] || {
        echo "ERROR: kubernetes context not configured" >&2
        return 1
    }
}

########################################
# Namespace validation
########################################

namespace_exists() {
    local namespace="$1"

    kubectl get namespace "${namespace}" \
        >/dev/null 2>&1
}

validate_namespace() {
    local namespace="$1"

    namespace_exists "${namespace}" || {
        echo "ERROR: namespace not found: ${namespace}" >&2
        return 1
    }
}

########################################
# Node validation
########################################

validate_nodes_exist() {
    local total_nodes

    total_nodes="$(
        kubectl get nodes \
            --no-headers \
            2>/dev/null \
        | wc -l \
        | tr -d ' '
    )"

    [[ "${total_nodes}" -gt 0 ]] || {
        echo "ERROR: no nodes found in cluster" >&2
        return 1
    }
}

########################################
# Metrics Server validation
########################################

metrics_server_available() {
    kubectl top nodes >/dev/null 2>&1
}

########################################
# jq validation
########################################

validate_json() {
    local file="$1"

    jq empty "${file}" >/dev/null 2>&1
}

########################################
# Generic non-empty validation
########################################

require_value() {
    local value="$1"
    local label="$2"

    [[ -n "${value}" ]] || {
        echo "ERROR: ${label} cannot be empty" >&2
        return 1
    }
}

########################################
# Input file validation
########################################

validate_input_file() {
    local file="$1"

    require_file "${file}"

    [[ -s "${file}" ]] || {
        echo "ERROR: input file is empty: ${file}" >&2
        return 1
    }
}

########################################
# Full cluster pre-check
########################################

validate_cluster_access() {

    require_many kubectl jq awk

    validate_kubeconfig
    validate_context
    validate_cluster_connection
    validate_nodes_exist
}

########################################
# Namespace pre-check
########################################

validate_namespace_access() {
    local namespace="$1"

    validate_cluster_access
    validate_namespace "${namespace}"
}

########################################
# Report file validation
########################################

validate_output_path() {
    local path="$1"

    local parent_dir

    parent_dir="$(dirname "${path}")"

    ensure_directory "${parent_dir}"

    [[ -w "${parent_dir}" ]] || {
        echo "ERROR: output directory not writable: ${parent_dir}" >&2
        return 1
    }
}
