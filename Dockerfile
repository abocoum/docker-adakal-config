FROM odoo:18.0

USER root

# Install additional system dependencies for OCA modules (S3, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-boto3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Entrypoint wrapper pour charger les Docker Secrets
COPY odoo-entrypoint.sh /odoo-entrypoint.sh
RUN chmod +x /odoo-entrypoint.sh

USER odoo

ENTRYPOINT ["/odoo-entrypoint.sh"]
