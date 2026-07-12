#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$project_root"

if ! docker compose ps --status running --services | grep -qx oracle; then
    echo "Oracle is not running. Start it with: docker compose up -d" >&2
    exit 1
fi

docker compose exec -T oracle bash -lc \
    'sqlplus -s "$APP_USER/$APP_USER_PASSWORD@//localhost/FREEPDB1"' \
    < sql/tests/test_services.sql