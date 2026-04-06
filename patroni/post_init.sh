#!/bin/bash
set -e

# Load secrets
POSTGRES_PASSWORD="$(tr -d '\n\r' < /run/secrets/postgres_password)"
REPLICATION_PASSWORD="$(tr -d '\n\r' < /run/secrets/patroni_replication_password)"

echo "Creating database users..."

psql -U postgres <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'odoo') THEN
            CREATE USER odoo WITH PASSWORD '${POSTGRES_PASSWORD}' CREATEDB;
            RAISE NOTICE 'User odoo created';
        END IF;
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
            CREATE USER replicator WITH PASSWORD '${REPLICATION_PASSWORD}' REPLICATION;
            RAISE NOTICE 'User replicator created';
        END IF;
    END
    \$\$;
EOSQL

echo "Database users ready"
