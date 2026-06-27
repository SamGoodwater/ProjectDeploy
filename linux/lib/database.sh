#!/usr/bin/env bash
# Installation et configuration des bases de données

set -euo pipefail

install_database() {
    case "${DB_TYPE:-none}" in
        none)   info "Aucune base de données demandée" ;;
        postgresql) install_postgresql ;;
        mysql)      install_mysql ;;
        sqlite)     install_sqlite ;;
        *)          warn "Type de BDD inconnu : $DB_TYPE" ;;
    esac
}

install_postgresql() {
    info "Installation de PostgreSQL..."
    apt_install postgresql postgresql-contrib libpq-dev

    systemctl enable postgresql
    systemctl start postgresql

    DB_NAME="${DB_NAME:-${PROJECT_SLUG//-/_}_db}"
    DB_USER="${DB_USER:-${PROJECT_SLUG//-/_}_user}"
    DB_PASSWORD="${DB_PASSWORD:-$(generate_password)}"

    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"

    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

    ok "PostgreSQL configuré — DB: $DB_NAME, User: $DB_USER"
    save_state "DB_NAME" "$DB_NAME"
    save_state "DB_USER" "$DB_USER"
    save_state "DB_PASSWORD" "$DB_PASSWORD"
}

install_mysql() {
    info "Installation de MariaDB..."
    apt_install mariadb-server mariadb-client libmysqlclient-dev

    systemctl enable mariadb
    systemctl start mariadb

    DB_NAME="${DB_NAME:-${PROJECT_SLUG//-/_}_db}"
    DB_USER="${DB_USER:-${PROJECT_SLUG//-/_}_user}"
    DB_PASSWORD="${DB_PASSWORD:-$(generate_password)}"

    mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    ok "MariaDB configuré — DB: $DB_NAME, User: $DB_USER"
    save_state "DB_NAME" "$DB_NAME"
    save_state "DB_USER" "$DB_USER"
    save_state "DB_PASSWORD" "$DB_PASSWORD"
}

install_sqlite() {
    info "Installation de SQLite..."
    apt_install sqlite3 libsqlite3-dev
    DB_FILE="${PROJECT_PATH}/${PROJECT_SLUG}.sqlite"
    ok "SQLite prêt — fichier : $DB_FILE"
    save_state "DB_FILE" "$DB_FILE"
}

install_redis() {
    $INSTALL_REDIS || return 0

    info "Installation de Redis..."
    apt_install redis-server redis-tools

    systemctl enable redis-server
    systemctl start redis-server

    ok "Redis installé et démarré"
}
