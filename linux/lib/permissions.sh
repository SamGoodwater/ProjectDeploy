#!/usr/bin/env bash
# Permissions et propriété des fichiers

set -euo pipefail

setup_permissions() {
    case "${PROJECT_TYPE:-}" in
        web)    setup_web_permissions ;;
        python) setup_python_permissions ;;
    esac
}

setup_web_permissions() {
    [[ -d "${PROJECT_PATH}" ]] || return 0

    info "Configuration des permissions web..."

    # Créer /var/www si nécessaire
    if [[ "${PROJECT_PATH}" == /var/www/* ]]; then
        mkdir -p /var/www
    fi

    # Ajouter l'utilisateur au groupe www-data
    usermod -aG www-data "${WSL_USER}" 2>/dev/null || true

    chown -R "${WSL_USER}:www-data" "${PROJECT_PATH}"

    find "${PROJECT_PATH}" -type d -exec chmod 775 {} \;
    find "${PROJECT_PATH}" -type f -exec chmod 664 {} \;

    # Laravel / Symfony storage
    if [[ -d "${PROJECT_PATH}/storage" ]]; then
        chmod -R 775 "${PROJECT_PATH}/storage"
    fi
    if [[ -d "${PROJECT_PATH}/bootstrap/cache" ]]; then
        chmod -R 775 "${PROJECT_PATH}/bootstrap/cache"
    fi

    ok "Permissions configurées (${WSL_USER}:www-data)"
}

setup_python_permissions() {
    [[ -d "${PROJECT_PATH}" ]] || return 0

    info "Configuration des permissions Python..."
    chown -R "${WSL_USER}:${WSL_USER}" "${PROJECT_PATH}"
    chmod -R 755 "${PROJECT_PATH}"
    ok "Permissions configurées (${WSL_USER})"
}
