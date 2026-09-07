#!/usr/bin/env bash

#
# lib/kubectl.sh
#
# Kubernetes access layer
#

set -Eeuo pipefail

########################################
# CONSTANTS
########################################

readonly EMPTY_JSON='{"items":[]}'

########################################
# GENERIC
########################################

k_context() {
    kubectl config current-context
}

k_version() {
    kubectl version -o json
}

k_cluster_info() {
    kubectl cluster-info
}

########################################
# SAFE WRAPPERS
########################################

k_get_json() {
    local resource="$1"

    kubectl get "${resource}" -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_get_namespace_json() {
    local namespace="$1"
    local resource="$2"

    kubectl get "${resource}" \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_count() {

    local resource="$1"

    kubectl get "${resource}" \
        --no-headers \
        2>/dev/null \
        | wc -l \
        | tr -d ' '
}

k_count_namespace() {

    local namespace="$1"
    local resource="$2"

    kubectl get "${resource}" \
        -n "${namespace}" \
        --no-headers \
        2>/dev/null \
        | wc -l \
        | tr -d ' '
}

########################################
# NODES
########################################

k_nodes() {
    kubectl get nodes -o json
}

k_node_names() {
    kubectl get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

k_node_count() {
    kubectl get nodes \
        --no-headers \
        | wc -l \
        | tr -d ' '
}

########################################
# NAMESPACES
########################################

k_namespaces() {
    kubectl get namespaces -o json
}

k_namespace_exists() {

    local namespace="$1"

    kubectl get namespace "${namespace}" \
        >/dev/null 2>&1
}

k_namespace_count() {
    kubectl get namespaces \
        --no-headers \
        | wc -l \
        | tr -d ' '
}

########################################
# PODS
########################################

k_pods() {
    kubectl get pods -A -o json
}

k_namespace_pods() {

    local namespace="$1"

    kubectl get pods \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# DEPLOYMENTS
########################################

k_deployments() {
    kubectl get deployments -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_deployments() {

    local namespace="$1"

    kubectl get deployments \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# STATEFULSETS
########################################

k_statefulsets() {
    kubectl get statefulsets -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_statefulsets() {

    local namespace="$1"

    kubectl get statefulsets \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# DAEMONSETS
########################################

k_daemonsets() {
    kubectl get daemonsets -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_daemonsets() {

    local namespace="$1"

    kubectl get daemonsets \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# JOBS
########################################

k_jobs() {
    kubectl get jobs -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_jobs() {

    local namespace="$1"

    kubectl get jobs \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# CRONJOBS
########################################

k_cronjobs() {
    kubectl get cronjobs -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_cronjobs() {

    local namespace="$1"

    kubectl get cronjobs \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# SERVICES
########################################

k_services() {
    kubectl get svc -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_services() {

    local namespace="$1"

    kubectl get svc \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# INGRESS
########################################

k_ingresses() {
    kubectl get ingress -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_ingresses() {

    local namespace="$1"

    kubectl get ingress \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# ENDPOINTS
########################################

k_endpoints() {
    kubectl get endpoints -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_endpoints() {

    local namespace="$1"

    kubectl get endpoints \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# STORAGE
########################################

k_pvcs() {
    kubectl get pvc -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_pvcs() {

    local namespace="$1"

    kubectl get pvc \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_pvs() {
    kubectl get pv -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_storageclasses() {
    kubectl get storageclass -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# CONFIGURATION
########################################

k_configmaps() {
    kubectl get configmaps -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_configmaps() {

    local namespace="$1"

    kubectl get configmaps \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_secrets() {
    kubectl get secrets -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_secrets() {

    local namespace="$1"

    kubectl get secrets \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# SECURITY
########################################

k_serviceaccounts() {
    kubectl get serviceaccounts -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_namespace_serviceaccounts() {

    local namespace="$1"

    kubectl get serviceaccounts \
        -n "${namespace}" \
        -o json \
        2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_roles() {
    kubectl get roles -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_rolebindings() {
    kubectl get rolebindings -A -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_clusterroles() {
    kubectl get clusterroles -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_clusterrolebindings() {
    kubectl get clusterrolebindings -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# CRD
########################################

k_crds() {
    kubectl get crd -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

k_crd_count() {
    kubectl get crd \
        --no-headers 2>/dev/null \
        | wc -l \
        | tr -d ' '
}

# Emit one TSV line per CRD with its addressable metadata.
# Columns: fullname<TAB>group<TAB>plural<TAB>scope<TAB>kind
# fullname is the "<plural>.<group>" identifier used by kubectl.
# Carriage returns are stripped so callers can split safely on TAB
# regardless of the platform emitting the kubectl output.
# Usage: k_crd_specs
k_crd_specs() {
    kubectl get crd -o json 2>/dev/null \
        | jq -r '
            .items[]
            | [
                .metadata.name,
                .spec.group,
                .spec.names.plural,
                .spec.scope,
                .spec.names.kind
              ]
            | @tsv
          ' \
        | tr -d '\r' \
        || true
}

# Count live instances of a custom resource across all namespaces.
# Accepts the "<plural>.<group>" identifier. Returns 0 when the
# resource cannot be listed (RBAC denial, stale CRD, etc.).
# Usage: k_crd_instance_count "widgets.example.com"
k_crd_instance_count() {

    local crd_fullname="$1"

    kubectl get "${crd_fullname}" \
        --all-namespaces \
        --no-headers \
        2>/dev/null \
        | wc -l \
        | tr -d ' '
}

########################################
# APISERVICE
########################################

k_apiservices() {
    kubectl get apiservice -o json 2>/dev/null \
        || echo "${EMPTY_JSON}"
}

########################################
# METRICS
########################################

k_metrics_available() {
    kubectl top nodes >/dev/null 2>&1
}

k_top_nodes() {
    kubectl top nodes 2>/dev/null || true
}

k_top_pods() {
    kubectl top pods -A 2>/dev/null || true
}

########################################
# API RESOURCES
########################################

k_api_resources_namespaced() {
    kubectl api-resources \
        --verbs=list \
        --namespaced \
        -o name
}

k_api_resources_cluster() {
    kubectl api-resources \
        --verbs=list \
        --namespaced=false \
        -o name
}
