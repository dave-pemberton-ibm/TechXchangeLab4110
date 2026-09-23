#!/usr/bin/env bash
# =============================================================================
# export-project.sh
# Exports a webMethods Integration (iPaaS) project to a local JSON file
# using the public REST API.
#
#   POST <tenant>/apis/v1/rest/projects/<project>/export
#
# Authentication uses an Instance API Key passed as the HTTP header:
#   x-instance-api-key: <your_api_key>
#
# Usage:
#   bash export-project.sh [OPTIONS]
#
# Options:
#   -t, --tenant   <hostname>    Tenant hostname (required)
#   -p, --project  <name>        Project name or UID (required)
#   -k, --key      <api-key>     Instance API Key (required, or set WM_API_KEY env var)
#   -o, --output   <file>        Output filename (default: <project>-export.json)
#   -v, --verbose                Show full request/response details
#   -h, --help                   Show this help message
#
# Environment variables:
#   WM_API_KEY     Instance API Key (avoids passing key on command line)
#   WM_TENANT      Tenant hostname
#   WM_PROJECT     Project name
#
# Examples:
#   bash export-project.sh --tenant myorg.int-aws-us.webmethods.io --project MyProject --key abc123
#   WM_API_KEY=abc123 bash export-project.sh -t myorg.int-aws-us.webmethods.io -p MyProject
#
# Docs:
#   Auth   : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=reference-authenticating-api-requests
#   Export : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=apis-exporting-projects
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

# ── Defaults (can be overridden by env vars or flags) ─────────────────────────
TENANT_HOST="${WM_TENANT:-}"
PROJECT_NAME="${WM_PROJECT:-}"
API_KEY="${WM_API_KEY:-}"
OUTPUT_FILE=""
VERBOSE=false

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}Usage:${RESET} bash export-project.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --tenant   <hostname>   Tenant hostname (e.g. myorg.int-aws-us.webmethods.io)"
    echo "  -p, --project  <name>       Project name or UID"
    echo "  -k, --key      <api-key>    Instance API Key (or set WM_API_KEY env var)"
    echo "  -o, --output   <file>       Output filename (default: <project>-export.json)"
    echo "  -v, --verbose               Show full request/response details"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  WM_API_KEY   Instance API Key"
    echo "  WM_TENANT    Tenant hostname"
    echo "  WM_PROJECT   Project name"
    echo ""
    echo "Examples:"
    echo "  bash export-project.sh -t myorg.int-aws-us.webmethods.io -p MyProject -k abc123"
    echo "  WM_API_KEY=abc123 bash export-project.sh -t myorg.int-aws-us.webmethods.io -p MyProject"
    echo ""
}

# ── Argument parsing ──────────────────────────────────────────────────────────
if [ $# -eq 0 ] && [ -z "${TENANT_HOST}" ] && [ -z "${PROJECT_NAME}" ] && [ -z "${API_KEY}" ]; then
    # No args and no env vars — run interactively
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

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
        -k|--key)
            API_KEY="${2:-}"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="${2:-}"
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
echo -e "${BOLD}  webMethods Integration — Project Exporter${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

# ── Pre-flight: check wget is available ───────────────────────────────────────
info "Checking dependencies..."

if ! command -v wget &>/dev/null; then
    error "wget is not installed or not on your PATH."
    error "Install it with:"
    error "  • Ubuntu/Debian : sudo apt install wget"
    error "  • macOS          : brew install wget"
    exit 1
fi
success "wget  : $(wget --version | head -1)"

if ! command -v jq &>/dev/null; then
    warn "jq is not installed — JSON output will not be pretty-printed."
    warn "Install it for nicer output:"
    warn "  • Ubuntu/Debian : sudo apt install jq"
    warn "  • macOS          : brew install jq"
    JQ_AVAILABLE=false
else
    success "jq    : $(jq --version)"
    JQ_AVAILABLE=true
fi
echo ""

# ── Interactive prompts (when no args given) ──────────────────────────────────
if [ "${INTERACTIVE}" = true ]; then
    divider
    echo ""
    echo -e "${BOLD}  No parameters supplied — running interactively${RESET}"
    echo ""

    read -rp "$(echo -e "  ${CYAN}Tenant hostname${RESET} (e.g. myorg.int-aws-us.webmethods.io): ")" TENANT_HOST
    read -rp "$(echo -e "  ${CYAN}Project name${RESET}   (exact name or UID of the project): ")" PROJECT_NAME

    echo ""
    echo -e "  ${YELLOW}You need a personal Instance API Key from the IBM SaaS Console.${RESET}"
    echo -e "  ${YELLOW}Go to: Access Management → Service IDs → API Keys${RESET}"
    echo ""
    read -rsp "$(echo -e "  ${CYAN}Instance API Key${RESET} (input hidden): ")" API_KEY
    echo ""
    echo ""

    read -rp "$(echo -e "  ${CYAN}Output filename${RESET} (leave blank for ${PROJECT_NAME}-export.json): ")" OUTPUT_FILE
    echo ""
fi

# ── Validate required parameters ──────────────────────────────────────────────
ERRORS=false

if [[ -z "${TENANT_HOST}" ]]; then
    error "Tenant hostname is required. Use --tenant or set WM_TENANT."
    ERRORS=true
