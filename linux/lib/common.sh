#!/usr/bin/env bash
# Bibliothèque commune — logging, apt, utilitaires

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="/var/log/wsl-project-init"
LOG_FILE="${LOG_DIR}/setup.log"
STATE_DIR="/var/lib/wsl-project-init"
DRY_RUN=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${ts} [${level}] ${msg}" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${ts} [${level}] ${msg}"
}

info()  { log "INFO" "$*"; echo -e "${BLUE}→${NC} $*"; }
ok()    { log "OK"   "$*"; echo -e "${GREEN}✓${NC} $*"; }
warn()  { log "WARN" "$*"; echo -e "${YELLOW}!${NC} $*"; }
err()   { log "ERROR" "$*"; echo -e "${RED}✗${NC} $*" >&2; }

die() {
    err "$*"
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Cette étape nécessite les droits root (sudo)."
}

init_logging() {
    if ! mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null; then
        LOG_DIR="${REPO_ROOT}/.logs"
        STATE_DIR="${REPO_ROOT}/.state"
        LOG_FILE="${LOG_DIR}/setup.log"
        mkdir -p "$LOG_DIR" "$STATE_DIR"
    fi
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE" 2>/dev/null || true
}

load_defaults() {
    local defaults="${REPO_ROOT}/config/defaults.conf"
    if [[ -f "$defaults" ]]; then
        # shellcheck source=/dev/null
        source "$defaults"
    fi
}

load_profile() {
    local profile="$1"
    local profile_file="${REPO_ROOT}/profiles/${profile}.conf"
    [[ -f "$profile_file" ]] || die "Profil introuvable : $profile"
    # shellcheck source=/dev/null
    source "$profile_file"
    ok "Profil chargé : $profile"
}

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'
}

