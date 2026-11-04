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

## Tenant store

`erpnext.api.saas` keeps tenants and trials in SQLite, default
`~/onerp-data/onerp_saas.db`. That path is container-local, so a redeploy wipes
it and every account silently stops being a tenant (no trial banner, no
per-tenant user scoping). Point it at the persisted volume instead:

```
ONERP_SAAS_DB=/home/frappe/persist/onerp-data/onerp_saas.db
```

Any `ONERP_*` value can also be set as a `onerp_*` key in site config.
