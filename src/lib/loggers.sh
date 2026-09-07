#!/usr/bin/env bash

#
# lib/logger.sh
#
# Logging utilities
#

########################################
# CONFIG
########################################

: "${LOG_LEVEL:=INFO}"

########################################
# COLORS
########################################

if [[ -t 1 ]]; then
    readonly C_RESET='\033[0m'
    readonly C_RED='\033[31m'
    readonly C_GREEN='\033[32m'
    readonly C_YELLOW='\033[33m'
    readonly C_BLUE='\033[34m'
    readonly C_CYAN='\033[36m'
else
    readonly C_RESET=''
    readonly C_RED=''
    readonly C_GREEN=''
    readonly C_YELLOW=''
    readonly C_BLUE=''
    readonly C_CYAN=''
fi

########################################
# INTERNAL
########################################

_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_log() {
    local level="$1"
    local color="$2"
    shift 2

    printf "%b[%s] [%s] %s%b\n" \
        "${color}" \
        "$(_timestamp)" \
        "${level}" \
        "$*" \
        "${C_RESET}"
}

########################################
# LEVELS
########################################

log_debug() {
    [[ "${LOG_LEVEL}" == "DEBUG" ]] || return 0

    _log "DEBUG" "${C_CYAN}" "$@"
}

log_info() {
    _log "INFO" "${C_GREEN}" "$@"
}

log_warn() {
    _log "WARN" "${C_YELLOW}" "$@"
}

log_error() {
    _log "ERROR" "${C_RED}" "$@" >&2
}

########################################
# FATAL
########################################

fatal() {
    log_error "$@"
    exit 1
}

########################################
# SUCCESS
########################################

log_success() {
    _log "SUCCESS" "${C_GREEN}" "$@"
}

########################################
# SECTION HEADER
########################################

print_header() {

    local title="$1"

    echo
    echo "================================================================"
    echo " ${title}"
    echo "================================================================"
}

########################################
# SECTION FOOTER
########################################

print_footer() {

    echo "================================================================"
    echo
}

########################################
# STEP
########################################

log_step() {
    local message="$1"

    echo
    printf ">> %s\n" "${message}"
}

########################################
# REPORT
########################################

report_item() {

    local label="$1"
    local value="$2"

    printf "%-35s : %s\n" "${label}" "${value}"
}

########################################
# JSON REPORT CREATED
########################################

report_file() {

    local file="$1"

    log_success "Report generated: ${file}"
}

########################################
# EXECUTION TIMER
########################################

timer_start() {
    date +%s
}

timer_end() {

    local start="$1"
    local end

    end="$(date +%s)"

    echo $((end - start))
}

########################################
# DURATION REPORT
########################################

report_duration() {

    local seconds="$1"

    report_item "Execution Time" "${seconds}s"
}

########################################
# TRAP HANDLER
########################################

error_trap() {

    local exit_code="$?"

    log_error \
        "Script failed at line ${BASH_LINENO[0]}: ${BASH_COMMAND}"

    exit "${exit_code}"
}

########################################
# REGISTER TRAP
########################################

register_error_trap() {
    trap error_trap ERR
}
