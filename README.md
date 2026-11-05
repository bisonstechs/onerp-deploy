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
commit when its own files change; Railway starts a build on that push.

The `bench init` layer that does the cloning is cached by Docker on `apps.json`
alone, so a fork push on its own ships nothing and Railway finishes in under a
minute. The two `ADD`s above that layer in the Dockerfile re-fetch each fork's
`commits/main.atom` on every build, so the clone reruns whenever either `main`
moves. A real app rebuild is the slow one — 15–30 minutes.

Railway only builds on a push to *this* repo, so after pushing app changes, land
any commit here (or press Redeploy in the dashboard) to start that rebuild.

## Base data on a fresh site

`bench new-site --install-app erpnext` installs the app but never runs the Setup
Wizard, so ERPNext's base records (Warehouse Type `Transit`, UOMs, Item Groups,
Territories, Address Templates) are absent and the first company insert dies with
`Could not find Warehouse Type: Transit` — the "Goods In Transit" warehouse every
new Company creates links to that row. `erpnext.api.auth.register_company`
installs them once, guarded on that row, so the site's first registration seeds
the data and the rest register normally.

The same skipped wizard leaves a second hole: `Installed Application.is_setup_complete`
stays `0`, and while it is `0` the desk reroutes every `/app` visit to `setup-wizard` —
a page a company owner's roles cannot open, so a new tenant's first screen is
"Not permitted". Frappe only recomputes those flags during install/migrate, so
`register_company` now marks them once a Company and a real System User exist. The
flag is site-wide: the first registration after this ships also unblocks tenants that
registered earlier.

Third hole from the same skipped wizard: no `Fiscal Year` row exists (the wizard's
`create_fiscal_year_and_company` is what normally makes one). Nothing fails until the
tenant opens the Accounting workspace, whose *Profit and Loss* chart runs the P&L
report with `from_fiscal_year = erpnext.utils.get_fiscal_year()`; with no fiscal year
that raises `Start Year and End Year are mandatory` as a modal, and signup looks broken.
`erpnext.api.auth.ensure_fiscal_years()` gives each company a fiscal year covering
today, using the wizard's country calendar (Pakistan Jul–Jun, most others Jan–Dec) and
scoping the row to that company so different calendars can coexist on one site. It runs
from `register_company` and again on every web boot, so existing tenants are backfilled
without re-registering.

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
