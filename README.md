# ADAKAL GROUP - Odoo 18 Community (Docker Swarm + Patroni)

Configuration Docker ready-to-use pour Odoo 18 Community Edition avec PostgreSQL HA (Patroni), stockage S3 compatible, sur un cluster Docker Swarm 3 nœuds.

## Architecture

```
                    ┌──────────────────┐
                    │  Reverse Proxy   │
                    │  (votre Nginx)   │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │ Swarm Ingress (port 8069)    │
              ├──────────┬──────────┬────────┤
              │  Node 1  │  Node 2  │ Node 3 │
              ├──────────┴──────────┴────────┤
              │          Odoo 18             │
              │       (failover)             │
              ├──────────────────────────────┤
              │        HAProxy               │
              │   (route vers primary PG)    │
              ├──────────┬──────────┬────────┤
              │Patroni 1 │Patroni 2 │Patroni3│
              │(primary) │(replica) │(replica│
              ├──────────┼──────────┼────────┤
              │  etcd 1  │  etcd 2  │ etcd 3 │
              └──────────┴──────────┴────────┘
                             │
                    ┌────────┴─────────┐
                    │   S3 Compatible  │
                    │   (filestore)    │
                    └──────────────────┘
```

## Structure du projet

```
odoo-docker/
├── docker-compose.yml       # Mode single-node (développement)
├── docker-stack.yml         # Mode Swarm + Patroni (production)
├── Dockerfile               # Image Odoo personnalisée (dépendances S3)
├── .env                     # Variables d'environnement
├── config/
│   └── odoo.conf            # Configuration Odoo
├── patroni/
│   ├── Dockerfile           # Image PostgreSQL + Patroni
│   ├── patroni.yml          # Configuration Patroni
│   └── entrypoint.sh        # Script d'entrée Patroni
├── haproxy/
│   └── haproxy.cfg          # Routage vers le primary PostgreSQL
├── addons/                  # Modules personnalisés
├── oca-addons/              # Modules OCA S3
├── backups/                 # Sauvegardes
├── deploy.sh                # Déploiement single-node
├── deploy-swarm.sh          # Déploiement Swarm + Patroni
├── init-s3-modules.sh       # Téléchargement modules OCA
├── backup.sh                # Sauvegarde DB + filestore
└── restore.sh               # Restauration
```

## Prérequis

- 3 VPS avec Docker Engine 24+ (NVMe recommandé)
- Docker Swarm initialisé entre les 3 nœuds
- Minimum 4 Go RAM par nœud (8 Go recommandé)
- 40 Go NVMe par nœud
- Un bucket S3 compatible créé chez votre provider

## Déploiement Swarm + Patroni

### 1. Initialiser le Swarm (si pas déjà fait)

```bash
# Sur le nœud manager (node 1)
docker swarm init --advertise-addr <IP_NODE1>

# Sur les nœuds workers (node 2 et 3)
docker swarm join --token <TOKEN> <IP_NODE1>:2377
```

### 2. Copier les fichiers sur le manager

```bash
scp -r odoo-docker/ user@node1:/opt/odoo/
```

### 3. Configurer

```bash
cd /opt/odoo/odoo-docker
nano .env
nano config/odoo.conf
```

Variables à renseigner dans `.env` :

| Variable | Description | Exemple |
|----------|-------------|---------|
| `POSTGRES_USER` | Utilisateur PostgreSQL | `odoo` |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | `un_vrai_mot_de_passe` |
| `PATRONI_SUPERUSER_PASSWORD` | Superuser PostgreSQL | `super_password` |
| `PATRONI_REPLICATION_PASSWORD` | Réplication Patroni | `replicator_password` |
| `S3_ACCESS_KEY` | Clé d'accès S3 | `SCWXXXXXXXXXX` |
| `S3_SECRET_KEY` | Clé secrète S3 | `xxxxxxxx-xxxx-xxxx` |
| `S3_BUCKET` | Nom du bucket | `adakal-odoo-filestore` |
| `S3_ENDPOINT` | Endpoint S3 | `https://s3.fr-par.scw.cloud` |
| `S3_REGION` | Région | `fr-par` |

### 4. Télécharger les modules OCA S3

```bash
chmod +x init-s3-modules.sh deploy-swarm.sh deploy.sh backup.sh restore.sh
./init-s3-modules.sh
```

### 5. Lancer le déploiement

```bash
./deploy-swarm.sh
```

Le script va automatiquement :
- Vérifier que le Swarm est actif
- Attribuer les labels `node=1`, `node=2`, `node=3` aux nœuds
- Construire les images Docker (Odoo + Patroni)
- Déployer la stack complète (etcd → Patroni → HAProxy → Odoo)

