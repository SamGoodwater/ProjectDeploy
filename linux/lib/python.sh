#!/usr/bin/env bash
# Stack Python : venv, pip/uv/poetry, FastAPI, Django, Flask

set -euo pipefail

install_python_stack() {
    install_python
    install_python_deps_manager
    init_python_project
}

install_python() {
    info "Installation de Python..."
    apt_install python3 python3-pip python3-venv python3-dev pipx

    pipx ensurepath 2>/dev/null || true

    case "${PYTHON_VERSION:-system}" in
        system)
            ok "Python $(python3 --version) (système)"
            ;;
        3.11|3.12|3.13)
            install_pyenv
            pyenv install -s "${PYTHON_VERSION}"
            pyenv global "${PYTHON_VERSION}"
            ok "Python ${PYTHON_VERSION} via pyenv"
            ;;
        *)
            ok "Python $(python3 --version)"
            ;;
    esac
}

install_pyenv() {
    if [[ -d /opt/pyenv ]]; then
        export PYENV_ROOT="/opt/pyenv"
    else
        info "Installation de pyenv..."
        apt_install \
            libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
            libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
            libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

        git clone https://github.com/pyenv/pyenv.git /opt/pyenv
        export PYENV_ROOT="/opt/pyenv"
    fi

    export PATH="${PYENV_ROOT}/bin:${PATH}"
    eval "$(pyenv init - bash 2>/dev/null)" || true

    # Config pour l'utilisateur
    if [[ -n "${WSL_USER:-}" ]]; then
        local bashrc="/home/${WSL_USER}/.bashrc"
        if ! grep -q 'PYENV_ROOT' "$bashrc" 2>/dev/null; then
            cat >> "$bashrc" <<'PYENV'

# pyenv
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash 2>/dev/null)"
PYENV
        fi
    fi
}

install_python_deps_manager() {
    case "${PYTHON_DEPS_MANAGER:-pip}" in
        uv)
            info "Installation de uv..."
            curl -LsSf https://astral.sh/uv/install.sh | sh
            ok "uv installé"
            ;;
        poetry)
            info "Installation de Poetry..."
            curl -sSL https://install.python-poetry.org | python3 -
            ok "Poetry installé"
            ;;
        pip)
            python3 -m pip install --upgrade pip
            ok "pip à jour"
            ;;
    esac
}

init_python_project() {
    info "Initialisation du projet Python dans ${PROJECT_PATH}..."
    ensure_project_dir "$PROJECT_PATH"

    local run_as="${WSL_USER:-root}"

    case "${PYTHON_PROJECT_TYPE:-script}" in
        fastapi) init_fastapi "$run_as" ;;
        django)  init_django "$run_as" ;;
        flask)   init_flask "$run_as" ;;
        *)       init_python_script "$run_as" ;;
    esac

    ok "Projet Python initialisé"
}

create_venv() {
    local project_path="$1"
    local run_as="$2"
    sudo -u "$run_as" bash -c "
        cd '$project_path'
        python3 -m venv .venv
        source .venv/bin/activate
        pip install --upgrade pip
    "
}

init_fastapi() {
    local run_as="$1"
    sudo -u "$run_as" bash -c "
        mkdir -p '${PROJECT_PATH}/app'
        cd '${PROJECT_PATH}'
        python3 -m venv .venv
        source .venv/bin/activate
        pip install fastapi 'uvicorn[standard]' python-dotenv
        [[ '${DB_TYPE:-none}' == 'postgresql' ]] && pip install psycopg2-binary sqlalchemy alembic

        cat > app/main.py <<'PY'
from fastapi import FastAPI

app = FastAPI(title=\"${PROJECT_NAME}\")

@app.get(\"/\")
def read_root():
    return {\"message\": \"${PROJECT_NAME} — FastAPI ready\"}

@app.get(\"/health\")
def health():
    return {\"status\": \"ok\"}
PY

        cat > requirements.txt <<'REQ'
fastapi
uvicorn[standard]
python-dotenv
REQ

        cat > .env.example <<'ENV'
APP_NAME=${PROJECT_NAME}
DEBUG=true
DATABASE_URL=postgresql://${DB_USER:-user}:${DB_PASSWORD:-pass}@localhost:5432/${DB_NAME:-db}
ENV
    "

    $INSTALL_DEV_TOOLS && sudo -u "$run_as" bash -c "
        cd '${PROJECT_PATH}'
        source .venv/bin/activate
        pip install pytest pytest-cov ruff black mypy
    "
}

init_django() {
    local run_as="$1"
    sudo -u "$run_as" bash -c "
        cd '${PROJECT_PATH}'
        python3 -m venv .venv
        source .venv/bin/activate
        pip install django gunicorn python-dotenv
        [[ '${DB_TYPE:-none}' == 'postgresql' ]] && pip install psycopg2-binary
        django-admin startproject config .
    "
}

init_flask() {
    local run_as="$1"
    sudo -u "$run_as" bash -c "
        mkdir -p '${PROJECT_PATH}/app'
        cd '${PROJECT_PATH}'
        python3 -m venv .venv
        source .venv/bin/activate
        pip install flask gunicorn python-dotenv

        cat > app/__init__.py <<'PY'
from flask import Flask

def create_app():
    app = Flask(__name__)

    @app.route(\"/\")
    def index():
        return \"${PROJECT_NAME} — Flask ready\"

    return app
PY

        cat > app/wsgi.py <<'PY'
from app import create_app
app = create_app()
PY
    "
}

init_python_script() {
    local run_as="$1"
    sudo -u "$run_as" bash -c "
        mkdir -p '${PROJECT_PATH}/src'
        cd '${PROJECT_PATH}'
        python3 -m venv .venv
        source .venv/bin/activate

        cat > src/main.py <<'PY'
#!/usr/bin/env python3
\"\"\"${PROJECT_NAME} — script principal\"\"\"

def main():
    print(\"${PROJECT_NAME} — ready\")

if __name__ == \"__main__\":
    main()
PY

        cat > requirements.txt <<'REQ'
# Ajoutez vos dépendances ici
REQ
    "
}
