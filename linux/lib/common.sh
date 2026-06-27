#!/usr/bin/env bash
# Bibliothèque commune — logging, apt, utilitaires

set -euo pipefail

LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LINUX_DIR}/.." && pwd)"
LOG_DIR="/var/log/project-deploy"
LOG_FILE="${LOG_DIR}/setup.log"
STATE_DIR="/var/lib/project-deploy"
PLAN_FILE=""
NON_INTERACTIVE=false

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
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

generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
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

run_as_user() {
    local user="$1"
    shift
    if [[ "$user" == "root" ]] || [[ -z "$user" ]]; then
        bash -c "$*"
    else
        sudo -u "$user" bash -c "$*"
    fi
}

save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "${STATE_DIR}/state.env"
}

write_summary() {
    local summary_file="${STATE_DIR}/summary.txt"
    cat > "$summary_file" <<EOF
========================================
  ProjectDeploy — Récapitulatif
========================================
Projet      : ${PROJECT_NAME:-}
Slug        : ${PROJECT_SLUG:-}
Chemin      : ${PROJECT_PATH:-}
WSL         : ${WSL_NAME:-}
Domaine     : ${PROJECT_DOMAIN:-N/A}
Utilisateur : ${WSL_USER:-}
Log         : ${LOG_FILE}
========================================
EOF
    cat "$summary_file"
}

parse_script_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan)
                PLAN_FILE="$2"
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

load_plan_env() {
    # shellcheck source=plan.sh
    source "${LINUX_DIR}/lib/plan.sh"
    load_plan "$PLAN_FILE"
}

setup_git_identity() {
    local run_as="${WSL_USER:-root}"
    local name="${GIT_USER_NAME:-}"
    local email="${GIT_USER_EMAIL:-}"

    [[ -n "$name" ]] || name="$run_as"
    [[ -n "$email" ]] || email="${run_as}@localhost"

    if ! command_exists git; then
        return 0
    fi

    run_as_user "$run_as" "git config --global user.name '$name'"
    run_as_user "$run_as" "git config --global user.email '$email'"
    ok "Git configuré : $name <$email>"
}

setup_github_repo() {
    local project_path="$1"
    local run_as="${WSL_USER:-root}"

    [[ "${GITHUB_INIT:-false}" == "true" ]] || return 0

    if ! command_exists git; then
        warn "Git non disponible — skip init"
        return 0
    fi

    setup_git_identity

    run_as_user "$run_as" "cd '$project_path' && git init -b main 2>/dev/null || git init"

    if [[ "${GITHUB_CREATE_REMOTE:-none}" == "none" ]]; then
        ok "Git initialisé (sans remote)"
        return 0
    fi

    if ! command_exists gh; then
        warn "gh non installé — git init seulement"
        return 0
    fi

    if ! gh auth status &>/dev/null; then
        warn "gh non authentifié — exécutez 'gh auth login' puis recréez le remote"
        return 0
    fi

    local visibility="${GITHUB_VISIBILITY:-private}"
    if [[ "${GITHUB_CREATE_REMOTE}" == "ask" ]]; then
        visibility="${GITHUB_VISIBILITY:-private}"
    fi

    run_as_user "$run_as" "cd '$project_path' && gh repo create '${PROJECT_NAME}' --${visibility} --source=. --remote=origin" || \
        warn "Impossible de créer le dépôt GitHub automatiquement"
}
