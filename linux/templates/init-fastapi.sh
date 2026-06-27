#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/plan.sh"

parse_script_args "$@"
load_plan "$PLAN_FILE"
require_root
init_logging

run_as="${WSL_USER:-root}"
ensure_project_dir "$PROJECT_PATH"

info "Initialisation FastAPI dans ${PROJECT_PATH}..."

run_as_user "$run_as" "
    python3 -m venv '${PROJECT_PATH}/.venv'
    source '${PROJECT_PATH}/.venv/bin/activate'
    pip install --upgrade pip
    pip install 'fastapi[standard]' uvicorn sqlalchemy psycopg2-binary pytest ruff
"

run_as_user "$run_as" "mkdir -p '${PROJECT_PATH}/app'"

cat > "${PROJECT_PATH}/app/__init__.py" <<'PY'

PY

cat > "${PROJECT_PATH}/app/main.py" <<PY
from fastapi import FastAPI

app = FastAPI(title="${PROJECT_NAME}")


@app.get("/")
def read_root():
    return {"project": "${PROJECT_NAME}", "status": "ok"}


@app.get("/health")
def health():
    return {"healthy": True}
PY

cat > "${PROJECT_PATH}/requirements.txt" <<'REQ'
fastapi[standard]
uvicorn
sqlalchemy
psycopg2-binary
pytest
ruff
REQ

cat > "${PROJECT_PATH}/README.md" <<MD
# ${PROJECT_NAME}

API FastAPI générée par ProjectDeploy.

\`\`\`bash
cd ${PROJECT_PATH}
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
\`\`\`
MD

chown -R "${run_as}:${run_as}" "$PROJECT_PATH"

setup_github_repo "$PROJECT_PATH"
ok "FastAPI initialisé"
