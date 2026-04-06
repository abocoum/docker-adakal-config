#!/bin/bash
set -e

# Load Docker Secrets into environment variables
for secret_file in /run/secrets/*; do
    if [ -f "$secret_file" ]; then
        var_name=$(basename "$secret_file" | tr '[:lower:]' '[:upper:]')
        export "$var_name"="$(tr -d '\n\r' < "$secret_file")"
    fi
done

# Map secrets to the env vars the official Odoo entrypoint expects
export PASSWORD="${POSTGRES_PASSWORD}"
export ODOO_ADMIN_PASSWD="${ODOO_ADMIN_PASSWD:-}"

# S3 credentials
[ -n "${S3_ACCESS_KEY:-}" ] && export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
[ -n "${S3_SECRET_KEY:-}" ] && export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"

# Delegate to the official Odoo entrypoint
exec /entrypoint.sh odoo "$@"
