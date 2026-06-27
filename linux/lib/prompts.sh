#!/usr/bin/env bash
# Questionnaire interactif et parsing des arguments CLI

set -euo pipefail

NON_INTERACTIVE=false
SKIP_WSL_USER_SETUP=false

usage() {
    cat <<EOF
Usage: bootstrap.sh [OPTIONS]

Options:
  --project NAME          Nom du projet
  --type web|python       Type de projet
  --path PATH             Chemin du projet
  --profile NAME          Profil prédéfini (web-laravel, web-vanilla, python-fastapi)
  --user USERNAME         Nom utilisateur Debian à créer/utiliser
  --wsl-name NAME         Nom de l'instance WSL
  --non-interactive       Pas de questions (nécessite --project et --type ou --profile)
  --skip-user-setup       Ne pas créer/configurer l'utilisateur (déjà fait)
  --dry-run               Afficher le plan sans installer
  --help                  Afficher cette aide
EOF
}

prompt_yes_no() {
    local question="$1"
    local default="${2:-y}"
    local answer

    if $NON_INTERACTIVE; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi

    local hint="[Y/n]"
    [[ "$default" == "n" ]] && hint="[y/N]"

    read -r -p "$question $hint " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_value() {
    local question="$1"
    local default="$2"
    local answer

    if $NON_INTERACTIVE; then
        echo "$default"
        return
    fi

    read -r -p "$question [$default] " answer
    echo "${answer:-$default}"
}

prompt_choice() {
    local question="$1"
    shift
    local options=("$@")
    local default="${options[0]}"
    local answer

    if $NON_INTERACTIVE; then
        echo "$default"
        return
    fi

    echo "$question"
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt"
        ((i++))
    done

    read -r -p "Choix [1]: " answer
    answer="${answer:-1}"
    if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#options[@]} )); then
        echo "${options[$((answer - 1))]}"
    else
        echo "$default"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)        PROJECT_NAME="$2"; shift 2 ;;
            --type)           PROJECT_TYPE="$2"; shift 2 ;;
            --path)           PROJECT_PATH="$2"; shift 2 ;;
            --profile)        PROFILE="$2"; shift 2 ;;
            --user)           WSL_USER="$2"; shift 2 ;;
            --wsl-name)       WSL_INSTANCE_NAME="$2"; shift 2 ;;
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            --skip-user-setup) SKIP_WSL_USER_SETUP=true; shift ;;
            --dry-run)        DRY_RUN=true; shift ;;
            --help)           usage; exit 0 ;;
            *)                die "Argument inconnu : $1" ;;
        esac
    done
}

run_prompts() {
    echo ""
    echo "========================================"
    echo "  WSL Project Init — Configuration"
    echo "========================================"
    echo ""

    if [[ -z "${PROFILE:-}" ]]; then
        if prompt_yes_no "Utiliser un profil prédéfini ?" "n"; then
            PROFILE="$(prompt_choice "Profil :" "web-laravel" "web-vanilla" "python-fastapi" "custom")"
            if [[ "$PROFILE" != "custom" ]]; then
                load_profile "$PROFILE"
            fi
        fi
    else
        load_profile "$PROFILE"
    fi

    PROJECT_NAME="${PROJECT_NAME:-$(prompt_value "Nom du projet" "mon-projet")}"
    PROJECT_SLUG="$(slugify "$PROJECT_NAME")"

    if [[ -z "${PROJECT_TYPE:-}" ]]; then
        PROJECT_TYPE="$(prompt_choice "Type de projet :" "web" "python")"
    fi

    case "$PROJECT_TYPE" in
        web)
            PROJECT_PATH="${PROJECT_PATH:-$(prompt_value "Chemin du projet" "/var/www/${PROJECT_NAME}")}"
            run_web_prompts
            ;;
        python)
            PROJECT_PATH="${PROJECT_PATH:-$(prompt_value "Chemin du projet" "${HOME}/${PROJECT_NAME}")}"
            run_python_prompts
            ;;
        *)
            die "Type de projet invalide : $PROJECT_TYPE"
            ;;
    esac

    run_common_prompts
    finalize_paths
}

