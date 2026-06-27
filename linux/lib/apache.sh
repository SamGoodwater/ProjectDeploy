#!/usr/bin/env bash
# Configuration Apache vhost

set -euo pipefail

configure_apache_vhost() {
    [[ "${WEB_SERVER:-apache}" == "apache" ]] || return 0
    [[ "${PROJECT_TYPE:-}" == "web" ]] || return 0
    [[ -n "${DOCUMENT_ROOT:-}" ]] || return 0

    info "Configuration du vhost Apache pour ${DOMAIN}..."

    local vhost_file="/etc/apache2/sites-available/${PROJECT_SLUG}.conf"
    render_template "${REPO_ROOT}/linux/templates/apache-vhost.conf.tpl" "$vhost_file"

    a2ensite "${PROJECT_SLUG}.conf" 2>/dev/null || true
    a2dissite 000-default.conf 2>/dev/null || true

    apache2ctl configtest
    systemctl reload apache2

    ok "Vhost Apache actif : http://${DOMAIN}"
    save_state "DOMAIN" "$DOMAIN"
    save_state "URL" "http://${DOMAIN}"
}

configure_nginx_vhost() {
    [[ "${WEB_SERVER:-}" == "nginx" ]] || return 0
    [[ "${PROJECT_TYPE:-}" == "web" ]] || return 0

    info "Configuration du vhost Nginx..."
    local vhost_file="/etc/nginx/sites-available/${PROJECT_SLUG}"

    cat > "$vhost_file" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    root ${DOCUMENT_ROOT};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION:-8.3}-fpm.sock;
    }
}
NGINX

    ln -sf "$vhost_file" "/etc/nginx/sites-enabled/${PROJECT_SLUG}"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl reload nginx

    ok "Vhost Nginx actif : http://${DOMAIN}"
}
