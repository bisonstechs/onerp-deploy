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
