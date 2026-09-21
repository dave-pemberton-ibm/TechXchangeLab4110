#!/usr/bin/env bash
# =============================================================================
# import-flows.sh
# Imports all *.zip Flow/DAF service archives from a directory into a
# webMethods Integration (iPaaS) project using the public REST API.
#
#   POST <tenant>/apis/v1/rest/projects/:project/flow-import
#
# Authentication uses an Instance API Key passed as the HTTP header:
#   x-instance-api-key: <your_api_key>
#
# Usage:
#   bash import-flows.sh [zip-directory]
#
# If no directory is supplied the script looks in the current working directory.
#
# Docs:
#   Auth   : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=reference-authenticating-api-requests
#   Import : https://www.ibm.com/docs/en/wm-integration-ipaas?topic=apis-importing-flow-services
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

info()    { echo -e "${CYAN}[INFO]${RESET}    $*"; }
success() { echo -e "${GREEN}[OK]${RESET}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}    $*"; }
error()   { echo -e "${RED}[ERROR]${RESET}   $*" >&2; }
divider() { echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  webMethods Integration — Flow Service Importer${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────
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

# ── Locate zip files ──────────────────────────────────────────────────────────
ZIP_DIR="${1:-.}"

if [ ! -d "${ZIP_DIR}" ]; then
    error "Directory not found: ${ZIP_DIR}"
    exit 1
fi

ZIP_DIR="$(cd "${ZIP_DIR}" && pwd)"
info "Scanning for *.zip files in: ${BOLD}${ZIP_DIR}${RESET}"

mapfile -t ZIP_FILES < <(find "${ZIP_DIR}" -maxdepth 1 -name "*.zip" | sort)

if [ ${#ZIP_FILES[@]} -eq 0 ]; then
    error "No *.zip files found in: ${ZIP_DIR}"
    error "Make sure your exported Flow/DAF service archives are in that directory."
    exit 1
fi

echo ""
info "Found ${BOLD}${#ZIP_FILES[@]}${RESET} zip file(s) to import:"
for f in "${ZIP_FILES[@]}"; do
    echo -e "    ${CYAN}•${RESET} $(basename "${f}")"
done
echo ""

# ── Interactive prompts ───────────────────────────────────────────────────────
divider
echo ""
echo -e "${BOLD}  Connection details${RESET}"
echo ""

# Tenant hostname
read -rp "$(echo -e "  ${CYAN}Tenant hostname${RESET} (e.g. myorg.int-aws-us.webmethods.io): ")" TENANT_HOST
TENANT_HOST="${TENANT_HOST%/}"   # strip any trailing slash

if [[ -z "${TENANT_HOST}" ]]; then
    error "Tenant hostname cannot be empty."
    exit 1
fi

# Project name
read -rp "$(echo -e "  ${CYAN}Project name${RESET}   (exact name of the target project): ")" PROJECT_NAME

if [[ -z "${PROJECT_NAME}" ]]; then
    error "Project name cannot be empty."
    exit 1
fi

# Instance API Key
echo ""
echo -e "  ${YELLOW}You need a personal Instance API Key from the IBM SaaS Console.${RESET}"
echo -e "  ${YELLOW}Go to: Access Management → Service IDs → API Keys${RESET}"
echo ""
read -rsp "$(echo -e "  ${CYAN}Instance API Key${RESET} (input hidden): ")" API_KEY
echo ""

if [[ -z "${API_KEY}" ]]; then
    error "API key cannot be empty."
    exit 1
fi

echo ""

# Build endpoint URL
BASE_URL="https://${TENANT_HOST}/apis/v1/rest/projects/${PROJECT_NAME}/flow-import"

divider
echo ""
info "Tenant   : ${BOLD}https://${TENANT_HOST}${RESET}"
info "Project  : ${BOLD}${PROJECT_NAME}${RESET}"
info "Endpoint : ${BOLD}${BASE_URL}${RESET}"
info "Auth     : ${BOLD}x-instance-api-key${RESET} (Instance API Key)"
echo ""

# Confirm before proceeding
read -rp "$(echo -e "  ${YELLOW}Proceed? Existing flow services with the same name will be overwritten. [y/N]: ${RESET}")" CONFIRM
echo ""

if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    warn "Import cancelled by user."
    exit 0
fi

# ── Import loop ───────────────────────────────────────────────────────────────
divider
echo ""
info "Starting import of ${BOLD}${#ZIP_FILES[@]}${RESET} file(s)..."
echo ""

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=()

for ZIP_FILE in "${ZIP_FILES[@]}"; do
    BASENAME="$(basename "${ZIP_FILE}")"
    echo -e "  ${BOLD}→ Importing:${RESET} ${BASENAME}"

    # POST the zip as multipart/form-data field 'recipe'
    # Capture body + HTTP status code on last line
    HTTP_RESPONSE=$(
        curl -s -w "\n%{http_code}" \
            -X POST "${BASE_URL}" \
            -H "x-instance-api-key: ${API_KEY}" \
            -H "Accept: application/json" \
            -F "recipe=@${ZIP_FILE};type=application/zip" \
            2>/dev/null
    )

    HTTP_BODY=$(echo "${HTTP_RESPONSE}" | head -n -1)
    HTTP_CODE=$(echo "${HTTP_RESPONSE}" | tail -n 1)

    echo -e "    ${CYAN}HTTP status:${RESET} ${HTTP_CODE}"

    if [[ "${HTTP_CODE}" =~ ^2 ]]; then
        success "Import succeeded: ${BASENAME}"
        if [ "${JQ_AVAILABLE}" = true ]; then
            echo "${HTTP_BODY}" | jq -r '
                if .output then
                    "    Name          : " + (.output.name          // "n/a"),
                    "    Assembly type : " + (.output.assemblyType  // "n/a"),
                    "    Full name     : " + (.output.serviceFullName // "n/a"),
                    "    Project UID   : " + (.output.project_uid   // "n/a"),
                    "    Tenant UID    : " + (.output.tenant_uid    // "n/a")
                else
                    "    Response: " + (. | tostring)
                end
            ' 2>/dev/null || echo "    Response: ${HTTP_BODY}"
        else
            echo "    Response: ${HTTP_BODY}"
        fi
        (( PASS_COUNT++ )) || true
    else
        error "Import FAILED: ${BASENAME} (HTTP ${HTTP_CODE})"
        if [ "${JQ_AVAILABLE}" = true ]; then
            echo "${HTTP_BODY}" | jq -r '
                "    Error: " + ((.message // .error // .detail // .) | tostring)
            ' 2>/dev/null || echo "    Response: ${HTTP_BODY}"
        else
            echo "    Response: ${HTTP_BODY}"
        fi
        (( FAIL_COUNT++ )) || true
        FAIL_LIST+=("${BASENAME}")
    fi
    echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
divider
echo ""
echo -e "${BOLD}  Import Summary${RESET}"
echo ""
success "Succeeded : ${PASS_COUNT} / ${#ZIP_FILES[@]}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    error   "Failed    : ${FAIL_COUNT} / ${#ZIP_FILES[@]}"
    echo ""
    warn "Files that failed:"
    for f in "${FAIL_LIST[@]}"; do
        echo -e "    ${RED}✗${RESET} ${f}"
    done
    echo ""
    warn "Common causes:"
    warn "  • Invalid or expired API key  → regenerate in IBM SaaS Console"
    warn "  • Wrong tenant hostname       → check your tenant URL"
    warn "  • Project name does not exist → verify the exact project name in webMethods Integration"
    warn "  • Insufficient permissions    → you need admin or project write access"
    warn "  • The zip is not a valid Flow/DAF export"
else
    echo ""
    success "All files imported successfully!"
fi

echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "  Done."
echo -e "${BOLD}============================================================${RESET}"
echo ""

[ "${FAIL_COUNT}" -eq 0 ] || exit 1
