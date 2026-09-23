#!/usr/bin/env bash
# =============================================================================
# convert-api-spec.sh
# Converts a Swagger 2.0 (OAS2) spec file to OpenAPI 3.0 (OAS3) using the
# swagger2openapi tool.
#
# Usage:
#   bash convert-api-spec.sh [OPTIONS] <input-file>
#
# Options:
#   -o, --output  <file>    Output filename (default: <input-basename>-oas3.<ext>)
#   -y, --yaml              Force YAML output (default: match input format)
#   -j, --json              Force JSON output
#   -p, --patch             Auto-fix minor errors in the source spec
#   -r, --resolve           Resolve external $ref references
#   -v, --verbose           Show detailed conversion output
#   -h, --help              Show this help message
#
# Examples:
#   bash convert-api-spec.sh my-api.yaml
#   bash convert-api-spec.sh my-api.json --output my-api-v3.json
#   bash convert-api-spec.sh my-api.yaml --yaml --patch
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
detail()  { if [ "${VERBOSE}" = true ]; then echo -e "${MAGENTA}[VERBOSE]${RESET} $*"; fi; }
divider() { echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
INPUT_FILE=""
OUTPUT_FILE=""
FORCE_YAML=false
FORCE_JSON=false
PATCH=false
RESOLVE=false
VERBOSE=false

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}Usage:${RESET} bash convert-api-spec.sh [OPTIONS] <input-file>"
    echo ""
    echo "Options:"
    echo "  -o, --output  <file>    Output filename (default: <input-basename>-oas3.<ext>)"
    echo "  -y, --yaml              Force YAML output"
    echo "  -j, --json              Force JSON output"
    echo "  -p, --patch             Auto-fix minor errors in the source spec"
    echo "  -r, --resolve           Resolve external \$ref references"
    echo "  -v, --verbose           Show detailed conversion output"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  bash convert-api-spec.sh my-api.yaml"
    echo "  bash convert-api-spec.sh my-api.json -o my-api-v3.json"
    echo "  bash convert-api-spec.sh my-api.yaml --yaml --patch --resolve"
    echo ""
}

