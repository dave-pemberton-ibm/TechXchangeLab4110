#!/usr/bin/env bash
# =============================================================================
# create-project.sh
# Creates a new project in webMethods Integration (iPaaS) using the REST API:
#
#   POST <tenant>/apis/v1/rest/projects
#
# Authentication uses an Instance API Key passed as the HTTP header:
#   x-instance-api-key: <your_api_key>
#
# Usage:
#   bash create-project.sh [OPTIONS]
#
# Options:
#   -p, --project      <name>       Project name to create (required)
#   -d, --description  <text>       Project description (default: "")
#   -t, --tenant       <hostname>   Tenant hostname (default: dev3048403.a-vir-r1.int.ipaas.automation.ibm.com)
#   -k, --key          <api-key>    Instance API Key (required, or set WM_API_KEY env var)
#   -v, --verbose                   Show full curl request/response details
#   -h, --help                      Show this help message
#
# Environment variables:
#   WM_API_KEY   Instance API Key
#   WM_TENANT    Tenant hostname override
#
# Docs:
#   Auth     : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=reference-authenticating-api-requests
#   Retrieve : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=apis-retrieving-project
#   Create   : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=apis-creating-projects
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_TENANT="dev3048403.a-vir-r1.int.ipaas.automation.ibm.com"

TENANT_HOST="${WM_TENANT:-${DEFAULT_TENANT}}"
API_KEY="${WM_API_KEY:-}"
PROJECT_NAME=""
PROJECT_DESC=""
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
        -d|--description)
            PROJECT_DESC="${2:-}"
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
            echo "Usage: bash create-project.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --project      <name>       Project name to create"
            echo "  -d, --description  <text>       Project description"
            echo "  -t, --tenant       <hostname>   Tenant hostname"
            echo "                                  (default: ${DEFAULT_TENANT})"
            echo "  -k, --key          <api-key>    Instance API Key (or set WM_API_KEY)"
            echo "  -v, --verbose                   Show full curl request/response details"
            echo "  -h, --help                      Show this help message"
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
echo -e "${BOLD}webMethods Integration iPaaS — Create Project${RESET}"
divider

# ── Validation ────────────────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || { error "'curl' is required but not installed."; exit 1; }
command -v jq   >/dev/null 2>&1 || { error "'jq' is required but not installed."; exit 1; }

if [ -z "${PROJECT_NAME}" ]; then
    error "Project name is required. Use -p or --project <name>."
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

info "Tenant:      ${BASE_URL}"
info "Project:     ${PROJECT_NAME}"
if [ -n "${PROJECT_DESC}" ]; then
    info "Description: ${PROJECT_DESC}"
fi
divider

# ── Check If Project Exists ───────────────────────────────────────────────────
# GET <tenant>/apis/v1/rest/projects/:project
CHECK_URL="${BASE_URL}/apis/v1/rest/projects/${PROJECT_NAME}"

info "Checking if project '${PROJECT_NAME}' already exists..."
verbose "GET ${CHECK_URL}"

CHECK_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${CHECK_URL}" \
    -H "x-instance-api-key: ${API_KEY}" \
    -H "Accept: application/json")

CHECK_HTTP_CODE=$(echo "${CHECK_RESPONSE}" | tail -n1)
CHECK_BODY=$(echo "${CHECK_RESPONSE}" | sed '$d')

verbose "HTTP Status: ${CHECK_HTTP_CODE}"
verbose "Response Body: ${CHECK_BODY}"

if [ "${CHECK_HTTP_CODE}" -ge 200 ] && [ "${CHECK_HTTP_CODE}" -lt 300 ]; then
    success "Project '${PROJECT_NAME}' already exists (HTTP ${CHECK_HTTP_CODE}). Skipping creation."
else
    info "Project '${PROJECT_NAME}' does not exist (HTTP ${CHECK_HTTP_CODE}). Proceeding with creation..."

    # ── Create Project ────────────────────────────────────────────────────────
    CREATE_URL="${BASE_URL}/apis/v1/rest/projects"

    # Build JSON payload
    PAYLOAD=$(jq -n \
        --arg name "${PROJECT_NAME}" \
        --arg desc "${PROJECT_DESC}" \
        '{name: $name, description: $desc}')

    info "Creating project '${PROJECT_NAME}'..."
    verbose "POST ${CREATE_URL}"
    verbose "Payload: ${PAYLOAD}"

    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${CREATE_URL}" \
        -H "x-instance-api-key: ${API_KEY}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "${PAYLOAD}")

    HTTP_CODE=$(echo "${HTTP_RESPONSE}" | tail -n1)
    BODY=$(echo "${HTTP_RESPONSE}" | sed '$d')

    verbose "HTTP Status: ${HTTP_CODE}"
    verbose "Response Body: ${BODY}"

    if [ "${HTTP_CODE}" -ge 200 ] && [ "${HTTP_CODE}" -lt 300 ]; then
        success "Successfully created project '${PROJECT_NAME}' (HTTP ${HTTP_CODE})"
        if [ -n "${BODY}" ]; then
            echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
        fi
    else
        error "Failed to create project '${PROJECT_NAME}' (HTTP ${HTTP_CODE})"
        if [ -n "${BODY}" ]; then
            echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
        fi
        exit 1
    fi
fi

divider

