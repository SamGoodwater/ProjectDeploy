#!/usr/bin/env bash
# Publie ProjectDeploy sur GitHub (dépôt public)
set -euo pipefail

REPO_NAME="ProjectDeploy"
VISIBILITY="${1:-public}"

if ! command -v gh >/dev/null 2>&1; then
    echo "Installation de GitHub CLI..."
    sudo apt update
    sudo apt install -y gh
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Authentification GitHub requise :"
    gh auth login
fi

cd "$(dirname "$0")/.."

if git remote get-url origin >/dev/null 2>&1; then
    echo "Remote origin déjà configuré."
    git push -u origin main
else
    gh repo create "$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin --push
fi

echo ""
echo "✓ Dépôt publié : https://github.com/$(gh api user -q .login)/${REPO_NAME}"
