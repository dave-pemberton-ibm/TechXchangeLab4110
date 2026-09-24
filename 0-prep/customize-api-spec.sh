#!/usr/bin/env bash
# =============================================================================
# customize-api-spec.sh
# Replaces 'STUDENTID' with the Linux username (or a supplied username) both
# inside the OpenAPI spec content and by renaming/copying the file.
#
# Usage:
#   bash customize-api-spec.sh [OPTIONS] [spec-file]
#
# Options:
#   -u, --username <name>   Username to replace STUDENTID with
#                           (default: current Linux username)
#   -f, --file     <path>   Path to template spec file
#                           (default: ./STUDENTID_CruiseAPI-oas3.json)
#   -o, --output   <path>   Explicit output file path (optional)
#   -h, --help              Show this help message
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER="$(whoami 2>/dev/null || echo "${USER:-user}")"

SPEC_FILE="${SCRIPT_DIR}/STUDENTID_CruiseAPI-oas3.json"
USERNAME="${CURRENT_USER}"
OUTPUT_FILE=""

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--username)
            USERNAME="${2:-}"
            shift 2
            ;;
        -f|--file)
            SPEC_FILE="${2:-}"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="${2:-}"
            shift 2
            ;;
        -h|--help)
            echo ""
            echo "Usage: bash customize-api-spec.sh [OPTIONS] [spec-file]"
            echo ""
            echo "Options:"
            echo "  -u, --username <name>   Username to replace STUDENTID with"
            echo "                          (default: ${CURRENT_USER})"
            echo "  -f, --file     <path>   Path to template spec file"
            echo "                          (default: ./STUDENTID_CruiseAPI-oas3.json)"
            echo "  -o, --output   <path>   Explicit output file path (optional)"
            echo "  -h, --help              Show this help message"
            echo ""
            exit 0
            ;;
        *)
            SPEC_FILE="$1"
            shift
            ;;
    esac
done

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
CYAN="\033[0;36m"
RED="\033[0;31m"
BOLD="\033[1m"
RESET="\033[0m"

info()    { echo -e "${CYAN}[INFO]${RESET}    $*"; }
success() { echo -e "${GREEN}[OK]${RESET}      $*"; }
error()   { echo -e "${RED}[ERROR]${RESET}   $*" >&2; }

# ── Validation ────────────────────────────────────────────────────────────────
if [ ! -f "${SPEC_FILE}" ]; then
    error "Template spec file not found: ${SPEC_FILE}"
    exit 1
fi

SPEC_DIR="$(cd "$(dirname "${SPEC_FILE}")" && pwd)"
SPEC_BASENAME="$(basename "${SPEC_FILE}")"

if [ -z "${OUTPUT_FILE}" ]; then
    NEW_BASENAME="${SPEC_BASENAME//STUDENTID/${USERNAME}}"
    OUTPUT_FILE="${SPEC_DIR}/${NEW_BASENAME}"
fi

info "Source template : ${SPEC_FILE}"
info "Target output   : ${OUTPUT_FILE}"
info "Target username : ${USERNAME}"

# Replace STUDENTID in content and write to output file
sed "s/STUDENTID/${USERNAME}/g" "${SPEC_FILE}" > "${OUTPUT_FILE}"
mv ${OUTPUT_FILE} ../
success "Customized API spec created: ${OUTPUT_FILE}"