# ── Argument parsing ──────────────────────────────────────────────────────────
if [ $# -eq 0 ]; then
    error "No input file specified."
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            OUTPUT_FILE="${2:-}"
            shift 2
            ;;
        -y|--yaml)
            FORCE_YAML=true
            shift
            ;;
        -j|--json)
            FORCE_JSON=true
            shift
            ;;
        -p|--patch)
            PATCH=true
            shift
            ;;
        -r|--resolve)
            RESOLVE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "${INPUT_FILE}" ]]; then
                INPUT_FILE="$1"
            else
                error "Unexpected argument: $1"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  API Spec Converter — Swagger 2.0 → OpenAPI 3.0${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

# ── Pre-flight: check swagger2openapi ────────────────────────────────────────
info "Checking dependencies..."

if command -v swagger2openapi &>/dev/null; then
    S2O_CMD="swagger2openapi"
    success "swagger2openapi : $(swagger2openapi --version 2>&1 | head -1)"
elif command -v npx &>/dev/null; then
    # Fallback: use npx to run it without a global install
    S2O_CMD="npx --yes swagger2openapi"
    success "swagger2openapi : will use npx (not globally installed)"
else
    error "swagger2openapi is not installed and npx is not available."
    error "Install one of the following:"
    error "  • npm install -g swagger2openapi"
    error "  • npm install -g npx  (then re-run)"
    exit 1
fi
echo ""

# ── Validate input file ───────────────────────────────────────────────────────
if [[ -z "${INPUT_FILE}" ]]; then
    error "No input file specified."
    usage
    exit 1
fi

if [ ! -f "${INPUT_FILE}" ]; then
    error "Input file not found: ${INPUT_FILE}"
    exit 1
fi

# Detect input format from extension
INPUT_EXT="${INPUT_FILE##*.}"
INPUT_EXT_LOWER=$(echo "${INPUT_EXT}" | tr '[:upper:]' '[:lower:]')

if [[ "${INPUT_EXT_LOWER}" != "yaml" && "${INPUT_EXT_LOWER}" != "yml" && "${INPUT_EXT_LOWER}" != "json" ]]; then
    warn "Unrecognised file extension '.${INPUT_EXT}' — expected .yaml, .yml, or .json"
fi

# Check it looks like a Swagger 2.0 document
SWAGGER_VERSION=$(grep -m1 '"swagger"\s*:\s*"2\.' "${INPUT_FILE}" 2>/dev/null || \
                  grep -m1 '^swagger:\s*["\x27]\?2\.' "${INPUT_FILE}" 2>/dev/null || true)

if [[ -z "${SWAGGER_VERSION}" ]]; then
    warn "Could not confirm this is a Swagger 2.0 document — proceeding anyway."
    warn "If conversion fails, check the file contains 'swagger: \"2.0\"'."
else
    success "Detected Swagger 2.0 spec"
fi
echo ""

# ── Derive output filename ────────────────────────────────────────────────────
if [[ -z "${OUTPUT_FILE}" ]]; then
    INPUT_BASENAME="${INPUT_FILE%.*}"
    if [ "${FORCE_JSON}" = true ]; then
        OUTPUT_EXT="json"
    elif [ "${FORCE_YAML}" = true ]; then
        OUTPUT_EXT="yaml"
    else
        # Match input format
        OUTPUT_EXT="${INPUT_EXT_LOWER}"
    fi
    OUTPUT_FILE="${INPUT_BASENAME}-oas3.${OUTPUT_EXT}"
fi

# Warn if output file already exists
if [ -f "${OUTPUT_FILE}" ]; then
    warn "Output file already exists and will be overwritten: ${OUTPUT_FILE}"
fi

# Determine output format flags for swagger2openapi
FORMAT_FLAGS=()
OUT_LOWER="${OUTPUT_FILE##*.}"
OUT_LOWER=$(echo "${OUT_LOWER}" | tr '[:upper:]' '[:lower:]')
if [[ "${OUT_LOWER}" == "yaml" || "${OUT_LOWER}" == "yml" || "${FORCE_YAML}" = true ]]; then
    FORMAT_FLAGS+=("--yaml")
fi

# Build full swagger2openapi command flags
S2O_FLAGS=("--outfile" "${OUTPUT_FILE}")
[ "${PATCH}" = true ]   && S2O_FLAGS+=("--patch")
[ "${RESOLVE}" = true ] && S2O_FLAGS+=("--resolve")
[ "${VERBOSE}" = true ] && S2O_FLAGS+=("--verbose")
S2O_FLAGS+=("${FORMAT_FLAGS[@]+"${FORMAT_FLAGS[@]}"}")

INPUT_SIZE=$(du -sh "${INPUT_FILE}" | cut -f1)

# ── Summary ───────────────────────────────────────────────────────────────────
divider
echo ""
info "Input    : ${BOLD}${INPUT_FILE}${RESET} (${INPUT_SIZE})"
info "Output   : ${BOLD}${OUTPUT_FILE}${RESET}"
info "Patch    : ${BOLD}${PATCH}${RESET}"
info "Resolve  : ${BOLD}${RESOLVE}${RESET}"
info "Verbose  : ${BOLD}${VERBOSE}${RESET}"
echo ""

if [ "${VERBOSE}" = true ]; then
    detail "Command  : ${S2O_CMD} ${S2O_FLAGS[*]} ${INPUT_FILE}"
    echo ""
fi

# ── Run conversion ────────────────────────────────────────────────────────────
divider
echo ""
info "Converting spec..."
echo ""

CONVERT_LOG=$(mktemp)
CONVERT_EXIT=0

if ${S2O_CMD} "${S2O_FLAGS[@]}" "${INPUT_FILE}" >"${CONVERT_LOG}" 2>&1; then
    CONVERT_EXIT=0
else
    CONVERT_EXIT=$?
fi

# Always show conversion output in verbose mode; in normal mode only on failure
if [ "${VERBOSE}" = true ] || [ "${CONVERT_EXIT}" -ne 0 ]; then
    if [ -s "${CONVERT_LOG}" ]; then
        cat "${CONVERT_LOG}" | sed 's/^/    /'
        echo ""
    fi
fi
rm -f "${CONVERT_LOG}"

if [ "${CONVERT_EXIT}" -ne 0 ]; then
    error "Conversion failed (exit code ${CONVERT_EXIT})"
    echo ""
    warn "Common causes:"
    warn "  • Input file is not valid Swagger 2.0 JSON/YAML"
    warn "  • Unresolvable \$ref references — try --resolve"
    warn "  • Structural errors in the spec — try --patch to auto-fix minor issues"
    exit 1
fi

# ── Validate output ───────────────────────────────────────────────────────────
if [ ! -f "${OUTPUT_FILE}" ] || [ ! -s "${OUTPUT_FILE}" ]; then
    error "Output file is missing or empty: ${OUTPUT_FILE}"
    exit 1
fi

OUTPUT_SIZE=$(du -sh "${OUTPUT_FILE}" | cut -f1)

# Verify the output declares openapi: 3.x
OAS3_VERSION=$(grep -m1 '"openapi"\s*:\s*"3\.' "${OUTPUT_FILE}" 2>/dev/null || \
               grep -m1 '^openapi:\s*["\x27]\?3\.' "${OUTPUT_FILE}" 2>/dev/null || true)

echo ""
success "Conversion complete!"
echo ""
echo -e "    Input  : ${INPUT_FILE} (${INPUT_SIZE})"
echo -e "    Output : ${BOLD}${OUTPUT_FILE}${RESET} (${OUTPUT_SIZE})"

if [[ -n "${OAS3_VERSION}" ]]; then
    echo -e "    Version: ${GREEN}${OAS3_VERSION// /}${RESET}"
fi

echo ""

# Show warning count if any x-s2o-warning extensions are present in output
if command -v grep &>/dev/null; then
    WARN_COUNT=$(grep -c "x-s2o-warning" "${OUTPUT_FILE}" 2>/dev/null || true)
    if [ "${WARN_COUNT}" -gt 0 ]; then
        warn "${WARN_COUNT} conversion warning(s) embedded in the output as 'x-s2o-warning' extensions."
        warn "Search for 'x-s2o-warning' in ${OUTPUT_FILE} to review them."
    fi
fi

echo -e "${BOLD}============================================================${RESET}"
echo -e "  Done."
echo -e "${BOLD}============================================================${RESET}"
echo ""
