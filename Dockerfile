# Onerp / ERPNext v15 image for Railway (single-site, multi-company)
# First build may take 15–30 minutes.
FROM python:3.11-slim-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    NVM_DIR=/home/frappe/.nvm \
    PATH=/home/frappe/.nvm/versions/node/v18.20.5/bin:/home/frappe/.local/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git redis-tools mariadb-client \
    build-essential python3-dev libffi-dev libssl-dev \
    libmariadb-dev pkg-config \
    libjpeg62-turbo-dev zlib1g-dev liblcms2-dev libwebp-dev \
    libtiff5-dev libopenjp2-7-dev \
    fontconfig libxrender1 xfonts-75dpi xfonts-base \
    wait-for-it ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/wkhtml.deb \
      https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && apt-get update && apt-get install -y /tmp/wkhtml.deb \
    && rm -f /tmp/wkhtml.deb && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash frappe \
    && pip install --no-cache-dir "click==8.1.7" "frappe-bench==5.22.9" \
    && mkdir -p /home/frappe && chown -R frappe:frappe /home/frappe

USER frappe
WORKDIR /home/frappe

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 18.20.5 \
    && nvm alias default 18.20.5 \
    && npm install -g yarn

FROM base AS builder
USER frappe
WORKDIR /home/frappe
COPY --chown=frappe:frappe apps.json /opt/apps.json

RUN . "$NVM_DIR/nvm.sh" \
    && bench init \
      --frappe-branch=main \
      --frappe-path=https://github.com/arshad-dev57/onerp-frappe \
      --apps_path=/opt/apps.json \
      --skip-redis-config-generation \
      --no-procfile \
      --no-backups \
      frappe-bench \
    && cd frappe-bench \
    && find apps -name .git -type d -prune -exec rm -rf {} + \
    && echo '{}' > sites/common_site_config.json

FROM base AS runtime
USER frappe
WORKDIR /home/frappe
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench
COPY --chown=frappe:frappe scripts/entrypoint.sh /home/frappe/entrypoint.sh
RUN chmod +x /home/frappe/entrypoint.sh

ENV SITE_NAME=frontend \
    LISTEN_PORT=8000

WORKDIR /home/frappe/frappe-bench
EXPOSE 8000
ENTRYPOINT ["/home/frappe/entrypoint.sh"]
CMD ["web"]
