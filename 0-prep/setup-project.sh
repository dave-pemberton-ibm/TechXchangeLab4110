#!/usr/bin/env bash
# =============================================================================
# setup-project.sh
# End-to-end automation for setting up a webMethods Integration iPaaS project:
#   1. Reads and exports the Instance API Key from apikey.env (as WM_API_KEY)
#   2. Creates the project using create-project.sh
#   3. Imports all Flow/DAF zip archives using import-flows.sh
#   4. Syncs the vault variable(s) using sync-vault-variables.sh
#   5. Customizes OpenAPI spec (STUDENTID -> username) via customize-api-spec.sh
#
# Usage:
#   bash setup-project.sh [OPTIONS] [zip-directory] (default: ./integrations/)
#
# Options:
#   -p, --project      <name>       Project name (default: <linux_username>_YYYYMMDD)
#   -n, --name         <var-name>   Vault variable name to sync (default: DP_CruiseLine_APIKey)
#   -d, --description  <text>       Project description (default: "")
#   -k, --key          <api-key>    Instance API Key (or set WM_API_KEY / apikey.env)
#   -t, --tenant       <hostname>   Tenant hostname (default: dev3048403.a-vir-r1.int.ipaas.automation.ibm.com)
#   -e, --env-file     <path>       Path to apikey.env file (default: ./apikey.env)
#   -y, --yes                       Skip confirmation prompts
#   -v, --verbose                   Show full request/response details
#   -h, --help                      Show this help message
#
# Examples:
#   bash setup-project.sh -p CruisingProject -n wxo_access ./wm-int
#   bash setup-project.sh -p CruisingProject -n wxo_access -d "Cruising integrations" wm-int/ -y -v
# =============================================================================

set -euo pipefail

# Trap unexpected errors and print clear failure message
trap 'echo -e "\n\033[0;31m[ERROR] Setup script aborted due to an error at line $LINENO.\033[0m\n" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_TENANT="dev3048403.a-vir-r1.int.ipaas.automation.ibm.com"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/apikey.env"
DEFAULT_VAR_NAME="DP_CruiseLine_APIKey"
DEFAULT_ZIP_DIR="${SCRIPT_DIR}/integrations"

# Default project name: <linux_username>_YYYYMMDD
CURRENT_USER="$(whoami 2>/dev/null || echo "${USER:-user}")"
CURRENT_DATE="$(date +%Y%m%d)"
DEFAULT_PROJECT_NAME="${CURRENT_USER}_${CURRENT_DATE}"

TENANT_HOST="${WM_TENANT:-${DEFAULT_TENANT}}"
ENV_FILE="${DEFAULT_ENV_FILE}"
API_KEY="${WM_API_KEY:-}"
PROJECT_NAME=""
VAR_NAME="${DEFAULT_VAR_NAME}"
PROJECT_DESC=""
AUTO_CONFIRM=false
VERBOSE=false
POSITIONAL_ARGS=()

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--project)
            PROJECT_NAME="${2:-}"
            shift 2
            ;;
        -n|--name)
            VAR_NAME="${2:-}"
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
        -t|--tenant)
            TENANT_HOST="${2:-}"
            shift 2
            ;;
        -e|--env-file)
            ENV_FILE="${2:-}"
            shift 2
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo ""
            echo "Usage: bash setup-project.sh [OPTIONS] [zip-directory]"
            echo ""
            echo "Positional Arguments:"
            echo "  [zip-directory]             Directory with flow .zip files"
            echo "                              (default: ./integrations/)"
            echo ""
            echo "Options:"
            echo "  -p, --project      <name>       Project name"
            echo "                                  (default: ${DEFAULT_PROJECT_NAME})"
            echo "  -n, --name         <var-name>   Vault variable name to sync"
            echo "                                  (default: ${DEFAULT_VAR_NAME})"
            echo "  -d, --description  <text>       Project description"
            echo "  -k, --key          <api-key>    Instance API Key (or set WM_API_KEY / apikey.env)"
            echo "  -t, --tenant       <hostname>   Tenant hostname"
            echo "                                  (default: ${DEFAULT_TENANT})"
            echo "  -e, --env-file     <path>       Path to apikey.env file"
            echo "                                  (default: ./apikey.env)"
            echo "  -y, --yes                       Skip confirmation prompts"
            echo "  -v, --verbose                   Show full curl request/response details"
            echo "  -h, --help                      Show this help message"
            echo ""
            exit 0
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
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
divider() { echo -e "${BOLD}══════════════════════════════════════════════════${RESET}"; }
step()    { echo -e "\n${BOLD}${MAGENTA}▶ STEP $1:${RESET} ${BOLD}$2${RESET}\n"; }

# ── Validation ────────────────────────────────────────────────────────────────
if [ -z "${PROJECT_NAME}" ]; then
    PROJECT_NAME="${DEFAULT_PROJECT_NAME}"
    info "No project name supplied. Defaulting to '${PROJECT_NAME}'."
fi

if [ -z "${VAR_NAME}" ]; then
    VAR_NAME="${DEFAULT_VAR_NAME}"
fi