detect_windows_username() {
    local win_user=""
    if [[ -d /mnt/c/Users ]]; then
        for dir in /mnt/c/Users/*/; do
            local name
            name="$(basename "$dir")"
            case "$name" in
                Public|Default|Default\ User|All\ Users|desktop.ini) continue ;;
            esac
            if [[ -d "${dir}Documents" || -d "${dir}Desktop" ]]; then
                win_user="$name"
                break
            fi
        done
    fi
    echo "$win_user"
}

apt_update() {
    info "Mise à jour des index apt..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
}

apt_upgrade() {
    info "Mise à jour des paquets système..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get upgrade -y -qq
}

apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq "$@"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_base_packages() {
    info "Installation des paquets de base..."
    apt_install \
        curl wget git unzip zip ca-certificates gnupg lsb-release \
        software-properties-common apt-transport-https \
        build-essential pkg-config \
        openssh-client htop tree jq nano \
        ripgrep fd-find net-tools dnsutils iputils-ping lsof
    ok "Paquets de base installés"
}

configure_locale_timezone() {
    local tz="${TIMEZONE:-Europe/Paris}"
    local locale="${LOCALE:-fr_FR.UTF-8}"
    local locale_extra="${LOCALE_EXTRA:-en_US.UTF-8}"

    info "Configuration locale et timezone ($tz)..."
    apt_install locales
    sed -i "s/# ${locale}/${locale}/" /etc/locale.gen 2>/dev/null || true
    sed -i "s/# ${locale_extra}/${locale_extra}/" /etc/locale.gen 2>/dev/null || true
    locale-gen
    update-locale LANG="$locale" LC_ALL="$locale"
    ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
    echo "$tz" > /etc/timezone
    ok "Locale et timezone configurés"
}

create_debian_user() {
    local username="$1"
    local win_user
    win_user="$(detect_windows_username)"

    if id "$username" &>/dev/null; then
        ok "Utilisateur $username existe déjà"
        WSL_USER="$username"
        return 0
    fi

    info "Création de l'utilisateur $username..."
    useradd -m -s /bin/bash -G sudo,www-data "$username" 2>/dev/null || \
        useradd -m -s /bin/bash -G sudo "$username"

    echo "${username} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${username}"
    chmod 440 "/etc/sudoers.d/${username}"

    # Copier clés SSH root si présentes
    if [[ -d /root/.ssh ]]; then
        mkdir -p "/home/${username}/.ssh"
        cp -r /root/.ssh/* "/home/${username}/.ssh/" 2>/dev/null || true
        chown -R "${username}:${username}" "/home/${username}/.ssh"
        chmod 700 "/home/${username}/.ssh"
        chmod 600 "/home/${username}/.ssh/"* 2>/dev/null || true
    fi

    WSL_USER="$username"
    ok "Utilisateur $username créé (sudo NOPASSWD)"
    [[ -n "$win_user" ]] && info "Utilisateur Windows détecté : $win_user"
}

configure_wsl_conf() {
    local username="$1"
    local template="${REPO_ROOT}/linux/templates/wsl.conf.tpl"
    local target="/etc/wsl.conf"

    info "Configuration /etc/wsl.conf (systemd, user par défaut)..."
    sed "s/{{WSL_USER}}/${username}/g" "$template" > "$target"
    ok "/etc/wsl.conf configuré — exécutez 'wsl --shutdown' depuis Windows pour appliquer systemd"
}

ensure_project_dir() {
    local path="$1"
    if [[ -d "$path" ]]; then
        if [[ -n "$(ls -A "$path" 2>/dev/null)" ]]; then
            die "Le répertoire $path existe et n'est pas vide."
        fi
    else
        mkdir -p "$path"
    fi
}

generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
}

render_template() {
    local template="$1"
    local output="$2"
    local content
    content="$(cat "$template")"

    content="${content//\{\{PROJECT_NAME\}\}/${PROJECT_NAME:-}/}"
    content="${content//\{\{PROJECT_SLUG\}\}/${PROJECT_SLUG:-}/}"
    content="${content//\{\{DOMAIN\}\}/${DOMAIN:-}/}"
    content="${content//\{\{DOCUMENT_ROOT\}\}/${DOCUMENT_ROOT:-}/}"
    content="${content//\{\{DB_NAME\}\}/${DB_NAME:-}/}"
    content="${content//\{\{DB_USER\}\}/${DB_USER:-}/}"
    content="${content//\{\{DB_PASSWORD\}\}/${DB_PASSWORD:-}/}"
    content="${content//\{\{WSL_USER\}\}/${WSL_USER:-}/}"

    echo "$content" > "$output"
}

save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "${STATE_DIR}/state.env"
}

show_dry_run_plan() {
    echo ""
    echo "========================================"
    echo "  Plan d'installation (dry-run)"
    echo "========================================"
    echo "Projet       : ${PROJECT_NAME}"
    echo "Slug         : ${PROJECT_SLUG}"
    echo "Type         : ${PROJECT_TYPE}"
    echo "Chemin       : ${PROJECT_PATH}"
    echo "Utilisateur  : ${WSL_USER}"
    echo "Domaine      : ${DOMAIN:-N/A}"
    [[ "${PROJECT_TYPE}" == "web" ]] && {
        echo "Serveur web  : ${WEB_SERVER:-apache}"
        echo "PHP          : ${INSTALL_PHP:-false} (${PHP_VERSION:-})"
        echo "Framework    : ${PHP_FRAMEWORK:-}"
        echo "Node.js      : ${INSTALL_NODE:-false} (${NODE_MANAGER:-})"
    }
    [[ "${PROJECT_TYPE}" == "python" ]] && {
        echo "Python       : ${PYTHON_VERSION:-system}"
        echo "Deps         : ${PYTHON_DEPS_MANAGER:-pip}"
        echo "Type         : ${PYTHON_PROJECT_TYPE:-script}"
    }
    echo "Base de données : ${DB_TYPE:-none}"
    echo "Redis        : ${INSTALL_REDIS:-false}"
    echo "Git init     : ${GIT_INIT:-false}"
    echo "GitHub       : ${GITHUB_REPO:-none}"
    echo "Log (futur)  : ${LOG_FILE}"
    echo "========================================"
    echo ""
    warn "Relancez avec sudo pour appliquer (mêmes arguments + sans --dry-run)"
}

write_summary() {
    local summary_file="${STATE_DIR}/summary.txt"
    cat > "$summary_file" <<EOF
========================================
  WSL Project Init — Récapitulatif
========================================
Projet      : ${PROJECT_NAME}
Type        : ${PROJECT_TYPE}
Chemin      : ${PROJECT_PATH}
WSL         : ${WSL_INSTANCE_NAME:-N/A}
Domaine     : ${DOMAIN:-N/A}
Utilisateur : ${WSL_USER}
Git         : ${GIT_REMOTE:-non initialisé}
Log         : ${LOG_FILE}
========================================
EOF
    cat "$summary_file"
}
