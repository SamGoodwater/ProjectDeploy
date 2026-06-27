#!/usr/bin/env bash
# WSL Project Init — Bootstrap Linux
# Provisionne Debian : utilisateur, stack web/python, BDD, git, permissions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Charger les bibliothèques
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/prompts.sh
source "${SCRIPT_DIR}/lib/prompts.sh"
# shellcheck source=lib/database.sh
source "${SCRIPT_DIR}/lib/database.sh"
# shellcheck source=lib/web.sh
source "${SCRIPT_DIR}/lib/web.sh"
# shellcheck source=lib/python.sh
source "${SCRIPT_DIR}/lib/python.sh"
# shellcheck source=lib/permissions.sh
source "${SCRIPT_DIR}/lib/permissions.sh"
# shellcheck source=lib/apache.sh
source "${SCRIPT_DIR}/lib/apache.sh"
# shellcheck source=lib/github.sh
source "${SCRIPT_DIR}/lib/github.sh"

main() {
    init_logging
    load_defaults
    parse_args "$@"

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║     WSL Project Init — Bootstrap         ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    # --- Phase 1 : Questionnaire ---
    if $NON_INTERACTIVE; then
        [[ -n "${PROFILE:-}" ]] && load_profile "$PROFILE"
        validate_config
    else
        run_prompts
    fi

    info "Projet : ${PROJECT_NAME} (${PROJECT_TYPE}) → ${PROJECT_PATH}"

    if $DRY_RUN; then
        show_dry_run_plan
        ok "Dry-run terminé — aucune modification appliquée"
        exit 0
    fi

    # --- Phase 2 : Système de base (root requis) ---
    require_root

    apt_update
    apt_upgrade
    install_base_packages
    configure_locale_timezone

    # --- Phase 3 : Utilisateur Debian ---
    if ! $SKIP_WSL_USER_SETUP; then
        create_debian_user "${WSL_USER}"
        configure_wsl_conf "${WSL_USER}"
    fi

    # --- Phase 4 : Stack technique ---
    case "${PROJECT_TYPE}" in
        web)
            install_web_stack
            install_mkcert
            ;;
        python)
            install_python_stack
            ;;
    esac

    # --- Phase 5 : Base de données & services ---
    install_database
    install_redis

    # --- Phase 6 : Permissions & serveur web ---
    setup_permissions

    case "${WEB_SERVER:-apache}" in
        apache) configure_apache_vhost ;;
        nginx)  configure_nginx_vhost ;;
    esac

    # --- Phase 7 : Git & GitHub ---
    setup_ssh_key
    setup_git
    generate_readme

    # --- Phase 8 : Sauvegarde config & récap ---
    save_state "PROJECT_NAME" "$PROJECT_NAME"
    save_state "PROJECT_TYPE" "$PROJECT_TYPE"
    save_state "PROJECT_PATH" "$PROJECT_PATH"
    save_state "WSL_USER" "$WSL_USER"

    echo ""
    write_summary

    ok "Bootstrap terminé avec succès !"
    warn "Si systemd vient d'être activé, exécutez 'wsl --shutdown' depuis PowerShell puis relancez la WSL."
}

main "$@"
