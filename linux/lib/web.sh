#!/usr/bin/env bash
# Stack web : Apache/Nginx, PHP, Composer, Node, frameworks

set -euo pipefail

install_web_stack() {
    install_web_server
    $INSTALL_PHP && install_php
    $INSTALL_NODE && install_node
    init_web_project
}

install_web_server() {
    case "${WEB_SERVER:-apache}" in
        apache) install_apache ;;
        nginx)  install_nginx ;;
        *)      warn "Serveur web inconnu : $WEB_SERVER" ;;
    esac
}

install_apache() {
    info "Installation d'Apache..."
    apt_install apache2 libapache2-mod-rewrite

    a2enmod rewrite headers ssl 2>/dev/null || true
    if $INSTALL_PHP; then
        a2enmod proxy_fcgi setenvif 2>/dev/null || true
    fi

    systemctl enable apache2
    systemctl start apache2
    ok "Apache installé"
}

install_nginx() {
    info "Installation de Nginx..."
    apt_install nginx
    systemctl enable nginx
    systemctl start nginx
    ok "Nginx installé"
}

install_php() {
    local ver="${PHP_VERSION:-8.3}"
    info "Installation de PHP ${ver}..."

    apt_install \
        "php${ver}" "php${ver}-cli" "php${ver}-fpm" \
        "php${ver}-mbstring" "php${ver}-xml" "php${ver}-curl" \
        "php${ver}-zip" "php${ver}-bcmath" "php${ver}-intl" \
        "php${ver}-gd" "php${ver}-sqlite3"

    case "${DB_TYPE:-none}" in
        postgresql) apt_install "php${ver}-pgsql" ;;
        mysql)      apt_install "php${ver}-mysql" ;;
    esac

    $INSTALL_XDEBUG && apt_install "php${ver}-xdebug"

    update-alternatives --set php "/usr/bin/php${ver}" 2>/dev/null || true

    systemctl enable "php${ver}-fpm"
    systemctl start "php${ver}-fpm"

    install_composer
    ok "PHP ${ver} installé"
}

install_composer() {
    if command_exists composer; then
        ok "Composer déjà installé"
        return 0
    fi

    info "Installation de Composer..."
    curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    chmod +x /usr/local/bin/composer
    ok "Composer installé"
}

install_node() {
    info "Installation de Node.js via fnm..."

    if ! command_exists fnm; then
        curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
        export PATH="${HOME}/.local/share/fnm:${PATH}"
        eval "$(fnm env --shell bash 2>/dev/null)" || true
    fi

    # Installer aussi pour l'utilisateur cible
    local fnm_install_script="/tmp/fnm-install.sh"
    curl -fsSL https://fnm.vercel.app/install -o "$fnm_install_script"
    bash "$fnm_install_script" --skip-shell

    export PATH="/root/.local/share/fnm:${PATH}"
    eval "$(/root/.local/share/fnm/fnm env --shell bash 2>/dev/null)" || true

    fnm install --lts
    fnm default lts-latest

    eval "$(fnm env --shell bash)"
    ok "Node.js $(node --version) installé"

    case "${NODE_MANAGER:-pnpm}" in
        pnpm)
            corepack enable 2>/dev/null || npm install -g pnpm
            ok "pnpm $(pnpm --version 2>/dev/null || echo 'installé') activé"
            ;;
        yarn)
            corepack enable 2>/dev/null || npm install -g yarn
            ok "yarn activé"
            ;;
        npm)
            ok "npm $(npm --version) disponible"
            ;;
    esac

    # Propager fnm dans le .bashrc de l'utilisateur
    if [[ -n "${WSL_USER:-}" ]] && id "$WSL_USER" &>/dev/null; then
        local bashrc="/home/${WSL_USER}/.bashrc"
        if ! grep -q 'fnm env' "$bashrc" 2>/dev/null; then
            cat >> "$bashrc" <<'FNM'

# fnm (Node version manager)
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --shell bash 2>/dev/null)"
FNM
        fi
    fi
}

