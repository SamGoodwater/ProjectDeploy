#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
load_plan "$PLAN_FILE"
require_root

ver="$(plan_package_option php version "8.3")"

if command_exists "php${ver}"; then
    ok "PHP ${ver} déjà installé"
    exit 0
fi

info "Installation de PHP ${ver}..."
apt_install \
    "php${ver}" "php${ver}-cli" "php${ver}-fpm" \
    "php${ver}-mbstring" "php${ver}-xml" "php${ver}-curl" \
    "php${ver}-zip" "php${ver}-bcmath" "php${ver}-intl" \
    "php${ver}-gd" "php${ver}-sqlite3"

if plan_has_package "postgresql"; then
    apt_install "php${ver}-pgsql"
fi

update-alternatives --set php "/usr/bin/php${ver}" 2>/dev/null || true
systemctl enable "php${ver}-fpm"
systemctl start "php${ver}-fpm"
ok "PHP ${ver} installé"
