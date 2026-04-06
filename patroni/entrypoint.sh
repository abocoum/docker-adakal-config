#!/bin/bash
set -e

# Substituer les variables d'environnement dans patroni.yml
envsubst < /etc/patroni/patroni.yml > /tmp/patroni.yml

# Lancer Patroni
exec patroni /tmp/patroni.yml
