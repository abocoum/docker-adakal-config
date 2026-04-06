FROM postgres:16-bookworm

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-psycopg2 \
    python3-yaml \
    python3-urllib3 \
    python3-certifi \
    python3-requests \
    gettext-base \
    curl \
    && pip3 install --break-system-packages patroni[etcd3] \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Script d'entrée Patroni
COPY patroni.yml /etc/patroni/patroni.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5432 8008

USER postgres
ENTRYPOINT ["/entrypoint.sh"]