ZIP_DIR="${POSITIONAL_ARGS[0]:-${DEFAULT_ZIP_DIR}}"
if [ ! -d "${ZIP_DIR}" ]; then
    error "Flow zip directory not found: ${ZIP_DIR}"
    echo "Please make sure '${ZIP_DIR}' exists or provide a directory path." >&2
    exit 1
fi

# ── Step 1: Resolve API Key ───────────────────────────────────────────────────
divider
echo -e "${BOLD}webMethods Integration iPaaS — Full Project Setup Flow${RESET}"
divider

step "1" "Resolve Instance API Key"

# 1. Check if supplied via -k/--key or WM_API_KEY env var
if [ -z "${API_KEY}" ]; then
    # 2. Check if apikey.env exists and is not empty
    if [ -f "${ENV_FILE}" ]; then
        FILE_KEY=$(tr -d '\r\n' < "${ENV_FILE}" | xargs)
        if [ -n "${FILE_KEY}" ]; then
            API_KEY="${FILE_KEY}"
            info "Loaded API key from: ${ENV_FILE}"
        fi
    fi
fi

# 3. If still empty, prompt interactively
if [ -z "${API_KEY}" ]; then
    warn "API key file '${ENV_FILE}' not found or empty, and no key passed."
    echo ""
    echo -e "  ${CYAN}Instance API Key${RESET} (input hidden):"
    read -rsp "  > " API_KEY
    echo ""
    if [ -z "${API_KEY}" ]; then
        error "API Key cannot be empty."
        exit 1
    fi
    # Write prompted key to apikey.env for future runs
    echo -n "${API_KEY}" > "${ENV_FILE}"
    chmod 600 "${ENV_FILE}" 2>/dev/null || true
    info "Saved API key to: ${ENV_FILE}"

    echo -n "${API_KEY}" > ../2-webmethods-api-exposure/apikey.env
    chmod 600 "${ENV_FILE}" 2>/dev/null || true
    info "Saved API key to: ${ENV_FILE}"
fi

export WM_API_KEY="${API_KEY}"
export WM_TENANT="${TENANT_HOST}"
success "Loaded and exported WM_API_KEY"

# Build common flags
COMMON_FLAGS=("-t" "${TENANT_HOST}")
if [ "${VERBOSE}" = true ]; then
    COMMON_FLAGS+=("-v")
fi

# ── Step 2: Create Project ────────────────────────────────────────────────────
step "2" "Create Project '${PROJECT_NAME}'"

CREATE_FLAGS=("${COMMON_FLAGS[@]}" "-p" "${PROJECT_NAME}")
if [ -n "${PROJECT_DESC}" ]; then
    CREATE_FLAGS+=("-d" "${PROJECT_DESC}")
fi

if ! bash "${SCRIPT_DIR}/create-project.sh" "${CREATE_FLAGS[@]}"; then
    error "Step 2 failed: Unable to create project '${PROJECT_NAME}'."
    exit 1
fi
success "Project '${PROJECT_NAME}' created successfully."

# ── Step 3: Import Flows ──────────────────────────────────────────────────────
step "3" "Import Flow Services from '${ZIP_DIR}'"

IMPORT_FLAGS=("${COMMON_FLAGS[@]}" "-p" "${PROJECT_NAME}")
if [ "${AUTO_CONFIRM}" = true ]; then
    IMPORT_FLAGS+=("-y")
fi

if ! bash "${SCRIPT_DIR}/import-flows.sh" "${IMPORT_FLAGS[@]}" "${ZIP_DIR}"; then
    error "Step 3 failed: Flow services import encountered errors."
    exit 1
fi
success "Flow services imported successfully."

# ── Step 4: Sync Vault Variable ───────────────────────────────────────────────
step "4" "Sync Vault Variable '${VAR_NAME}' to Project '${PROJECT_NAME}'"

SYNC_FLAGS=("${COMMON_FLAGS[@]}" "-p" "${PROJECT_NAME}" "-n" "${VAR_NAME}")

if ! bash "${SCRIPT_DIR}/sync-vault-variables.sh" "${SYNC_FLAGS[@]}"; then
    error "Step 4 failed: Unable to synchronize vault variable '${VAR_NAME}'."
    exit 1
fi
success "Vault variable '${VAR_NAME}' synchronized successfully."

# ── Step 5: Customize API Spec ────────────────────────────────────────────────
step "5" "Customize API Specification (replace STUDENTID with '${CURRENT_USER}')"

SPEC_TEMPLATE="${SCRIPT_DIR}/STUDENTID_CruiseAPI-oas3.json"
if [ -f "${SPEC_TEMPLATE}" ]; then
    if ! bash "${SCRIPT_DIR}/customize-api-spec.sh" -u "${CURRENT_USER}" -f "${SPEC_TEMPLATE}"; then
        error "Step 5 failed: Unable to customize OpenAPI spec file."
        exit 1
    fi
    success "API specification customized successfully."
else
    warn "Template '${SPEC_TEMPLATE}' not found; skipping Step 5."
fi

# ── Completion ────────────────────────────────────────────────────────────────
divider
echo -e "${GREEN}${BOLD}✔ Full setup completed successfully!${RESET}"
divider

