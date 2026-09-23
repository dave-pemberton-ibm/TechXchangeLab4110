#!/usr/bin/env bash
# =============================================================================
# import-project.sh
# Imports a webMethods Integration (iPaaS) project zip file into a tenant,
# optionally under a different project name.
#
#   POST <tenant>/apis/v1/rest/project-import
#
# Authentication uses an Instance API Key passed as the HTTP header:
#   x-instance-api-key: <your_api_key>
#
# Usage:
#   bash import-project.sh [OPTIONS]
#
# Options:
#   -f, --file       <path>       Path to the project .zip file (required)
#   -n, --name       <name>       New project name to import as (required)
#   -t, --tenant     <hostname>   Tenant hostname (default: dev3048403.a-vir-r1.int.ipaas.automation.ibm.com)
#   -k, --key        <api-key>    Instance API Key (required, or set WM_API_KEY env var)
#   -V, --visibility <value>      Project visibility: private or public (default: private)
#   -v, --verbose                 Show full request/response details
#   -h, --help                    Show this help message
#
# Environment variables:
#   WM_API_KEY   Instance API Key (avoids passing key on command line)
#   WM_TENANT    Tenant hostname override
#
# Examples:
#   bash import-project.sh --file MyProject.zip --name MyNewProject --key abc123
#   bash import-project.sh -f MyProject.zip -n MyNewProject -t myorg.int-aws-us.webmethods.io -k abc123
#   WM_API_KEY=abc123 bash import-project.sh -f MyProject.zip -n MyNewProject
#
# Docs:
#   Auth   : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=reference-authenticating-api-requests
#   Import : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=apis-importing-projects
# =============================================================================

set -euo pipefail

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
verbose() { if [ "${VERBOSE}" = true ]; then echo -e "${MAGENTA}[VERBOSE]${RESET} $*"; fi; }
divider() { echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_TENANT="dev3048403.a-vir-r1.int.ipaas.automation.ibm.com"

TENANT_HOST="${WM_TENANT:-${DEFAULT_TENANT}}"
API_KEY="${WM_API_KEY:-}"
PROJECT_FILE=""
NEW_PROJECT_NAME=""
VISIBILITY="private"
VERBOSE=false

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}Usage:${RESET} bash import-project.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --file       <path>      Path to the project .zip file (required)"
    echo "  -n, --name       <name>      New project name to import as (required)"
    echo "  -t, --tenant     <hostname>  Tenant hostname"
    echo "                               (default: ${DEFAULT_TENANT})"
    echo "  -k, --key        <api-key>   Instance API Key (or set WM_API_KEY env var)"
    echo "  -V, --visibility <value>     private or public (default: private)"
    echo "  -v, --verbose               Show full request/response details"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  WM_API_KEY   Instance API Key"
    echo "  WM_TENANT    Tenant hostname override"
    echo ""
    echo "Examples:"
    echo "  bash import-project.sh -f MyProject.zip -n MyNewProject -k abc123"
    echo "  WM_API_KEY=abc123 bash import-project.sh -f MyProject.zip -n MyNewProject"
    echo ""
}

