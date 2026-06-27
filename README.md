# ProjectDeploy

Script d'initialisation automatique d'une WSL Debian par projet — stack web (Apache, PHP, Laravel, Node/pnpm, PostgreSQL) ou Python (FastAPI, Django, venv).

## Prérequis

- **Windows 10/11** avec WSL2 activé
- **PowerShell 5.1+** (ou PowerShell 7)
- Droits **administrateur** recommandés (création WSL, fichier hosts)

## Démarrage rapide

### Depuis Windows (PowerShell)

```powershell
# Cloner le dépôt
git clone https://github.com/VOTRE_USER/ProjectDeploy.git
cd ProjectDeploy

# Mode interactif — crée une WSL + installe tout
.\install.ps1

# Avec un profil prédéfini
.\install.ps1 -ProjectName "mon-api" -ProjectType python -Profile python-fastapi -NonInteractive

# Laravel complet sur une nouvelle WSL
.\install.ps1 -ProjectName "mon-site" -Profile web-laravel

# WSL existante (comme celle où vous développez déjà)
.\install.ps1 -UseExistingWsl -ProjectName "mon-app" -Profile web-laravel
```

### Depuis la WSL existante (sans PowerShell)

Utile pour tester ou reprovisionner la WSL courante :

```bash
cd ~/scriptDeploy   # ou le chemin du clone
sudo bash linux/bootstrap.sh
```

Avec un profil :

```bash
sudo bash linux/bootstrap.sh \
  --project mon-api \
  --type python \
  --profile python-fastapi \
  --non-interactive
```

## Profils disponibles

| Profil | Stack |
|--------|-------|
| `web-laravel` | Apache, PHP 8.3, Composer, Laravel, Node/pnpm, PostgreSQL |
| `web-vanilla` | Apache, PHP 8.3, Composer, PHP vanilla |
| `python-fastapi` | Python 3, venv, pip, FastAPI, uvicorn, PostgreSQL, pytest/ruff |
| `custom` | Questionnaire interactif complet |

## Flux complet (Windows → WSL → Projet)

```
install.ps1 (PowerShell)
    ├── Écrit ~/.wslconfig (RAM, CPU, swap)
    ├── wsl --install -d Debian --name wsl-mon-projet
    ├── Lance bootstrap.sh dans la WSL
    │       ├── apt update/upgrade
    │       ├── Crée utilisateur Debian + /etc/wsl.conf (systemd)
    │       ├── Installe la stack (web ou python)
    │       ├── Configure PostgreSQL / Redis
    │       ├── Permissions (chown www-data pour web)
    │       ├── Vhost Apache (*.local)
    │       └── Git init + GitHub (optionnel)
    └── Ajoute 127.0.0.1 mon-projet.local dans hosts Windows
```

## Questionnaire interactif (mode custom)

### Projet web

1. Serveur : Apache / Nginx
2. PHP ? → version → framework (vanilla, Laravel, Symfony, WordPress)
3. Node.js ? → pnpm (défaut) / npm / yarn
4. Base de données : aucune / PostgreSQL / MySQL / SQLite
5. Redis, SSL local (mkcert), Xdebug

### Projet Python

1. Python : système / pyenv (3.11, 3.12)
2. Gestionnaire : pip / uv / poetry
3. Type : script / FastAPI / Django / Flask
4. Base de données : aucune / PostgreSQL / SQLite
5. Outils qualité : pytest, ruff, black

### Commun

- Utilisateur Debian (défaut : nom utilisateur Windows)
- Git init
- Dépôt GitHub : aucun / privé / public

## Structure du dépôt

```
scriptDeploy/
├── install.ps1                 # Point d'entrée Windows
├── config/
│   ├── defaults.conf           # Valeurs par défaut
│   └── wsl-template.wslconfig
├── profiles/                   # Profils prédéfinis
├── windows/                    # Scripts PowerShell
│   ├── New-WslInstance.ps1
│   ├── Set-WslConfig.ps1
│   ├── Invoke-WslBootstrap.ps1
│   └── Set-WindowsHosts.ps1
└── linux/
    ├── bootstrap.sh            # Point d'entrée Linux
    ├── lib/                    # Modules bash
    └── templates/              # vhost Apache, .gitignore, .env
```

## Arguments PowerShell

| Paramètre | Description |
|-----------|-------------|
| `-ProjectName` | Nom du projet |
| `-ProjectType` | `web` ou `python` |
| `-Profile` | `web-laravel`, `web-vanilla`, `python-fastapi` |
| `-ProjectPath` | Chemin custom (défaut : `/var/www/X` ou `~/X`) |
| `-WslName` | Nom instance WSL (défaut : `wsl-{slug}`) |
| `-UseExistingWsl` | Ne pas créer de WSL, utiliser l'existante |
| `-NonInteractive` | Pas de questions (nécessite ProjectName + Type ou Profile) |
| `-Memory`, `-Processors`, `-Swap` | Ressources .wslconfig |

## Arguments bootstrap Linux

```bash
sudo bash linux/bootstrap.sh \
  --project mon-projet \
  --type web \
  --profile web-laravel \
  --path /var/www/mon-projet \
  --user monuser \
  --wsl-name wsl-mon-projet \
  --non-interactive
```

## Après l'installation

```powershell
# Entrer dans la WSL du projet
wsl -d wsl-mon-projet

# Appliquer systemd (première fois)
wsl --shutdown
# Puis relancer la WSL
```

### Laravel

```bash
cd /var/www/mon-projet
php artisan migrate
pnpm run dev
# http://mon-projet.local
```

### FastAPI

```bash
cd ~/mon-projet
source .venv/bin/activate
uvicorn app.main:app --reload
```

## GitHub

Le script installe `gh` et peut créer un dépôt si authentifié :

```bash
gh auth login
```

Pour générer une clé SSH :

```bash
ssh-keygen -t ed25519 -C "votre@email.com"
# Ajouter ~/.ssh/id_ed25519.pub sur GitHub
```

## Logs

Les logs d'installation sont dans :

```
/var/log/wsl-project-init/setup.log
```

L'état et le récapitulatif :

```
/var/lib/wsl-project-init/summary.txt
```

## Supprimer un projet WSL

```powershell
wsl --terminate wsl-mon-projet
wsl --unregister wsl-mon-projet
```

## Publier sur GitHub

Le dépôt local est initialisé. Pour créer le dépôt public **ProjectDeploy** sur GitHub :

```bash
cd ~/scriptDeploy
chmod +x scripts/publish-github.sh
./scripts/publish-github.sh
```

Ou manuellement :

```bash
sudo apt install -y gh
gh auth login
cd ~/scriptDeploy
gh repo create ProjectDeploy --public --source=. --remote=origin --push
```

## Licence

MIT
