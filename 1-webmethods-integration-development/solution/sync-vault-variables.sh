#!/usr/bin/env bash
# =============================================================================
# sync-vault-variables.sh
# Synchronizes vault/configuration variables into a linked project in
# webMethods Integration (iPaaS) using the public REST API v2:
#
#   POST <tenant>/apis/v2/rest/configurations/variables/{variable_name}/sync?projects={list_of_projects}
#
# Authentication uses an Instance API Key passed as the HTTP header:
#   x-instance-api-key: <your_api_key>
#
# Usage:
#   bash sync-vault-variables.sh [OPTIONS]
#
# Options:
#   -t, --tenant   <hostname>   Tenant hostname (default: dev3048403.a-vir-r1.int.ipaas.automation.ibm.com)
#   -p, --project  <name>       Project name to sync variable into (required)
#   -n, --name     <var-name>   Vault variable name to sync (required)
#   -k, --key      <api-key>    Instance API Key (required, or set WM_API_KEY env var)
#   -v, --verbose               Show full curl request/response details
#   -h, --help                  Show this help message
#
# Environment variables:
#   WM_API_KEY   Instance API Key
#   WM_TENANT    Tenant hostname override
#
# Docs:
#   https://www.ibm.com/docs/en/wm-integration-ipaas?topic=references-public-apis
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_TENANT="dev3048403.a-vir-r1.int.ipaas.automation.ibm.com"

TENANT_HOST="${WM_TENANT:-${DEFAULT_TENANT}}"
API_KEY="${WM_API_KEY:-}"
PROJECT_NAME=""
VAR_NAME=""
VERBOSE=false

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--tenant)
            TENANT_HOST="${2:-}"
            shift 2
            ;;
        -p|--project)
            PROJECT_NAME="${2:-}"
            shift 2
            ;;
        -n|--name)
            VAR_NAME="${2:-}"
            shift 2
            ;;
        -k|--key)
            API_KEY="${2:-}"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo ""
            echo "Usage: bash sync-vault-variables.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -t, --tenant   <hostname>   Tenant hostname"
            echo "                              (default: ${DEFAULT_TENANT})"
            echo "  -p, --project  <name>       Project name to sync variable into"
            echo "  -n, --name     <var-name>   Vault variable name to sync"
            echo "  -k, --key      <api-key>    Instance API Key (or set WM_API_KEY)"
            echo "  -v, --verbose               Show full curl request/response details"
            echo "  -h, --help                  Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h or --help for usage details." >&2
            exit 1
            ;;
    esac
done

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
BOLD="\033[1m"
RESET="\033[0m"

info()    { echo -e "${CYAN}[INFO]${RESET}    $*"; }
success() { echo -e "${GREEN}[OK]${RESET}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}    $*"; }
error()   { echo -e "${RED}[ERROR]${RESET}   $*" >&2; }
divider() { echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"; }
verbose() { if [ "${VERBOSE}" = true ]; then echo -e "${MAGENTA}[VERBOSE]${RESET} $*"; fi; }

# ── Banner ────────────────────────────────────────────────────────────────────
divider
echo -e "${BOLD}webMethods Integration iPaaS — Sync Vault Variable${RESET}"
divider

# ── Validation ────────────────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || { error "'curl' is required but not installed."; exit 1; }
command -v jq   >/dev/null 2>&1 || { error "'jq' is required but not installed."; exit 1; }

if [ -z "${PROJECT_NAME}" ]; then
    error "Project name is required. Use -p or --project <name>."
    exit 1
fi

if [ -z "${VAR_NAME}" ]; then
    error "Variable name is required. Use -n or --name <var-name>."
    exit 1
fi

if [ -z "${API_KEY}" ]; then
    error "API Key is required. Pass -k / --key or export WM_API_KEY."
    exit 1
fi

# Strip https:// if user included it in tenant hostname
TENANT_HOST="${TENANT_HOST#https://}"
TENANT_HOST="${TENANT_HOST#http://}"
TENANT_HOST="${TENANT_HOST%/}"

BASE_URL="https://${TENANT_HOST}"

info "Tenant:   ${BASE_URL}"
info "Project:  ${PROJECT_NAME}"
info "Variable: ${VAR_NAME}"
divider

# ── Sync Vault Variable to Project ────────────────────────────────────────────
# Exact API endpoint:
# POST /apis/v2/rest/configurations/variables/{variable_name}/sync?projects={list_of_projects}
SYNC_URL="${BASE_URL}/apis/v2/rest/configurations/variables/${VAR_NAME}/sync?projects=${PROJECT_NAME}"

info "Synchronizing vault variable '${VAR_NAME}' to project '${PROJECT_NAME}'..."
verbose "POST ${SYNC_URL}"

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${SYNC_URL}" \
    -H "x-instance-api-key: ${API_KEY}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json")

HTTP_CODE=$(echo "${HTTP_RESPONSE}" | tail -n1)
BODY=$(echo "${HTTP_RESPONSE}" | sed '$d')

verbose "HTTP Status: ${HTTP_CODE}"
verbose "Response Body: ${BODY}"

if [ "${HTTP_CODE}" -ge 200 ] && [ "${HTTP_CODE}" -lt 300 ]; then
    success "Successfully synchronized '${VAR_NAME}' to '${PROJECT_NAME}' (HTTP ${HTTP_CODE})"
    if [ -n "${BODY}" ]; then
        echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
    fi
else
    error "Failed to synchronize variable '${VAR_NAME}' to project '${PROJECT_NAME}' (HTTP ${HTTP_CODE})"
    if [ -n "${BODY}" ]; then
        echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
    fi
    exit 1
fi

divider

