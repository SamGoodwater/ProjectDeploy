#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
load_plan "$PLAN_FILE"
require_root

if command_exists python3; then
    ok "Python déjà disponible ($(python3 --version))"
    exit 0
fi

ver="$(plan_package_option python version "system")"
info "Installation de Python..."
apt_install python3 python3-pip python3-venv python3-dev pipx
pipx ensurepath 2>/dev/null || true
ok "Python $(python3 --version) installé"
