#!/usr/bin/env bash
# Git init et création de dépôt GitHub via gh CLI

set -euo pipefail

setup_git() {
    $GIT_INIT || return 0
    [[ -d "${PROJECT_PATH}" ]] || return 0

    info "Initialisation Git..."

    local run_as="${WSL_USER:-root}"
    local gitignore_template

    case "${PROJECT_TYPE:-}" in
        web)    gitignore_template="${REPO_ROOT}/linux/templates/gitignore.web" ;;
        python) gitignore_template="${REPO_ROOT}/linux/templates/gitignore.python" ;;
    esac

    sudo -u "$run_as" bash -c "
        cd '${PROJECT_PATH}'
        git init -b main
        [[ -f '${gitignore_template}' ]] && cp '${gitignore_template}' .gitignore
        git add .
        git commit -m 'Initial project setup via wsl-project-init'
    "

    ok "Git initialisé (branche main)"

    case "${GITHUB_REPO:-none}" in
        private|public) create_github_repo ;;
        ask)
            if ! $NON_INTERACTIVE; then
                GITHUB_REPO="$(prompt_choice "Créer un dépôt GitHub ?" "none" "private" "public")"
                [[ "$GITHUB_REPO" != "none" ]] && create_github_repo
            fi
            ;;
    esac
}

install_gh_cli() {
    if command_exists gh; then
        return 0
    fi

    info "Installation de GitHub CLI (gh)..."
    apt_install gh 2>/dev/null || {
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            > /etc/apt/sources.list.d/github-cli.list
        apt_update
        apt_install gh
    }
}

create_github_repo() {
    install_gh_cli

    if ! sudo -u "${WSL_USER}" gh auth status &>/dev/null; then
        warn "gh n'est pas authentifié. Exécutez : gh auth login"
        warn "Le dépôt GitHub n'a pas été créé automatiquement."
        return 0
    fi

    local visibility="${GITHUB_REPO}"
    local run_as="${WSL_USER}"

    info "Création du dépôt GitHub (${visibility})..."

    sudo -u "$run_as" bash -c "
        cd '${PROJECT_PATH}'
        gh repo create '${PROJECT_NAME}' --${visibility} --source=. --remote=origin --push
    "

    GIT_REMOTE="$(sudo -u "$run_as" git -C "${PROJECT_PATH}" remote get-url origin 2>/dev/null || echo '')"
    ok "Dépôt GitHub créé : ${GIT_REMOTE}"
    save_state "GIT_REMOTE" "$GIT_REMOTE"
}

setup_ssh_key() {
    $NON_INTERACTIVE && return 0

    local user_home="/home/${WSL_USER}"
    local ssh_dir="${user_home}/.ssh"

    [[ -f "${ssh_dir}/id_ed25519" ]] && return 0

    if prompt_yes_no "Générer une clé SSH pour GitHub ?" "y"; then
        sudo -u "${WSL_USER}" mkdir -p "$ssh_dir"
        sudo -u "${WSL_USER}" ssh-keygen -t ed25519 -C "${WSL_USER}@wsl" -f "${ssh_dir}/id_ed25519" -N ""
        ok "Clé SSH générée : ${ssh_dir}/id_ed25519.pub"
        echo ""
        info "Ajoutez cette clé à GitHub (Settings → SSH keys) :"
        cat "${ssh_dir}/id_ed25519.pub"
        echo ""
    fi
}

generate_readme() {
    [[ -d "${PROJECT_PATH}" ]] || return 0
    [[ -f "${PROJECT_PATH}/README.md" ]] && return 0

    local run_as="${WSL_USER:-root}"

    sudo -u "$run_as" bash -c "cat > '${PROJECT_PATH}/README.md'" <<EOF
# ${PROJECT_NAME}

Projet initialisé avec [wsl-project-init](https://github.com).

## Stack

- **Type** : ${PROJECT_TYPE}
- **Chemin** : ${PROJECT_PATH}
$( [[ "${PROJECT_TYPE}" == "web" ]] && echo "- **URL** : http://${DOMAIN}" )
$( [[ "${DB_TYPE:-none}" != "none" ]] && echo "- **Base de données** : ${DB_TYPE}" )

## Démarrage

$( [[ "${PROJECT_TYPE}" == "web" && "${PHP_FRAMEWORK:-}" == "laravel" ]] && cat <<'LARAVEL'
```bash
cd ${PROJECT_PATH}
php artisan serve
# ou via Apache : http://${DOMAIN}
composer install
pnpm install && pnpm run dev
php artisan migrate
```
LARAVEL
)

$( [[ "${PROJECT_TYPE}" == "python" && "${PYTHON_PROJECT_TYPE:-}" == "fastapi" ]] && cat <<'FASTAPI'
```bash
cd ${PROJECT_PATH}
source .venv/bin/activate
uvicorn app.main:app --reload
```
FASTAPI
)
EOF

    ok "README.md généré"
}