run_web_prompts() {
    if [[ -z "${WEB_SERVER:-}" ]]; then
        WEB_SERVER="$(prompt_choice "Serveur web :" "apache" "nginx")"
    fi

    if [[ -z "${INSTALL_PHP:-}" ]]; then
        INSTALL_PHP=true
        prompt_yes_no "Installer PHP ?" "y" || INSTALL_PHP=false
    fi

    if $INSTALL_PHP; then
        if [[ -z "${PHP_VERSION:-}" ]]; then
            PHP_VERSION="$(prompt_choice "Version PHP :" "8.3" "8.2" "8.4")"
        fi
        if [[ -z "${PHP_FRAMEWORK:-}" ]]; then
            PHP_FRAMEWORK="$(prompt_choice "Framework PHP :" "vanilla" "laravel" "symfony" "wordpress")"
        fi
    fi

    if [[ -z "${INSTALL_NODE:-}" ]]; then
        if [[ "${PHP_FRAMEWORK:-}" == "laravel" ]]; then
            INSTALL_NODE=true
            info "Node.js requis pour Laravel (Vite) — activé automatiquement"
        else
            INSTALL_NODE=false
            prompt_yes_no "Installer Node.js ?" "n" && INSTALL_NODE=true
        fi
    fi

    if $INSTALL_NODE && [[ -z "${NODE_MANAGER:-}" ]]; then
        NODE_MANAGER="$(prompt_choice "Gestionnaire de paquets JS :" "pnpm" "npm" "yarn")"
    fi

    if [[ -z "${DB_TYPE:-}" ]]; then
        DB_TYPE="$(prompt_choice "Base de données :" "none" "postgresql" "mysql" "sqlite")"
    fi

    if [[ -z "${INSTALL_REDIS:-}" ]]; then
        INSTALL_REDIS=false
        prompt_yes_no "Installer Redis ?" "n" && INSTALL_REDIS=true
    fi

    if [[ -z "${INSTALL_SSL_LOCAL:-}" ]]; then
        INSTALL_SSL_LOCAL=false
        prompt_yes_no "Configurer SSL local (mkcert) ?" "n" && INSTALL_SSL_LOCAL=true
    fi

    if [[ -z "${INSTALL_XDEBUG:-}" ]]; then
        INSTALL_XDEBUG=false
        $INSTALL_PHP && prompt_yes_no "Installer Xdebug ?" "n" && INSTALL_XDEBUG=true
    fi
}

run_python_prompts() {
    if [[ -z "${PYTHON_VERSION:-}" ]]; then
        PYTHON_VERSION="$(prompt_choice "Python :" "system" "3.12" "3.11")"
    fi

    if [[ -z "${PYTHON_DEPS_MANAGER:-}" ]]; then
        PYTHON_DEPS_MANAGER="$(prompt_choice "Gestionnaire de dépendances :" "pip" "uv" "poetry")"
    fi

    if [[ -z "${PYTHON_PROJECT_TYPE:-}" ]]; then
        PYTHON_PROJECT_TYPE="$(prompt_choice "Type de projet Python :" "script" "fastapi" "django" "flask")"
    fi

    if [[ -z "${DB_TYPE:-}" ]]; then
        DB_TYPE="$(prompt_choice "Base de données :" "none" "postgresql" "sqlite")"
    fi

    if [[ -z "${INSTALL_DEV_TOOLS:-}" ]]; then
        INSTALL_DEV_TOOLS=false
        prompt_yes_no "Installer outils qualité (pytest, ruff, black) ?" "y" && INSTALL_DEV_TOOLS=true
    fi
}

run_common_prompts() {
    if [[ -z "${WSL_USER:-}" ]]; then
        local default_user
        default_user="$(detect_windows_username)"
        default_user="${default_user:-dev}"
        WSL_USER="$(prompt_value "Utilisateur Debian" "$default_user")"
    fi

    if [[ -z "${GIT_INIT:-}" ]]; then
        GIT_INIT=true
        prompt_yes_no "Initialiser Git ?" "y" || GIT_INIT=false
    fi

    if $GIT_INIT && [[ -z "${GITHUB_REPO:-}" ]]; then
        GITHUB_REPO="$(prompt_choice "Créer un dépôt GitHub ?" "none" "private" "public")"
    fi

    if $GIT_INIT; then
        if ! git config --global user.name &>/dev/null; then
            GIT_USER_NAME="$(prompt_value "Git user.name" "${WSL_USER}")"
            git config --global user.name "$GIT_USER_NAME"
        fi
        if ! git config --global user.email &>/dev/null; then
            GIT_USER_EMAIL="$(prompt_value "Git user.email" "${WSL_USER}@localhost")"
            git config --global user.email "$GIT_USER_EMAIL"
        fi
    fi
}

finalize_paths() {
    PROJECT_SLUG="$(slugify "$PROJECT_NAME")"
    DOMAIN="${PROJECT_SLUG}.local"
    WSL_INSTANCE_NAME="${WSL_INSTANCE_NAME:-wsl-${PROJECT_SLUG}}"

    if [[ "$PROJECT_TYPE" == "web" ]]; then
        case "${PHP_FRAMEWORK:-vanilla}" in
            laravel|symfony) DOCUMENT_ROOT="${PROJECT_PATH}/public" ;;
            wordpress)       DOCUMENT_ROOT="${PROJECT_PATH}" ;;
            *)               DOCUMENT_ROOT="${PROJECT_PATH}/public" ;;
        esac
    fi
}

validate_config() {
    [[ -n "${PROJECT_NAME:-}" ]] || die "Nom du projet requis (--project ou mode interactif)"
    [[ -n "${PROJECT_TYPE:-}" ]]  || die "Type de projet requis (--type ou mode interactif)"
    finalize_paths
    [[ -n "${PROJECT_PATH:-}" ]] || {
        case "$PROJECT_TYPE" in
            web)    PROJECT_PATH="/var/www/${PROJECT_NAME}" ;;
            python) PROJECT_PATH="${HOME}/${PROJECT_NAME}" ;;
        esac
    }
    [[ -n "${WSL_USER:-}" ]] || WSL_USER="$(detect_windows_username)"
    WSL_USER="${WSL_USER:-dev}"
}
