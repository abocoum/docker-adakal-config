#!/bin/bash
set -e

# Load Docker Secrets into environment variables
for secret_file in /run/secrets/*; do
    if [ -f "$secret_file" ]; then
        var_name=$(basename "$secret_file" | tr '[:lower:]' '[:upper:]')
        export "$var_name"="$(tr -d '\n\r' < "$secret_file")"
    fi
done

# Substitute environment variables into patroni.yml
envsubst < /etc/patroni/patroni.yml > /tmp/patroni.yml

# Wait for at least one etcd host to be reachable
echo "Waiting for etcd..."
until curl -sf "http://${PATRONI_ETCD3_HOST1}/version" > /dev/null 2>&1 || \
      curl -sf "http://${PATRONI_ETCD3_HOST2}/version" > /dev/null 2>&1 || \
      curl -sf "http://${PATRONI_ETCD3_HOST3}/version" > /dev/null 2>&1; do
    sleep 2
done
echo "etcd is reachable"

exec patroni /tmp/patroni.yml