# ── Argument parsing ──────────────────────────────────────────────────────────
# No args and no env vars — run interactively
if [ $# -eq 0 ] && [ -z "${API_KEY}" ]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            PROJECT_FILE="${2:-}"
            shift 2
            ;;
        -n|--name)
            NEW_PROJECT_NAME="${2:-}"
            shift 2
            ;;
        -t|--tenant)
            TENANT_HOST="${2:-}"
            shift 2
            ;;
        -k|--key)
            API_KEY="${2:-}"
            shift 2
            ;;
        -V|--visibility)
            VISIBILITY="${2:-private}"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  webMethods Integration — Project Importer${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

# ── Pre-flight: check curl is available ───────────────────────────────────────
info "Checking dependencies..."

if ! command -v curl &>/dev/null; then
    error "curl is not installed or not on your PATH."
    error "Install it with:"
    error "  • Ubuntu/Debian : sudo apt install curl"
    error "  • macOS          : brew install curl"
    exit 1
fi
success "curl  : $(curl --version | head -1)"

if ! command -v jq &>/dev/null; then
    warn "jq is not installed — JSON responses will be shown raw."
    warn "Install it for nicer output:"
    warn "  • Ubuntu/Debian : sudo apt install jq"
    warn "  • macOS          : brew install jq"
    JQ_AVAILABLE=false
else
    success "jq    : $(jq --version)"
    JQ_AVAILABLE=true
fi
echo ""

# ── Interactive prompts ───────────────────────────────────────────────────────
if [ "${INTERACTIVE}" = true ]; then
    divider
    echo ""
    echo -e "${BOLD}  No parameters supplied — running interactively${RESET}"
    echo ""

    read -rp "$(echo -e "  ${CYAN}Project .zip file${RESET} (path to the exported project zip): ")" PROJECT_FILE
    read -rp "$(echo -e "  ${CYAN}New project name${RESET}  (name to import the project as): ")" NEW_PROJECT_NAME

    echo ""
    echo -e "  ${CYAN}Tenant hostname${RESET} (press Enter to use default):"
    echo -e "  ${YELLOW}Default: ${DEFAULT_TENANT}${RESET}"
    read -rp "  > " TENANT_INPUT
    if [[ -n "${TENANT_INPUT}" ]]; then
        TENANT_HOST="${TENANT_INPUT}"
    fi

    read -rp "$(echo -e "  ${CYAN}Visibility${RESET} (private/public, default: private): ")" VIS_INPUT
    if [[ -n "${VIS_INPUT}" ]]; then
        VISIBILITY="${VIS_INPUT}"
    fi

    echo ""
    echo -e "  ${YELLOW}You need a personal Instance API Key from the IBM SaaS Console.${RESET}"
    echo -e "  ${YELLOW}Go to: Access Management → Service IDs → API Keys${RESET}"
    echo ""
    read -rsp "$(echo -e "  ${CYAN}Instance API Key${RESET} (input hidden): ")" API_KEY
    echo ""
    echo ""
fi

# ── Validate parameters ───────────────────────────────────────────────────────
ERRORS=false

if [[ -z "${PROJECT_FILE}" ]]; then
    error "Project zip file is required. Use --file."
    ERRORS=true
elif [ ! -f "${PROJECT_FILE}" ]; then
    error "File not found: ${PROJECT_FILE}"
    ERRORS=true
elif [[ "${PROJECT_FILE}" != *.zip ]]; then
    warn "File does not have a .zip extension — proceeding anyway: ${PROJECT_FILE}"
fi

if [[ -z "${NEW_PROJECT_NAME}" ]]; then
    error "New project name is required. Use --name."
    ERRORS=true
fi

if [[ -z "${API_KEY}" ]]; then
    error "API key is required. Use --key or set WM_API_KEY."
    ERRORS=true
fi

if [[ "${VISIBILITY}" != "private" && "${VISIBILITY}" != "public" ]]; then
    error "Visibility must be 'private' or 'public', got: ${VISIBILITY}"
    ERRORS=true
fi

[ "${ERRORS}" = true ] && { usage; exit 1; }

# Strip trailing slash from hostname
TENANT_HOST="${TENANT_HOST%/}"

ENDPOINT="https://${TENANT_HOST}/apis/v1/rest/project-import"
FILE_SIZE=$(du -sh "${PROJECT_FILE}" | cut -f1)

# ── Confirm ───────────────────────────────────────────────────────────────────
divider
echo ""
info "Tenant      : ${BOLD}https://${TENANT_HOST}${RESET}"
info "Endpoint    : ${BOLD}${ENDPOINT}${RESET}"
info "Source file : ${BOLD}${PROJECT_FILE}${RESET} (${FILE_SIZE})"
info "Project name: ${BOLD}${NEW_PROJECT_NAME}${RESET}"
info "Visibility  : ${BOLD}${VISIBILITY}${RESET}"
info "Verbose     : ${BOLD}${VERBOSE}${RESET}"
echo ""

if [ "${VERBOSE}" = true ]; then
    verbose "Request  : POST ${ENDPOINT}"
    verbose "Headers  : x-instance-api-key: <redacted>"
    verbose "Fields   : project=@${PROJECT_FILE}  new_project_name=${NEW_PROJECT_NAME}  visibility=${VISIBILITY}"
    echo ""
fi

read -rp "$(echo -e "  ${YELLOW}Proceed with import? [y/N]: ${RESET}")" CONFIRM
echo ""

if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    warn "Import cancelled by user."
    exit 0
fi

# ── Execute import ────────────────────────────────────────────────────────────
divider
echo ""
info "Importing project as ${BOLD}${NEW_PROJECT_NAME}${RESET}..."
echo ""

if [ "${VERBOSE}" = true ]; then
    CURL_VERBOSE_LOG=$(mktemp)
    HTTP_RESPONSE=$(
        curl -s -w "\n%{http_code}" \
            --verbose \
            -X POST "${ENDPOINT}" \
            -H "x-instance-api-key: ${API_KEY}" \
            -H "Accept: application/json" \
            -F "project=@${PROJECT_FILE};type=application/zip" \
            -F "new_project_name=${NEW_PROJECT_NAME}" \
            -F "visibility=${VISIBILITY}" \
            2>"${CURL_VERBOSE_LOG}"
    )
    verbose "curl trace:"
    sed "s/${API_KEY}/<redacted>/g" "${CURL_VERBOSE_LOG}" \
        | sed 's/^/          /' \
        | grep -v "^$" || true
    rm -f "${CURL_VERBOSE_LOG}"
    echo ""
else
    HTTP_RESPONSE=$(
        curl -s -w "\n%{http_code}" \
            -X POST "${ENDPOINT}" \
            -H "x-instance-api-key: ${API_KEY}" \
            -H "Accept: application/json" \
            -F "project=@${PROJECT_FILE};type=application/zip" \
            -F "new_project_name=${NEW_PROJECT_NAME}" \
            -F "visibility=${VISIBILITY}" \
            2>/dev/null
    )
fi

HTTP_BODY=$(echo "${HTTP_RESPONSE}" | head -n -1)
HTTP_CODE=$(echo "${HTTP_RESPONSE}" | tail -n 1)

echo -e "    ${CYAN}HTTP status:${RESET} ${HTTP_CODE}"
echo ""

if [ "${VERBOSE}" = true ]; then
    verbose "Raw response body:"
    echo "${HTTP_BODY}" | sed 's/^/          /' || true
    echo ""
fi

# ── Result ────────────────────────────────────────────────────────────────────
if [[ "${HTTP_CODE}" =~ ^2 ]]; then
    success "Project imported successfully as: ${BOLD}${NEW_PROJECT_NAME}${RESET}"
    echo ""
    if [ "${JQ_AVAILABLE}" = true ]; then
        echo "${HTTP_BODY}" | jq -r '
            if .output then
                "    Status            : " + (.output.status // "n/a"),
                if (.output.messaging_issues.issues | length) > 0 then
                    "    Messaging issues  : " + (.output.messaging_issues.issues | join(", "))
                else
                    "    Messaging issues  : none"
                end
            else
                "    Response: " + (. | tostring)
            end
        ' 2>/dev/null || echo "    Response: ${HTTP_BODY}"
    else
        echo "    Response: ${HTTP_BODY}"
    fi
else
    error "Import FAILED (HTTP ${HTTP_CODE})"
    echo ""
    if [ "${JQ_AVAILABLE}" = true ]; then
        echo "${HTTP_BODY}" | jq -r '
            "    Status     : " + (.error.status // "n/a"),
            "    Message    : " + (.error.message // .message // .detail // "unknown error"),
            "    Error code : " + (.error.errorSource.errorCode // "n/a"),
            "    Request ID : " + (.error.errorSource.requestID // "n/a")
        ' 2>/dev/null || echo "    Response: ${HTTP_BODY}"
    else
        echo "    Response: ${HTTP_BODY}"
    fi
    echo ""
    warn "Common causes:"
    warn "  • Invalid or expired API key        → regenerate in IBM SaaS Console"
    warn "  • Wrong tenant hostname             → check your tenant URL"
    warn "  • Project name already exists       → choose a different --name"
    warn "  • Importing to source tenant        → not supported by the API"
    warn "  • Insufficient permissions          → admin access required"
    warn "  • new_project_name not supported    → not available in develop-anywhere/deploy-anywhere environments"
    exit 1
fi

echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "  Done."
echo -e "${BOLD}============================================================${RESET}"
echo ""
