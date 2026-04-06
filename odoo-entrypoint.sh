#!/bin/bash
set -e

# Charger les Docker Secrets dans les variables d'environnement
for secret_file in /run/secrets/*; do
    if [ -f "$secret_file" ]; then
        var_name=$(basename "$secret_file" | tr '[:lower:]' '[:upper:]')
        export "$var_name"="$(tr -d '\n\r' < "$secret_file")"
    fi
done

# Substituer les placeholders dans odoo.conf avec les valeurs des secrets
CONF_TEMPLATE="/etc/odoo/odoo.conf"
CONF_RUNTIME="/tmp/odoo.conf"

cp "$CONF_TEMPLATE" "$CONF_RUNTIME"

# Remplacer les placeholders par les valeurs réelles
if [ -n "${POSTGRES_PASSWORD:-}" ]; then
    sed -i "s|__DB_PASSWORD__|${POSTGRES_PASSWORD}|g" "$CONF_RUNTIME"
fi
if [ -n "${ODOO_ADMIN_PASSWD:-}" ]; then
    sed -i "s|__ADMIN_PASSWD__|${ODOO_ADMIN_PASSWD}|g" "$CONF_RUNTIME"
fi

# Passer les credentials S3 via les variables d'environnement standard AWS
if [ -n "${S3_ACCESS_KEY:-}" ]; then
    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
fi
if [ -n "${S3_SECRET_KEY:-}" ]; then
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
fi

# Lancer Odoo avec le fichier de config généré
exec /entrypoint.sh odoo --config="$CONF_RUNTIME" "$@"
