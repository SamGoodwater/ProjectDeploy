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
parent_dir="$(dirname "$PROJECT_PATH")"
project_dir="$(basename "$PROJECT_PATH")"
domain="${PROJECT_DOMAIN:-${PROJECT_SLUG}.local}"
php_ver="$(plan_package_option php version "8.3")"

ensure_project_dir "$PROJECT_PATH"

info "Initialisation Laravel dans ${PROJECT_PATH}..."

if $NON_INTERACTIVE; then
    run_as_user "$run_as" "
        cd '${parent_dir}'
        composer create-project laravel/laravel '${project_dir}' --prefer-dist --no-interaction
    "
else
    warn "Mode interactif : composer peut poser des questions"
    run_as_user "$run_as" "
        cd '${parent_dir}'
        composer create-project laravel/laravel '${project_dir}' --prefer-dist
    "
fi

if plan_has_package "postgresql" && [[ -f "${STATE_DIR}/state.env" ]]; then
    # shellcheck source=/dev/null
    source "${STATE_DIR}/state.env" 2>/dev/null || true
    if [[ -n "${DB_NAME:-}" ]]; then
        env_file="${PROJECT_PATH}/.env"
        if [[ -f "$env_file" ]]; then
            sed -i "s/DB_CONNECTION=.*/DB_CONNECTION=pgsql/" "$env_file"
            sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/" "$env_file"
            sed -i "s/DB_PORT=.*/DB_PORT=5432/" "$env_file"
            sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" "$env_file"
            sed -i "s/DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" "$env_file"
            sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" "$env_file"
            run_as_user "$run_as" "cd '${PROJECT_PATH}' && php artisan key:generate --force"
        fi
    fi
fi

if plan_has_package "nodejs"; then
    mgr="$(plan_package_option nodejs manager "pnpm")"
    run_as_user "$run_as" "
        export PATH=\"/home/${WSL_USER}/.local/share/fnm:\$PATH\"
        eval \"\$(fnm env --shell bash 2>/dev/null)\" || true
        cd '${PROJECT_PATH}'
        ${mgr} install
    " || warn "Installation des assets Node échouée"
fi

chown -R "${run_as}:www-data" "$PROJECT_PATH" 2>/dev/null || chown -R "${run_as}:${run_as}" "$PROJECT_PATH"
find "$PROJECT_PATH" -type d -exec chmod 775 {} \;
find "$PROJECT_PATH" -type f -exec chmod 664 {} \;

if plan_has_package "apache"; then
    vhost="/etc/apache2/sites-available/${PROJECT_SLUG}.conf"
    cat > "$vhost" <<VHOST
<VirtualHost *:80>
    ServerName ${domain}
    DocumentRoot ${PROJECT_PATH}/public

    <Directory ${PROJECT_PATH}/public>
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \\.php\$>
        SetHandler "proxy:unix:/run/php/php${php_ver}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/${PROJECT_SLUG}-error.log
    CustomLog \${APACHE_LOG_DIR}/${PROJECT_SLUG}-access.log combined
</VirtualHost>
VHOST
    a2ensite "${PROJECT_SLUG}.conf" 2>/dev/null || true
    a2dissite 000-default.conf 2>/dev/null || true
    systemctl reload apache2
    ok "Vhost Apache configuré : http://${domain}"
fi

setup_github_repo "$PROJECT_PATH"
ok "Laravel initialisé"
