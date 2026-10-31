#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench
# shellcheck disable=SC1090
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"

SITE_NAME="${SITE_NAME:-frontend}"
PORT="${PORT:-${LISTEN_PORT:-8000}}"
DB_HOST="${MYSQLHOST:-${DB_HOST:-}}"
DB_PORT="${MYSQLPORT:-${DB_PORT:-3306}}"
DB_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-${MYSQLPASSWORD:-}}"
DB_NAME="${MYSQLDATABASE:-${MYSQL_DATABASE:-}}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
REDIS_CACHE="${REDIS_CACHE:-}"
REDIS_QUEUE="${REDIS_QUEUE:-}"

if [ -z "$REDIS_CACHE" ] && [ -n "${REDIS_URL:-}" ]; then
  REDIS_CACHE="$REDIS_URL"
fi
if [ -z "$REDIS_QUEUE" ] && [ -n "${REDIS_URL:-}" ]; then
  if [[ "$REDIS_URL" == redis://*/* ]] || [[ "$REDIS_URL" == rediss://*/* ]]; then
    REDIS_QUEUE="${REDIS_URL%/*}/1"
  else
    REDIS_QUEUE="${REDIS_URL}/1"
  fi
fi

echo "[onerp] waiting for MySQL at ${DB_HOST}:${DB_PORT}..."
wait-for-it "${DB_HOST}:${DB_PORT}" -t 120

bench set-config -g db_host "$DB_HOST"
bench set-config -g db_port "$DB_PORT"
bench set-config -g redis_cache "$REDIS_CACHE"
bench set-config -g redis_queue "$REDIS_QUEUE"
bench set-config -g redis_socketio "$REDIS_CACHE"

if [ ! -d "sites/${SITE_NAME}" ]; then
  echo "[onerp] creating site ${SITE_NAME}..."
  NEW_SITE_ARGS=(
    "$SITE_NAME"
    --mariadb-root-password "$DB_ROOT_PASSWORD"
    --admin-password "$ADMIN_PASSWORD"
    --no-mariadb-socket
    --install-app erpnext
  )
  if [ -n "$DB_NAME" ]; then
    NEW_SITE_ARGS+=(--db-name "$DB_NAME")
  fi
  bench new-site "${NEW_SITE_ARGS[@]}"
  bench --site "$SITE_NAME" set-config allow_cors "*"
  bench --site "$SITE_NAME" enable-scheduler || true
fi

bench use "$SITE_NAME"

ROLE="${1:-web}"
case "$ROLE" in
  web)
    echo "[onerp] starting gunicorn on :${PORT}"
    exec /home/frappe/frappe-bench/env/bin/gunicorn \
      --chdir=/home/frappe/frappe-bench/sites \
      --bind=0.0.0.0:"${PORT}" \
      --workers="${WEB_WORKERS:-2}" \
      --threads="${WEB_THREADS:-4}" \
      --timeout=120 \
      frappe.app:application
    ;;
  worker)
    exec bench worker --queue short,default,long
    ;;
  scheduler)
    exec bench schedule
    ;;
  socketio)
    exec node apps/frappe/socketio.js
    ;;
  *)
    exec "$@"
    ;;
esac
