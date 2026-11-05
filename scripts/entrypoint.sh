#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench
# shellcheck disable=SC1090
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"

SITE_NAME="${SITE_NAME:-frontend}"
export SITE_NAME
PORT="${PORT:-${LISTEN_PORT:-8000}}"
ROLE="${1:-web}"
DB_HOST="${MYSQLHOST:-${DB_HOST:-}}"
DB_PORT="${MYSQLPORT:-${DB_PORT:-3306}}"
DB_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-${MYSQLPASSWORD:-}}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
REDIS_CACHE="${REDIS_CACHE:-}"
REDIS_QUEUE="${REDIS_QUEUE:-}"
PERSIST="${PERSIST_DIR:-/home/frappe/persist}"

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

echo "[onerp] waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
wait-for-it "${DB_HOST}:${DB_PORT}" -t 120

bench set-config -g db_host "$DB_HOST"
bench set-config -g db_port "$DB_PORT"
bench set-config -g redis_cache "$REDIS_CACHE"
bench set-config -g redis_queue "$REDIS_QUEUE"
bench set-config -g redis_socketio "$REDIS_CACHE"

if ! mkdir -p "$PERSIST" 2>/dev/null || [ ! -w "$PERSIST" ]; then
  echo "[onerp] ERROR: ${PERSIST} writable nahi hai. Volume lagao ya RAILWAY_RUN_UID=0 variable set karo."
  exit 1
fi

MARKER="${PERSIST}/${SITE_NAME}/.onerp_installed"

if [ -f "$MARKER" ]; then
  echo "[onerp] existing site mila, link kar raha hoon..."
  rm -rf "sites/${SITE_NAME}"
  ln -sfn "${PERSIST}/${SITE_NAME}" "sites/${SITE_NAME}"
else
  rm -rf "sites/${SITE_NAME}" "${PERSIST:?}/${SITE_NAME}"
  FORCE_ARGS=()
  if [ "${ONERP_FORCE_RECREATE:-}" = "1" ]; then
    echo "[onerp] ONERP_FORCE_RECREATE=1, purana database drop hoga"
    FORCE_ARGS+=(--force)
  fi
  echo "[onerp] creating site ${SITE_NAME}..."
  bench new-site "$SITE_NAME" \
    --mariadb-root-password "$DB_ROOT_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --mariadb-user-host-login-scope='%' \
    --install-app erpnext \
    ${FORCE_ARGS[@]+"${FORCE_ARGS[@]}"}
  bench --site "$SITE_NAME" set-config allow_cors "*"
  bench --site "$SITE_NAME" enable-scheduler || true
  # site ko volume pe move karo taake redeploy pe bachi rahe
  mv "sites/${SITE_NAME}" "${PERSIST}/${SITE_NAME}"
  ln -sfn "${PERSIST}/${SITE_NAME}" "sites/${SITE_NAME}"
  touch "$MARKER"
  echo "[onerp] install complete"
fi

# tenant store bhi volume pe, warna har redeploy pe tenants mit jaate hain
bench --site "$SITE_NAME" set-config onerp_saas_db "${PERSIST}/onerp-data/onerp_saas.db"

# Stock Website Settings signup disabled rakhti hai, jisse login page pe company
# register karne ka button hi nahi aata. Flag sirf document me hai (koi conf fallback
# nahi), isliye har web boot pe on karo -- installed sites ke liye bhi, sirf naye
# site ke liye nahi.
if [ "$ROLE" = "web" ]; then
  echo "[onerp] enabling company registration on the login page..."
  bench --site "$SITE_NAME" execute frappe.client.set_value \
    --kwargs "{'doctype':'Website Settings','name':'Website Settings','fieldname':{'disable_signup':0}}" \
    >/dev/null || echo "[onerp] WARNING: signup enable nahi hua -- Website Settings me 'Disable Signup' uncheck karo"

  # Setup Wizard na chalne ki wajah se site me koi Fiscal Year nahi hota, aur Accounting
  # workspace ka Profit and Loss chart usi pe chalta hai -- tenants ko "Start Year and
  # End Year are mandatory" ka modal aata tha. Boot pe har company ko FY de do.
  echo "[onerp] ensuring a fiscal year for every company..."
  bench --site "$SITE_NAME" execute erpnext.api.auth.ensure_fiscal_years \
    || echo "[onerp] WARNING: fiscal year backfill skip ho gaya"
fi

bench use "$SITE_NAME"
bench set-config -g default_site "$SITE_NAME"

for DOMAIN in "${RAILWAY_PUBLIC_DOMAIN:-}" ${EXTRA_DOMAINS:-}; do
  if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "$SITE_NAME" ]; then
    echo "[onerp] linking domain ${DOMAIN} -> ${SITE_NAME}"
    ln -sfn "$SITE_NAME" "sites/${DOMAIN}"
  fi
done

# gunicorn ke andar /assets aur /files serve karne ka wrapper
cat > /home/frappe/frappe-bench/onerp_wsgi.py <<'PYEOF'
import os
from werkzeug.middleware.shared_data import SharedDataMiddleware
from frappe.app import application as frappe_app

SITES = "/home/frappe/frappe-bench/sites"
SITE = os.environ.get("SITE_NAME", "frontend")

application = SharedDataMiddleware(
    frappe_app,
    {
        "/assets": os.path.join(SITES, "assets"),
        "/files": os.path.join(SITES, SITE, "public", "files"),
    },
    cache=True,
)
PYEOF

case "$ROLE" in
  web)
    echo "[onerp] starting gunicorn on :${PORT}"
    exec /home/frappe/frappe-bench/env/bin/gunicorn \
      --chdir=/home/frappe/frappe-bench/sites \
      --pythonpath=/home/frappe/frappe-bench \
      --bind=0.0.0.0:"${PORT}" \
      --workers="${WEB_WORKERS:-2}" \
      --threads="${WEB_THREADS:-4}" \
      --timeout=120 \
      onerp_wsgi:application
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
