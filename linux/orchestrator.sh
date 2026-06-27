#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/plan.sh
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
[[ -n "$PLAN_FILE" ]] || die "Usage: $0 --plan PATH [--non-interactive]"
load_plan "$PLAN_FILE"
require_root
init_logging

info "ProjectDeploy — orchestrateur Linux"
info "Projet : ${PROJECT_NAME} → ${PROJECT_PATH}"

apt_update
apt_upgrade

while IFS= read -r pkg_id; do
    [[ -n "$pkg_id" ]] || continue
    script="${SCRIPT_DIR}/packages/install-${pkg_id}.sh"
    if [[ ! -f "$script" ]]; then
        warn "Script paquet introuvable pour '$pkg_id' : $script"
        continue
    fi
    info "=== Paquet : ${pkg_id} ==="
    chmod +x "$script"
    bash "$script" --plan "$PLAN_FILE" $(${NON_INTERACTIVE} && echo --non-interactive)
done < <(plan_list_package_ids)

while IFS= read -r tpl_id; do
    [[ -n "$tpl_id" ]] || continue
    script="${SCRIPT_DIR}/templates/init-${tpl_id}.sh"
    if [[ ! -f "$script" ]]; then
        warn "Script template introuvable pour '$tpl_id' : $script"
        continue
    fi
    info "=== Template : ${tpl_id} ==="
    chmod +x "$script"
    bash "$script" --plan "$PLAN_FILE" $(${NON_INTERACTIVE} && echo --non-interactive)
done < <(plan_list_template_ids)

save_state "PROJECT_NAME" "$PROJECT_NAME"
save_state "PROJECT_PATH" "$PROJECT_PATH"
save_state "WSL_USER" "$WSL_USER"
write_summary

ok "Orchestration Linux terminée"