### 6. Distribuer les images aux autres nœuds

```bash
# Depuis le manager
docker save adakal-odoo:18.0 | ssh user@node2 docker load
docker save adakal-odoo:18.0 | ssh user@node3 docker load
docker save adakal-patroni:16 | ssh user@node2 docker load
docker save adakal-patroni:16 | ssh user@node3 docker load
```

### 7. Accéder à Odoo

Ouvrez `http://<IP_N_IMPORTE_QUEL_NOEUD>:8069`

### 8. Configurer le stockage S3 dans Odoo

1. Activez le **mode développeur** : Settings > Developer Tools > Activate Developer Mode
2. **Settings > Technical > Apps > Update Apps List**
3. Installez dans cet ordre : `fs_storage`, `fs_attachment`, `fs_attachment_s3`
4. **Settings > Technical > Storage Backends** → créez le backend S3
5. **Settings > Technical > Attachment Locations** → activez S3 par défaut

## Configuration du reverse proxy

```nginx
upstream odoo {
    server 127.0.0.1:8069;
}

upstream odoo-chat {
    server 127.0.0.1:8072;
}

server {
    listen 443 ssl http2;
    server_name odoo.adakalgroup.com;

    ssl_certificate     /etc/letsencrypt/live/odoo.adakalgroup.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/odoo.adakalgroup.com/privkey.pem;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;
    client_max_body_size 200m;

    location / {
        proxy_pass http://odoo;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
    }

    location /longpolling {
        proxy_pass http://odoo-chat;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /websocket {
        proxy_pass http://odoo-chat;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo;
    }

    gzip on;
    gzip_types text/css text/plain application/json application/javascript text/xml application/xml;
}

server {
    listen 80;
    server_name odoo.adakalgroup.com;
    return 301 https://$server_name$request_uri;
}
```

## Commandes Swarm

| Action | Commande |
|--------|---------|
| Voir les services | `docker stack services adakal-odoo` |
| Logs Odoo | `docker service logs adakal-odoo_odoo -f` |
| Logs Patroni | `docker service logs adakal-odoo_patroni1 -f` |
| HAProxy Stats | `http://<IP>:7000` |
| Supprimer la stack | `docker stack rm adakal-odoo` |
| Mise à jour Odoo | `docker service update --image adakal-odoo:18.0 adakal-odoo_odoo` |

## Commandes Patroni

| Action | Commande |
|--------|---------|
| État du cluster PG | `docker exec $(docker ps -q -f name=patroni1) patronictl list` |
| Failover manuel | `docker exec $(docker ps -q -f name=patroni1) patronictl failover` |
| Switchover planifié | `docker exec $(docker ps -q -f name=patroni1) patronictl switchover` |
| Réinitialiser un replica | `docker exec $(docker ps -q -f name=patroni1) patronictl reinit adakal-pg patroni2` |

## Comment fonctionne le failover

**Si un nœud PostgreSQL tombe :**
Patroni détecte la perte via etcd et promeut automatiquement un replica en primary. HAProxy redirige Odoo vers le nouveau primary. Le failover prend environ 10-30 secondes. Odoo peut avoir une brève interruption pendant le basculement.

**Si le nœud Odoo tombe :**
Docker Swarm relance automatiquement Odoo sur un autre nœud disponible. Le filestore est sur S3 donc pas de perte de données. La session utilisateur sera perdue (reconnecter).

## Optimisation selon les ressources

| RAM par nœud | workers Odoo | PostgreSQL shared_buffers |
|-------------|-------------|--------------------------|
| 4 Go | 2 | 256MB |
| 8 Go | 4 | 512MB |
| 16 Go | 6 | 1GB |

Modifiez `config/odoo.conf` pour les workers Odoo et `patroni/patroni.yml` pour PostgreSQL.

## Sécurité recommandée

1. Changez **tous** les mots de passe par défaut (`.env` + `odoo.conf`)
2. Gardez `list_db = False` en production
3. Firewall : seuls les ports 80/443 exposés publiquement
4. Ports Swarm entre nœuds : 2377/tcp, 7946/tcp+udp, 4789/udp
5. Le réseau overlay est chiffré (`encrypted: true`)
6. HAProxy Stats (port 7000) uniquement en accès local
7. Sauvegardez régulièrement avec `./backup.sh`

## Mode single-node (développement)

Pour un déploiement simple sur un seul serveur, utilisez :

```bash
./deploy.sh    # utilise docker-compose.yml
```
