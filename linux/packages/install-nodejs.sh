#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
load_plan "$PLAN_FILE"
require_root

NODE_MANAGER="$(plan_package_option nodejs manager "pnpm")"

if command_exists node; then
    ok "Node.js déjà installé ($(node --version))"
    exit 0
fi

info "Installation de Node.js via fnm..."
if ! command_exists fnm; then
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

export PATH="/root/.local/share/fnm:${PATH}"
eval "$(fnm env --shell bash 2>/dev/null)" || true
fnm install --lts
fnm default lts-latest
eval "$(fnm env --shell bash)"

case "$NODE_MANAGER" in
    pnpm) corepack enable 2>/dev/null || npm install -g pnpm ;;
    yarn) corepack enable 2>/dev/null || npm install -g yarn ;;
    npm)  ok "npm disponible" ;;
esac

if [[ -n "${WSL_USER:-}" ]] && id "$WSL_USER" &>/dev/null; then
    bashrc="/home/${WSL_USER}/.bashrc"
    if ! grep -q 'fnm env' "$bashrc" 2>/dev/null; then
        cat >> "$bashrc" <<'FNM'

# fnm (Node version manager)
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --shell bash 2>/dev/null)"
FNM
        # Installer fnm pour l'utilisateur
        sudo -u "$WSL_USER" bash -c 'curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell' || true
        sudo -u "$WSL_USER" bash -c 'export PATH="$HOME/.local/share/fnm:$PATH" && eval "$(fnm env --shell bash)" && fnm install --lts && fnm default lts-latest' || true
    fi
fi

ok "Node.js $(node --version) installé"
