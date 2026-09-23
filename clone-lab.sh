#!/usr/bin/env bash
# =============================================================================
# clone-lab.sh
# Clones the TechXchangeLab4110 repository for TechXchange 2026 Lab 4110.
#
# Usage:
#   bash clone-lab.sh [target-directory]
#
# If no target directory is specified the repo is cloned into a folder called
# TechXchangeLab4110 inside your current working directory.
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Config ────────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/dave-pemberton-ibm/TechXchangeLab4110.git"
REPO_NAME="TechXchangeLab4110"
TARGET_DIR="${1:-${REPO_NAME}}"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  TechXchange 2026 — Lab 4110  •  Repository Setup${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""
info "Repository : ${REPO_URL}"
info "Destination: ${TARGET_DIR}"
echo ""

# ── Pre-flight: check git is available ───────────────────────────────────────
info "Checking that git is installed..."
if ! command -v git &>/dev/null; then
    error "git is not installed or not on your PATH."
    error "Please install git and re-run this script."
    error "  • macOS  : xcode-select --install"
    error "  • Ubuntu : sudo apt install git"
    error "  • Windows: https://git-scm.com/download/win"
    exit 1
fi

GIT_VERSION=$(git --version)
success "Found: ${GIT_VERSION}"
echo ""

# ── Check the target directory doesn't already exist ─────────────────────────
if [ -d "${TARGET_DIR}" ]; then
    warn "The directory '${TARGET_DIR}' already exists."
    warn "To avoid overwriting your work this script will not clone into it."
    warn "Options:"
    warn "  • Delete or rename '${TARGET_DIR}' and re-run this script."
    warn "  • Run:  bash clone-lab.sh my-new-folder-name"
    echo ""
    exit 1
fi

# ── Clone ─────────────────────────────────────────────────────────────────────
info "Starting clone — this may take a few seconds depending on your connection..."
echo ""

# Run git clone with verbose progress so students can see activity
if git clone --progress "${REPO_URL}" "${TARGET_DIR}" 2>&1; then
    echo ""
    success "Repository cloned successfully!"
else
    echo ""
    error "Clone failed. Common reasons:"
    error "  • No internet connection."
    error "  • A firewall or proxy is blocking GitHub."
    error "  • The repository URL has changed."
    error "Please check the above and try again, or ask your lab instructor for help."
    exit 1
fi
# ── Create API Studio project directory based on hostname ────────────────────
USERNAME=$(whoami)
API_STUDIO_DIR="${USERNAME}_APIStudioProject"

#HOSTNAME_SHORT=$(hostname -s)
#API_STUDIO_DIR="${HOSTNAME_SHORT}_APIStudioProject"
 
info "Creating API Studio project directory: ${API_STUDIO_DIR}"
 
mkdir -p "${TARGET_DIR}/${API_STUDIO_DIR}"
 
success "Created: ${TARGET_DIR}/${API_STUDIO_DIR}"


# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}------------------------------------------------------------${RESET}"
success "All done! Your lab files are in: ${BOLD}$(pwd)/${TARGET_DIR}${RESET}"
info "API Studio project folder: ${CYAN}${API_STUDIO_DIR}${RESET}"
echo ""
info "Next steps:"
echo -e "  1.  ${CYAN}cd ${TARGET_DIR}${RESET}   — move into your new lab folder"
echo -e "  2.  Open the folder in your editor or platform workspace"
echo -e "  3.  Follow the lab instructions in ${CYAN}README.md${RESET}"
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "  Good luck and enjoy the lab!"
echo -e "${BOLD}============================================================${RESET}"
echo ""
