#!/usr/bin/env bash
# JCM Platform — VPS deploy script (run on server, not on Windows)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> JCM deploy from $ROOT"

if [[ ! -f .env ]]; then
  echo "ERROR: .env missing. Run: cp .env.example .env && nano .env"
  exit 1
fi

echo "==> Pull latest (if git repo)"
if git rev-parse --git-dir >/dev/null 2>&1; then
  git pull --ff-only || echo "WARN: git pull failed, continuing with local files"
fi

echo "==> Build and start containers"
docker compose build
docker compose up -d

echo "==> Wait for postgres"
sleep 5

echo "==> Apply marketing migration (idempotent)"
if [[ -f backend/db/migrations/002_marketing.sql ]]; then
  docker exec -i jcm-postgres psql -U "${POSTGRES_USER:-jcm_admin}" -d "${POSTGRES_DB:-jcm_bsv32}" \
    < backend/db/migrations/002_marketing.sql 2>/dev/null || true
fi

echo "==> Health check"
sleep 10
curl -sf http://localhost:8000/health && echo "" || echo "WARN: API health check failed"

echo "==> Running containers"
docker compose ps

echo ""
echo "Done. Dashboard: http://$(hostname -I | awk '{print $1}'):3000"
echo "API docs:       http://$(hostname -I | awk '{print $1}'):8000/docs"
