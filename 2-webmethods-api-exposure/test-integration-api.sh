#!/usr/bin/env bash
# =============================================================================
# test-integration-api.sh
# Tests a webMethods Integration REST API endpoint (e.g., /getPassenger360)
# using the X-INSTANCE-API-KEY header.
#
# URL is mandatory (via flag or interactive prompt).
# API Key is read from ./apikey.env if present, via flag, or interactively.
#
# Usage:
#   bash test-integration-api.sh [OPTIONS]
#
# Options:
#   -u, --url       <url>        Base API endpoint URL (required)
#   -k, --key       <api-key>    Instance API Key (or set WM_API_KEY / apikey.env)
#   -i, --id        <id>         Passenger ID (default: P12345)
#   -v, --verbose                Show full curl request/response details
#   -h, --help                   Show this help message
#
# Examples:
#   bash test-integration-api.sh -u "https://dev3048403.a-vir-r1.int.ipaas.automation.ibm.com/integration/restv2/development/fl0cd7334a11e5496c91e1f959a3f532df/cruising"
#   bash test-integration-api.sh -u "https://.../cruising" -i "P12345" -v
#   bash test-integration-api.sh   # interactive mode
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/apikey.env"

# ── Defaults ──────────────────────────────────────────────────────────────────
BASE_URL=""
API_KEY="${WM_API_KEY:-}"
PASSENGER_ID="P12345"
VERBOSE=false

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--url)
            BASE_URL="${2:-}"
            shift 2
            ;;
        -k|--key)
            API_KEY="${2:-}"
            shift 2
            ;;
        -i|--id)
            PASSENGER_ID="${2:-}"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo ""
            echo "Usage: bash test-integration-api.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -u, --url       <url>        Base API endpoint URL (required)"
            echo "  -k, --key       <api-key>    Instance API Key (or set WM_API_KEY / apikey.env)"
            echo "  -i, --id        <id>         Passenger ID (default: P12345)"
            echo "  -v, --verbose                Show full curl request/response details"
            echo "  -h, --help                   Show this help message"
            echo ""
            exit 0
            ;;
        *)
            if [ -z "${BASE_URL}" ]; then
                BASE_URL="$1"
            else
                echo "Unknown option: $1" >&2
                echo "Use -h or --help for usage details." >&2
                exit 1
            fi
            shift
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
echo -e "${BOLD}webMethods Integration iPaaS — Test Integration API${RESET}"
divider

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || { error "'curl' is required but not installed."; exit 1; }

JQ_AVAILABLE=false
if command -v jq >/dev/null 2>&1; then
    JQ_AVAILABLE=true
fi

# ── Resolve API Key: Flag > apikey.env > Interactive prompt ───────────────────
if [ -z "${API_KEY}" ] && [ -f "${ENV_FILE}" ]; then
    FILE_KEY=$(tr -d '\r\n' < "${ENV_FILE}" | xargs)
    if [ -n "${FILE_KEY}" ]; then
        API_KEY="${FILE_KEY}"
        info "Loaded API key from: ${ENV_FILE}"
    fi
fi

# ── Interactive Prompts (if missing required parameters) ──────────────────────
if [ -z "${BASE_URL}" ]; then
    echo ""
    echo -e "  ${CYAN}API Base URL${RESET} is required (e.g. https://.../cruising):"
    read -rp "  > " BASE_URL
    if [ -z "${BASE_URL}" ]; then
        error "API URL cannot be empty."
        exit 1
    fi
fi

if [ -z "${API_KEY}" ]; then
    echo ""
    echo -e "  ${CYAN}Instance API Key${RESET} (input hidden):"
    read -rsp "  > " API_KEY
    echo ""
    if [ -z "${API_KEY}" ]; then
        error "API Key cannot be empty."
        exit 1
    fi
fi

# Strip trailing slash from base URL
BASE_URL="${BASE_URL%/}"

# ── Request Construction ──────────────────────────────────────────────────────
REQUEST_URL="${BASE_URL}/getPassenger360?passenger_id=${PASSENGER_ID}"

echo ""
info "Base URL     : ${BASE_URL}"
info "Request URL  : ${REQUEST_URL}"
info "Passenger ID : ${PASSENGER_ID}"
divider

echo ""
info "Sending GET request to integration API..."
verbose "GET ${REQUEST_URL}"

# ── Execute Request ───────────────────────────────────────────────────────────
if [ "${VERBOSE}" = true ]; then
    CURL_LOG=$(mktemp)
    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
        --verbose \
        -X GET "${REQUEST_URL}" \
        -H "Accept: application/json" \
        -H "X-INSTANCE-API-KEY: ${API_KEY}" \
        2>"${CURL_LOG}")

    echo -e "${MAGENTA}[VERBOSE] curl trace:${RESET}"
    sed "s/${API_KEY}/<redacted>/g" "${CURL_LOG}" | sed 's/^/          /' | grep -v "^$" || true
    rm -f "${CURL_LOG}"
    echo ""
else
    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X GET "${REQUEST_URL}" \
        -H "Accept: application/json" \
        -H "X-INSTANCE-API-KEY: ${API_KEY}")
fi

HTTP_CODE=$(echo "${HTTP_RESPONSE}" | tail -n1)
BODY=$(echo "${HTTP_RESPONSE}" | sed '$d')

echo -e "  ${CYAN}HTTP Status:${RESET} ${HTTP_CODE}"
echo ""

if [ "${HTTP_CODE}" -ge 200 ] && [ "${HTTP_CODE}" -lt 300 ]; then
    success "API request succeeded!"
    echo ""
    echo -e "${BOLD}Response Body:${RESET}"
    if [ "${JQ_AVAILABLE}" = true ]; then
        echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
    else
        echo "${BODY}"
    fi
else
    error "API request failed with HTTP status ${HTTP_CODE}."
    echo ""
    echo -e "${BOLD}Response Body:${RESET}"
    if [ "${JQ_AVAILABLE}" = true ]; then
        echo "${BODY}" | jq . 2>/dev/null || echo "${BODY}"
    else
        echo "${BODY}"
    fi
    exit 1
fi

echo ""
divider