init_web_project() {
    info "Initialisation du projet web dans ${PROJECT_PATH}..."
    ensure_project_dir "$PROJECT_PATH"

    case "${PHP_FRAMEWORK:-vanilla}" in
        laravel)  init_laravel ;;
        symfony)  init_symfony ;;
        wordpress) init_wordpress ;;
        *)        init_vanilla_php ;;
    esac

    ok "Projet web initialisé"
}

init_laravel() {
    local run_as="root"
    [[ -n "${WSL_USER:-}" ]] && run_as="$WSL_USER"

    sudo -u "$run_as" bash -c "
        cd '$(dirname "$PROJECT_PATH")'
        composer create-project laravel/laravel '$(basename "$PROJECT_PATH")' --prefer-dist --no-interaction
    "

    if [[ "${DB_TYPE:-none}" == "postgresql" ]]; then
        render_template "${REPO_ROOT}/linux/templates/env.example.laravel" "${PROJECT_PATH}/.env"
        sudo -u "$run_as" bash -c "cd '$PROJECT_PATH' && php artisan key:generate --force"
    fi

    $INSTALL_NODE && sudo -u "$run_as" bash -c "
        export PATH=\"/home/${WSL_USER}/.local/share/fnm:\$PATH\"
        eval \"\$(fnm env --shell bash 2>/dev/null)\" || true
        cd '$PROJECT_PATH'
        ${NODE_MANAGER:-pnpm} install
    "
}

init_symfony() {
    local run_as="${WSL_USER:-root}"
    sudo -u "$run_as" bash -c "
        cd '$(dirname "$PROJECT_PATH")'
        composer create-project symfony/skeleton '$(basename "$PROJECT_PATH")' --no-interaction
    "
    sudo -u "$run_as" bash -c "cd '$PROJECT_PATH' && composer require webapp --no-interaction" || true
}

init_wordpress() {
    local run_as="${WSL_USER:-root}"
    sudo -u "$run_as" bash -c "
        mkdir -p '$PROJECT_PATH'
        cd '$PROJECT_PATH'
        curl -fsSL https://wordpress.org/latest.tar.gz | tar -xz --strip-components=1
    "
    DOCUMENT_ROOT="$PROJECT_PATH"
}

init_vanilla_php() {
    local run_as="${WSL_USER:-root}"
    sudo -u "$run_as" bash -c "
        mkdir -p '${PROJECT_PATH}/public' '${PROJECT_PATH}/src'
        cat > '${PROJECT_PATH}/public/index.php' <<'PHP'
<?php
declare(strict_types=1);
echo '<h1>${PROJECT_NAME}</h1>';
echo '<p>Projet PHP vanilla — prêt.</p>';
PHP
        cat > '${PROJECT_PATH}/composer.json' <<'JSON'
{
    \"name\": \"app/${PROJECT_SLUG}\",
    \"description\": \"${PROJECT_NAME}\",
    \"type\": \"project\",
    \"require\": {
        \"php\": \"^8.2\"
    },
    \"autoload\": {
        \"psr-4\": {
            \"App\\\\\": \"src/\"
        }
    }
}
JSON
        cd '${PROJECT_PATH}' && composer install --no-interaction 2>/dev/null || true
    "
    DOCUMENT_ROOT="${PROJECT_PATH}/public"
}

install_mkcert() {
    $INSTALL_SSL_LOCAL || return 0

    info "Installation de mkcert..."
    apt_install libnss3-tools
    if ! command_exists mkcert; then
        curl -fsSL -o /usr/local/bin/mkcert \
            "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
        chmod +x /usr/local/bin/mkcert
    fi
    mkcert -install
    local cert_dir="${PROJECT_PATH}/certs"
    mkdir -p "$cert_dir"
    mkcert -cert-file "${cert_dir}/${DOMAIN}.pem" -key-file "${cert_dir}/${DOMAIN}-key.pem" "$DOMAIN"
    ok "Certificat SSL local généré pour $DOMAIN"
}
