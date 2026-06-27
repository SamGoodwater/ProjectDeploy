#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
load_plan "$PLAN_FILE"
require_root
init_logging

run_as="${WSL_USER:-root}"
mgr="$(plan_package_option nodejs manager "pnpm")"
ensure_project_dir "$PROJECT_PATH"

info "Initialisation Nuxt dans ${PROJECT_PATH}..."

parent_dir="$(dirname "$PROJECT_PATH")"
project_dir="$(basename "$PROJECT_PATH")"

run_cmd() {
    run_as_user "$run_as" "
        export PATH=\"/home/${WSL_USER}/.local/share/fnm:\$PATH\"
        eval \"\$(fnm env --shell bash 2>/dev/null)\" || true
        $*
    "
}

if $NON_INTERACTIVE; then
    run_cmd "cd '${parent_dir}' && ${mgr} create nuxt@latest '${project_dir}' --force --no-git --packageManager ${mgr}"
else
    warn "Mode interactif : pnpm create nuxt peut poser des questions"
    run_cmd "cd '${parent_dir}' && ${mgr} dlx nuxi@latest init '${project_dir}'"
fi

if [[ -d "${PROJECT_PATH}" ]]; then
    run_cmd "cd '${PROJECT_PATH}' && ${mgr} install" || warn "pnpm install échoué"
fi

chown -R "${run_as}:${run_as}" "$PROJECT_PATH"

setup_github_repo "$PROJECT_PATH"
ok "Nuxt initialisé"
