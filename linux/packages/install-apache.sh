#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
load_plan "$PLAN_FILE"
require_root

if systemctl is-active apache2 &>/dev/null; then
    ok "Apache déjà actif"
    exit 0
fi

info "Installation d'Apache..."
apt_install apache2 libapache2-mod-rewrite
a2enmod rewrite headers ssl 2>/dev/null || true
if plan_has_package "php"; then
    a2enmod proxy_fcgi setenvif 2>/dev/null || true
fi
systemctl enable apache2
systemctl start apache2
ok "Apache installé"
