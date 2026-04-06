#!/bin/bash
set -e

# Charger les Docker Secrets dans les variables d'environnement
# Les secrets sont montés dans /run/secrets/<nom_secret>
for secret_file in /run/secrets/*; do
    if [ -f "$secret_file" ]; then
        var_name=$(basename "$secret_file" | tr '[:lower:]' '[:upper:]')
        export "$var_name"="$(tr -d '\n\r' < "$secret_file")"
    fi
done

# Substituer les variables d'environnement dans patroni.yml
envsubst < /etc/patroni/patroni.yml > /tmp/patroni.yml

# Lancer Patroni
exec patroni /tmp/patroni.yml
