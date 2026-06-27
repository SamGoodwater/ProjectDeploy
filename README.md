# ProjectDeploy v2

Assistant de déploiement WSL piloté par **catalogues JSON** — interface graphique Tauri et CLI PowerShell.

## Prérequis

- Windows 10/11 avec WSL2
- PowerShell 5.1+
- Droits administrateur recommandés (création WSL, fichier hosts)

### Développement GUI (Tauri)

- [Node.js 20+](https://nodejs.org/)
- [Rust](https://rustup.rs/)
- [WebView2](https://developer.microsoft.com/microsoft-edge/webview2/)
- Visual Studio Build Tools (C++)

## Démarrage rapide

### Première utilisation (recommandé)

Un script vérifie les prérequis, installe ce qui manque (via winget) et lance la GUI :

```powershell
cd ProjectDeploy
.\install.ps1
```

Options :

```powershell
# Vérifier sans installer ni lancer la GUI
.\install.ps1 -CheckOnly

# Forcer une compilation release avant lancement
.\install.ps1 -BuildRelease

# Ignorer WSL (test GUI uniquement)
.\install.ps1 -SkipWsl

# Mode CLI au lieu de la GUI
.\install.ps1 -Cli
```

Prérequis contrôlés automatiquement : **WSL2**, **Node.js 20+**, **Rust**, **WebView2**, **VS Build Tools (C++)**, **npm install** dans `app/`.

### CLI (terminal)

```powershell
cd ProjectDeploy

# Mode interactif
.\cli\deploy.ps1

# Preset Laravel complet
.\cli\deploy.ps1 -Preset laravel-full -ProjectName "mon-site" -NonInteractive

# Preset FastAPI
.\cli\deploy.ps1 -Preset fastapi-api -ProjectName "mon-api" -NonInteractive

# Preset Nuxt
.\cli\deploy.ps1 -Preset nuxt-app -ProjectName "mon-nuxt" -NonInteractive

# Exécuter un plan existant
.\cli\deploy.ps1 -PlanFile plans\mon-site.plan.json

# Générer un plan sans installer
.\cli\deploy.ps1 -Preset laravel-full -ProjectName "test" -BuildOnly -NonInteractive
```

### GUI (Tauri)

```powershell
# Automatique (vérifie + installe + lance)
.\install.ps1

# Manuel
cd ProjectDeploy\app
npm install
npm run tauri dev
```

Build release :

```powershell
cd app
npm run tauri build
# Exécutable : app\src-tauri\target\release\project-deploy.exe
```

## Architecture

```
catalog/          → JSON (paquets, templates, presets) — seule source de vérité UI
cli/              → PowerShell (Build-Plan, Execute-Plan, deploy)
windows/          → WSL, .wslconfig, hosts
linux/            → orchestrator + scripts modulaires
app/              → Tauri + React (wizard 3 étapes + terminal PTY)
plans/            → plans générés (*.plan.json)
```

### Flux

1. UI ou CLI produit un `plan.json`
2. `Execute-Plan.ps1` configure Windows (`.wslconfig`, WSL, hosts)
3. `linux/orchestrator.sh` exécute paquets puis templates dans l'ordre

## Stacks v1

| Template | Preset | Paquets typiques |
|----------|--------|------------------|
| Laravel | `laravel-full` | Apache, PHP, Composer, Node, PostgreSQL |
| FastAPI | `fastapi-api` | Python, PostgreSQL |
| Nuxt | `nuxt-app` | Node.js (pnpm) |

## Étendre le catalogue — guide rapide

**Principe :** l'UI et la CLI lisent uniquement les fichiers JSON dans `catalog/`.  
Pour ajouter une possibilité, vous créez **1 JSON + 1 script bash** — sans modifier l'orchestrateur, la GUI ni la CLI.

```
catalog/packages/mon-paquet.json     →  checkbox + options dans l'UI
linux/packages/install-mon-paquet.sh →  exécuté par orchestrator.sh

catalog/templates/mon-stack.json     →  checkbox template
linux/templates/init-mon-stack.sh    →  init projet
```

Les schémas de référence sont dans `catalog/schema/` (`package.schema.json`, `template.schema.json`, `plan.schema.json`).

---

### Ajouter un paquet à installer

**Étape 1 — JSON** `catalog/packages/redis.json`

```json
{
  "id": "redis",
  "label": "Redis",
  "description": "Cache Redis",
  "category": "service",
  "script": "linux/packages/install-redis.sh",
  "requires": ["base"],
  "provides": ["redis"],
  "incompatibleWith": [],
  "options": [
    {
      "id": "port",
      "label": "Port",
      "type": "text",
      "default": "6379"
    }
  ]
}
```

| Champ | Rôle |
|-------|------|
| `id` | Identifiant unique (= nom du script `install-{id}.sh`) |
| `requires` | IDs de paquets cochés automatiquement avant celui-ci |
| `requiresProvides` | Ex. `["php"]` — résout le paquet qui `provides: ["php"]` |
| `provides` | Capacités exposées aux templates (`requiresProvides`) |
| `incompatibleWith` | IDs exclusifs (erreur si cochés ensemble) |
| `hidden` | `true` = invisible UI mais installable (ex. `base`) |
| `options` | Paramètres UI : `select`, `boolean`, `text` |

**Étape 2 — Script** `linux/packages/install-redis.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"          # --plan /var/lib/project-deploy/plan.json
load_plan "$PLAN_FILE"
require_root

port="$(plan_package_option redis port "6379")"

apt_install redis-server
ok "Redis installé (port $port)"
```

**Lire le plan dans un script :**

| Fonction bash | Usage |
|---------------|-------|
| `plan_package_option <id> <option> [défaut]` | Valeur d'une option paquet |
| `plan_has_package <id>` | Vrai si le paquet est dans le plan |
| `plan_template_option <id> <option> [défaut]` | Option d'un template |
| `$PROJECT_NAME`, `$PROJECT_PATH`, `$WSL_USER` | Variables projet (via `load_plan`) |

Rendre le script **idempotent** : tester si déjà installé (`command_exists`, `systemctl is-active`) et sortir avec `ok` si rien à faire.

```bash
chmod +x linux/packages/install-redis.sh
```

C'est tout — le paquet apparaît automatiquement dans l'UI (étape 2) et la CLI.

---

### Ajouter un template (init projet)

**Étape 1 — JSON** `catalog/templates/symfony.json`

```json
{
  "id": "symfony",
  "label": "Symfony",
  "description": "Projet Symfony via Composer",
  "script": "linux/templates/init-symfony.sh",
  "requiresPackages": ["base", "apache", "php", "composer"],
  "incompatibleWith": ["laravel", "fastapi", "nuxt"],
  "interactive": true,
  "defaultPath": "/var/www/{name}",
  "domain": true,
  "options": [],
  "github": { "supported": true, "fields": ["init", "createRemote", "visibility"] }
}
```

| Champ | Rôle |
|-------|------|
| `requiresPackages` | Paquets auto-sélectionnés quand le template est coché |
| `interactive` | `true` = terminal PTY dans la GUI après install |
| `defaultPath` | Chemin Linux par défaut (`{name}` = nom du projet) |
| `domain` | `true` → génère `{slug}.local` + entrée hosts Windows |
| `incompatibleWith` | Autres templates exclusifs |

**Étape 2 — Script** `linux/templates/init-symfony.sh`

Même en-tête que les paquets (`parse_script_args`, `load_plan`, `require_root`).  
Utilisez `setup_github_repo "$PROJECT_PATH"` (défini dans `linux/lib/common.sh`) pour Git/GitHub.

---

### Ajouter un preset (sélection pré-cochée)

Fichier `catalog/presets/symfony-full.json` :

```json
{
  "id": "symfony-full",
  "label": "Stack Symfony",
  "description": "Apache, PHP, Composer, Symfony",
  "packages": ["base", "apache", "php", "composer", "github-cli"],
  "packageOptions": {
    "php": { "version": "8.3" }
  },
  "templates": ["symfony"],
  "templateOptions": {},
  "github": {
    "init": true,
    "createRemote": "none",
    "visibility": "private"
  }
}
```

Utilisation CLI :

```powershell
.\cli\deploy.ps1 -Preset symfony-full -ProjectName "mon-app" -NonInteractive
```

Les presets apparaissent aussi comme boutons en haut du wizard GUI.

---

### Flux des paramètres (options)

```
JSON catalog (options[])
       ↓  GUI / CLI
plans/mon-projet.plan.json
       ↓
{
  "packages": [
    { "id": "php", "options": { "version": "8.3" } }
  ],
  "templates": [
    { "id": "laravel", "options": {} }
  ]
}
       ↓  orchestrator.sh
linux/packages/install-php.sh --plan /var/lib/project-deploy/plan.json
       ↓
plan_package_option php version "8.3"   →  "8.3"
```

---

### Tester sans la GUI

```powershell
# Générer le plan seulement
.\cli\deploy.ps1 -Preset laravel-full -ProjectName "test" -BuildOnly -NonInteractive

# Inspecter
Get-Content plans\test.plan.json

# Exécuter
.\cli\deploy.ps1 -PlanFile plans\test.plan.json
```

Logs Linux : `/var/log/project-deploy/setup.log`

---

### Git : user.name et user.email

Ces champs sont dans le bloc **`github`** du plan (pas un paquet séparé). Ils configurent `git config --global` pour l'utilisateur WSL avant `git init`.

**Dans le plan** (`plans/mon-projet.plan.json`) :

```json
"github": {
  "init": true,
  "createRemote": "none",
  "visibility": "private",
  "userName": "Jean Dupont",
  "userEmail": "jean@example.com"
}
```

**GUI** — étape 3 (Templates & GitHub), champs visibles quand « Initialiser Git » est coché.

**CLI** — valeurs par défaut : nom = utilisateur WSL, email = `{user}@localhost`. Pour les surcharger, éditez le plan ou le preset :

```json
"github": {
  "init": true,
  "createRemote": "ask",
  "visibility": "private",
  "userName": "Jean Dupont",
  "userEmail": "jean@example.com"
}
```

**Côté bash** — lus automatiquement via `load_plan` :

```bash
# $GIT_USER_NAME et $GIT_USER_EMAIL (variables exportées)
# appliqués dans setup_git_identity() avant git init
```

Si vides : repli sur `$WSL_USER` et `{WSL_USER}@localhost`.

---

### Rappels

- **Ordre d'exécution** : paquets (triés par dépendances) → templates — géré par `linux/orchestrator.sh`
- **Nommage** : `id` du JSON = suffixe du script (`install-{id}.sh`, `init-{id}.sh`)
- **base** : paquet système toujours inclus (utilisateur Debian, jq, locale, systemd)
- **Schemas** : valider vos JSON contre `catalog/schema/*.schema.json` si besoin


## Wizard GUI

1. **Projet & WSL** — nom, chemin, ressources WSL
2. **Paquets** — checkboxes générées depuis `catalog/packages/`
3. **Templates & GitHub** — init projet + options Git
4. **Installation** — logs + terminal PTY (shell dans le projet)

Presets chargables en un clic depuis l'écran principal.

## Checklist de validation manuelle

- [ ] `.\cli\deploy.ps1 -Preset laravel-full -ProjectName "test-laravel" -NonInteractive`
- [ ] `http://test-laravel.local` répond (hosts + Apache)
- [ ] `.\cli\deploy.ps1 -Preset fastapi-api -ProjectName "test-api" -NonInteractive`
- [ ] `uvicorn app.main:app --reload` dans la WSL
- [ ] `.\cli\deploy.ps1 -Preset nuxt-app -ProjectName "test-nuxt" -NonInteractive`
- [ ] GUI : wizard complet + terminal post-install
- [ ] Ajout d'un paquet JSON + script sans toucher au cœur

## Logs

```
/var/log/project-deploy/setup.log
/var/lib/project-deploy/summary.txt
```

## Licence

MIT
