# onerp-deploy

Docker + Railway deploy config for customized Onerp (Frappe/ERPNext v15).

- Frappe: https://github.com/arshad-dev57/onerp-frappe
- ERPNext: https://github.com/arshad-dev57/onerp-erpnext

## Railway `web` service

Connect this repo to the `web` service.

Required env vars:

- MYSQLHOST, MYSQLPORT, MYSQLUSER, MYSQLPASSWORD, MYSQLDATABASE, MYSQL_ROOT_PASSWORD
- REDIS_URL (or REDISHOST / REDISPORT / REDISPASSWORD)
- ADMIN_PASSWORD
- SITE_NAME=frontend (optional)

First Docker build can take 15–30+ minutes. Site is auto-created on first boot.

## Shipping app changes

Every build clones both forks at `main`, so pushing there is what ships desk
changes — the image rebuilds assets during `bench init`. This repo only needs a
commit when its own files change; Railway starts a build on that push. Pushing
to the forks alone does not wake Railway, so to ship app-only changes either
Redeploy the `web` service in the dashboard or commit a docs change here.

## Base data on a fresh site

`bench new-site --install-app erpnext` installs the app but never runs the Setup
Wizard, so ERPNext's base records (Warehouse Type `Transit`, UOMs, Item Groups,
Territories, Address Templates) are absent and the first company insert dies with
`Could not find Warehouse Type: Transit` — the "Goods In Transit" warehouse every
new Company creates links to that row. `erpnext.api.auth.register_company`
installs them once, guarded on that row, so the site's first registration seeds
the data and the rest register normally.

## Tenant store

`erpnext.api.saas` keeps tenants and trials in SQLite, default
`~/onerp-data/onerp_saas.db`. That path is container-local, so a redeploy wipes
it and every account silently stops being a tenant (no trial banner, no
per-tenant user scoping). The entrypoint therefore writes the persisted path
into site config on every boot:

```
onerp_saas_db = ${PERSIST_DIR:-/home/frappe/persist}/onerp-data/onerp_saas.db
```

A `ONERP_SAAS_DB` env var still overrides it, and any other `ONERP_*` value can
also be set as a `onerp_*` key in site config.

## Company registration

Stock `Website Settings` ships with **Disable Signup** checked, which hides the
Register tab on `/#login` — the tab that runs the Onerp company signup. There is
no conf fallback for that flag, so the entrypoint clears the document on each
web boot. Sites installed before this commit get fixed by the next deploy, no
manual uncheck needed.