fi

if [[ -z "${PROJECT_NAME}" ]]; then
    error "Project name is required. Use --project or set WM_PROJECT."
    ERRORS=true
fi

if [[ -z "${API_KEY}" ]]; then
    error "API key is required. Use --key or set WM_API_KEY."
    ERRORS=true
fi

[ "${ERRORS}" = true ] && { usage; exit 1; }

# Strip any accidental trailing slash from hostname
TENANT_HOST="${TENANT_HOST%/}"

# Default output filename
if [[ -z "${OUTPUT_FILE}" ]]; then
    OUTPUT_FILE="${PROJECT_NAME}-export.json"
fi

# Warn if output file already exists
if [ -f "${OUTPUT_FILE}" ]; then
    warn "Output file already exists and will be overwritten: ${OUTPUT_FILE}"
fi

# Build endpoint URL
ENDPOINT="https://${TENANT_HOST}/apis/v1/rest/projects/${PROJECT_NAME}/export"

# ── Summary ───────────────────────────────────────────────────────────────────
divider
echo ""
info "Tenant   : ${BOLD}https://${TENANT_HOST}${RESET}"
info "Project  : ${BOLD}${PROJECT_NAME}${RESET}"
info "Endpoint : ${BOLD}${ENDPOINT}${RESET}"
info "Output   : ${BOLD}${OUTPUT_FILE}${RESET}"
info "Verbose  : ${BOLD}${VERBOSE}${RESET}"
echo ""

if [ "${VERBOSE}" = true ]; then
    verbose "Request  : POST ${ENDPOINT}"
    verbose "Headers  : x-instance-api-key: <redacted>"
    verbose "Body     : {} (exports all project assets)"
    echo ""
fi

# ── Execute export ────────────────────────────────────────────────────────────
divider
echo ""
info "Exporting project ${BOLD}${PROJECT_NAME}${RESET}..."
echo ""

WGET_OPTS=(
    --method=POST
    --header="x-instance-api-key: ${API_KEY}"
    --header="Content-Type: application/json"
    --header="Accept: application/json"
    --body-data="{}"
    --server-response        # always show HTTP response headers (goes to stderr)
    -O "${OUTPUT_FILE}"
)

if [ "${VERBOSE}" = true ]; then
    WGET_OPTS+=(--debug)
fi

# Run wget; capture stderr for verbose processing / redaction
WGET_STDERR_LOG=$(mktemp)

if wget "${WGET_OPTS[@]}" "${ENDPOINT}" 2>"${WGET_STDERR_LOG}"; then
    # Redact API key from any logged output before printing
    if [ "${VERBOSE}" = true ]; then
        verbose "wget output:"
        sed "s/${API_KEY}/<redacted>/g" "${WGET_STDERR_LOG}" \
            | sed 's/^/          /' || true
        echo ""
    else
        # Even in normal mode, show the HTTP status line from --server-response
        HTTP_STATUS=$(grep "HTTP/" "${WGET_STDERR_LOG}" | tail -1 | tr -d '\r')
        echo -e "    ${CYAN}Server response:${RESET} ${HTTP_STATUS}"
    fi
    rm -f "${WGET_STDERR_LOG}"
else
    WGET_EXIT=$?
    error "wget exited with code ${WGET_EXIT}"
    echo ""
    warn "wget output:"
    sed "s/${API_KEY}/<redacted>/g" "${WGET_STDERR_LOG}" \
        | sed 's/^/    /' || true
    rm -f "${WGET_STDERR_LOG}"
    echo ""
    warn "Common causes:"
    warn "  • Invalid or expired API key  → regenerate in IBM SaaS Console"
    warn "  • Wrong tenant hostname       → check your tenant URL"
    warn "  • Project does not exist      → verify the exact project name or UID"
    warn "  • Insufficient permissions    → you need admin or project write access"
    exit 1
fi

# ── Validate and report output ────────────────────────────────────────────────
echo ""

if [ ! -f "${OUTPUT_FILE}" ] || [ ! -s "${OUTPUT_FILE}" ]; then
    error "Output file is missing or empty: ${OUTPUT_FILE}"
    exit 1
fi

FILE_SIZE=$(du -sh "${OUTPUT_FILE}" | cut -f1)

success "Export saved to: ${BOLD}$(pwd)/${OUTPUT_FILE}${RESET} (${FILE_SIZE})"
echo ""

if [ "${JQ_AVAILABLE}" = true ]; then
    # Pretty-print a summary from the export JSON
    jq -r '
        "    Source env  : " + (.metadata.source      // "n/a"),
        "    Project     : " + (.metadata.project     // "n/a"),
        "    Generated   : " + (.metadata.generatedOn // "n/a" | tostring),
        "    Packages    : " + ((.configurations.packages    // []) | length | tostring),
        "    Connections : " + ((.configurations.connections // []) | length | tostring),
        "    Variables   : " + ((.configurations.variables   // []) | length | tostring),
        "    Schedules   : " + ((.configurations.servicesSchedule // []) | length | tostring)
    ' "${OUTPUT_FILE}" 2>/dev/null || warn "Could not parse export JSON — file may be unexpected format."
fi

echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "  Done."
echo -e "${BOLD}============================================================${RESET}"
echo ""
