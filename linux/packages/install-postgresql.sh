#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
load_plan "$PLAN_FILE"
require_root

if systemctl is-active postgresql &>/dev/null; then
    ok "PostgreSQL déjà actif"
    exit 0
fi

ver="$(plan_package_option postgresql version "16")"
info "Installation de PostgreSQL ${ver}..."
apt_install "postgresql-${ver}" "postgresql-client-${ver}"
systemctl enable postgresql
systemctl start postgresql

DB_NAME="$(slugify "$PROJECT_NAME")"
DB_USER="${DB_NAME}_user"
DB_PASSWORD="$(generate_password)"

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

save_state "DB_NAME" "$DB_NAME"
save_state "DB_USER" "$DB_USER"
save_state "DB_PASSWORD" "$DB_PASSWORD"

ok "PostgreSQL installé (db: ${DB_NAME}, user: ${DB_USER})"
