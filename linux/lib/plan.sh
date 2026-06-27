#!/usr/bin/env bash
# Parse plan.json via jq

set -euo pipefail

load_plan() {
    local plan_file="$1"
    [[ -f "$plan_file" ]] || die "Plan introuvable : $plan_file"

    if ! command_exists jq; then
        die "jq requis pour lire le plan"
    fi

    PROJECT_NAME="$(jq -r '.project.name' "$plan_file")"
    PROJECT_SLUG="$(jq -r '.project.slug' "$plan_file")"
    PROJECT_PATH="$(jq -r '.project.path' "$plan_file")"
    PROJECT_DOMAIN="$(jq -r '.project.domain // empty' "$plan_file")"

    WSL_NAME="$(jq -r '.wsl.name' "$plan_file")"
    WSL_USER="$(jq -r '.wsl.user' "$plan_file")"
    WSL_CREATE_NEW="$(jq -r '.wsl.createNew' "$plan_file")"
    WSL_MEMORY="$(jq -r '.wsl.memory' "$plan_file")"
    WSL_PROCESSORS="$(jq -r '.wsl.processors' "$plan_file")"
    WSL_SWAP="$(jq -r '.wsl.swap' "$plan_file")"
    WSL_DISTRIBUTION="$(jq -r '.wsl.distribution' "$plan_file")"

    GITHUB_INIT="$(jq -r '.github.init' "$plan_file")"
    GITHUB_CREATE_REMOTE="$(jq -r '.github.createRemote' "$plan_file")"
    GITHUB_VISIBILITY="$(jq -r '.github.visibility' "$plan_file")"

    if [[ -z "$WSL_USER" || "$WSL_USER" == "null" ]]; then
        WSL_USER="$(detect_windows_username)"
        [[ -n "$WSL_USER" ]] || WSL_USER="dev"
    fi

    export PROJECT_NAME PROJECT_SLUG PROJECT_PATH PROJECT_DOMAIN
    export WSL_NAME WSL_USER WSL_CREATE_NEW WSL_MEMORY WSL_PROCESSORS WSL_SWAP WSL_DISTRIBUTION
    export GITHUB_INIT GITHUB_CREATE_REMOTE GITHUB_VISIBILITY
    export PLAN_FILE="$plan_file"
}

plan_has_package() {
    local pkg_id="$1"
    jq -e --arg id "$pkg_id" '.packages[] | select(.id == $id)' "$PLAN_FILE" >/dev/null 2>&1
}

plan_package_option() {
    local pkg_id="$1"
    local opt_id="$2"
    local default="${3:-}"
    local val
    val="$(jq -r --arg id "$pkg_id" --arg opt "$opt_id" \
        '.packages[] | select(.id == $id) | .options[$opt] // empty' "$PLAN_FILE" 2>/dev/null || true)"
    if [[ -z "$val" || "$val" == "null" ]]; then
        echo "$default"
    else
        echo "$val"
    fi
}

plan_has_template() {
    local tpl_id="$1"
    jq -e --arg id "$tpl_id" '.templates[] | select(.id == $id)' "$PLAN_FILE" >/dev/null 2>&1
}

plan_template_option() {
    local tpl_id="$1"
    local opt_id="$2"
    local default="${3:-}"
    local val
    val="$(jq -r --arg id "$tpl_id" --arg opt "$opt_id" \
        '.templates[] | select(.id == $id) | .options[$opt] // empty' "$PLAN_FILE" 2>/dev/null || true)"
    if [[ -z "$val" || "$val" == "null" ]]; then
        echo "$default"
    else
        echo "$val"
    fi
}

plan_list_package_ids() {
    jq -r '.packages[].id' "$PLAN_FILE"
}

plan_list_template_ids() {
    jq -r '.templates[].id' "$PLAN_FILE"
}
