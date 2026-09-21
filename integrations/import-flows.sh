#!/usr/bin/env bash
# =============================================================================
# import-flows.sh
# Imports all *.zip Flow/DAF service archives from a directory into a
# webMethods Integration (IWHI) project using the public REST API:
#
#   POST <tenant>/apis/v1/rest/projects/:project/flow-import
#
# Usage:
#   bash import-flows.sh [zip-directory]
#
# If no directory is supplied the script looks in the current working directory.
#
# Docs: https://www.ibm.com/docs/en/wisolution/wm-integration/11.2.4
#       ?topic=apis-importing-flow-services
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
step()    { echo -e "${BOLD}──────────────────────────────────────────────${RESET}"; }

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
success "curl found: $(curl --version | head -1)"

if ! command -v jq &>/dev/null; then
    warn "jq is not installed — JSON responses will be printed raw."
    warn "Install it for prettier output:"
    warn "  • Ubuntu/Debian : sudo apt install jq"
    warn "  • macOS          : brew install jq"
    JQ_AVAILABLE=false
else
    success "jq found: $(jq --version)"
    JQ_AVAILABLE=true
fi
echo ""

# ── Zip directory ─────────────────────────────────────────────────────────────
ZIP_DIR="${1:-.}"

if [ ! -d "${ZIP_DIR}" ]; then
    error "Directory not found: ${ZIP_DIR}"
    exit 1
fi

# Resolve to absolute path for clarity in output
ZIP_DIR="$(cd "${ZIP_DIR}" && pwd)"
info "Looking for *.zip files in: ${BOLD}${ZIP_DIR}${RESET}"

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
step
echo ""
echo -e "${BOLD}  Please answer the following questions:${RESET}"
echo ""

# Tenant hostname
read -rp "$(echo -e "  ${CYAN}Tenant hostname${RESET} (e.g. myorg.dev-int-aws-us.webmethods.io): ")" TENANT_HOST
TENANT_HOST="${TENANT_HOST%/}"   # strip any trailing slash

if [[ -z "${TENANT_HOST}" ]]; then
    error "Tenant hostname cannot be empty."
    exit 1
fi

# Project name
read -rp "$(echo -e "  ${CYAN}Project name${RESET} (the project to import into): ")" PROJECT_NAME

if [[ -z "${PROJECT_NAME}" ]]; then
    error "Project name cannot be empty."
    exit 1
fi

# Credentials
read -rp "$(echo -e "  ${CYAN}Username${RESET}: ")" USERNAME
read -rsp "$(echo -e "  ${CYAN}Password${RESET} (input hidden): ")" PASSWORD
echo ""
echo ""

# Build base URL
BASE_URL="https://${TENANT_HOST}/apis/v1/rest/projects/${PROJECT_NAME}/flow-import"

step
echo ""
info "Tenant  : ${BOLD}https://${TENANT_HOST}${RESET}"
info "Project : ${BOLD}${PROJECT_NAME}${RESET}"
info "Endpoint: ${BOLD}${BASE_URL}${RESET}"
echo ""

# Confirm before proceeding
read -rp "$(echo -e "  ${YELLOW}Proceed with import? Existing flow services with the same name will be overwritten. [y/N]: ${RESET}")" CONFIRM
echo ""

if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    warn "Import cancelled by user."
    exit 0
fi

# ── Import loop ───────────────────────────────────────────────────────────────
step
echo ""
info "Starting import of ${#ZIP_FILES[@]} file(s)..."
echo ""

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=()

for ZIP_FILE in "${ZIP_FILES[@]}"; do
    BASENAME="$(basename "${ZIP_FILE}")"
    echo -e "  ${BOLD}→ Importing:${RESET} ${BASENAME}"

    HTTP_RESPONSE=$(
        curl -s -w "\n%{http_code}" \
            -X POST "${BASE_URL}" \
            -u "${USERNAME}:${PASSWORD}" \
            -H "Accept: application/json" \
            -F "recipe=@${ZIP_FILE};type=application/zip" \
            2>/dev/null
    )

    # Separate body from HTTP status code (last line)
    HTTP_BODY=$(echo "${HTTP_RESPONSE}" | head -n -1)
    HTTP_CODE=$(echo "${HTTP_RESPONSE}" | tail -n 1)

    echo -e "    ${CYAN}HTTP status:${RESET} ${HTTP_CODE}"

    if [[ "${HTTP_CODE}" =~ ^2 ]]; then
        success "Import succeeded: ${BASENAME}"
        if [ "${JQ_AVAILABLE}" = true ]; then
            echo "${HTTP_BODY}" | jq -r '
                if .output then
                    "    \u001b[32mName\u001b[0m          : " + (.output.name // "n/a"),
                    "    \u001b[32mAssembly type\u001b[0m : " + (.output.assemblyType // "n/a"),
                    "    \u001b[32mFull name\u001b[0m     : " + (.output.serviceFullName // "n/a"),
                    "    \u001b[32mProject UID\u001b[0m   : " + (.output.project_uid // "n/a")
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
step
echo ""
echo -e "${BOLD}  Import Summary${RESET}"
echo ""
success "Succeeded : ${PASS_COUNT} / ${#ZIP_FILES[@]}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    error   "Failed    : ${FAIL_COUNT} / ${#ZIP_FILES[@]}"
    echo ""
    warn "The following files failed to import:"
    for f in "${FAIL_LIST[@]}"; do
        echo -e "    ${RED}✗${RESET} ${f}"
    done
    echo ""
    warn "Common reasons for failure:"
    warn "  • Wrong tenant hostname or project name"
    warn "  • Incorrect username / password"
    warn "  • The zip is not a valid Flow/DAF export"
    warn "  • Your account lacks write access to the project"
else
    echo ""
    success "All files imported successfully!"
fi

echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "  Done."
echo -e "${BOLD}============================================================${RESET}"
echo ""

# Exit with error code if anything failed
[ "${FAIL_COUNT}" -eq 0 ] || exit 1
