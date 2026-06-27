#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
[[ -n "$PLAN_FILE" ]] || die "Usage: $0 --plan PATH"
load_plan "$PLAN_FILE"
require_root
init_logging

if plan_has_package "base"; then
    info "Installation des paquets de base..."
    apt_install \
        curl wget git unzip zip ca-certificates gnupg lsb-release \
        software-properties-common apt-transport-https \
        build-essential pkg-config \
        openssh-client htop tree jq nano \
        ripgrep fd-find net-tools dnsutils iputils-ping lsof sudo

    info "Configuration locale et timezone..."
    locale="fr_FR.UTF-8"
    tz="Europe/Paris"
    apt_install locales
    sed -i "s/# ${locale}/${locale}/" /etc/locale.gen 2>/dev/null || true
    locale-gen
    update-locale LANG="$locale" LC_ALL="$locale"
    ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
    echo "$tz" > /etc/timezone

    if ! id "$WSL_USER" &>/dev/null; then
        info "Création de l'utilisateur ${WSL_USER}..."
        useradd -m -s /bin/bash -G sudo,www-data "$WSL_USER" 2>/dev/null || \
            useradd -m -s /bin/bash -G sudo "$WSL_USER"
        echo "${WSL_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${WSL_USER}"
        chmod 440 "/etc/sudoers.d/${WSL_USER}"
    else
        ok "Utilisateur ${WSL_USER} existe déjà"
    fi

    cat > /etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=${WSL_USER}
EOF
    ok "Paquets de base et utilisateur configurés"
    warn "Exécutez 'wsl --shutdown' depuis Windows si systemd vient d'être activé"
else
    ok "Paquet base non sélectionné — skip"
fi
