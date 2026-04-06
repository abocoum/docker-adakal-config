#!/bin/bash
# ============================================
# ADAKAL GROUP - Déploiement Odoo 18 sur Docker Swarm
# avec Patroni (PostgreSQL HA) + etcd + HAProxy
# ============================================
# À exécuter depuis le nœud MANAGER du Swarm
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

STACK_NAME="adakal-odoo"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

echo -e "\n${BLUE}============================================${NC}"
echo -e "${BLUE}  ADAKAL GROUP - Odoo 18 Swarm + Patroni${NC}"
echo -e "${BLUE}============================================${NC}"

# -------------------------------------------
# 1. Vérifications Swarm
# -------------------------------------------
echo -e "\n${BLUE}=== [1/7] Vérification du Swarm ===${NC}"

if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
    print_error "Ce nœud n'est pas dans un Swarm actif."
    echo "  Initialisez avec : docker swarm init --advertise-addr <IP_MANAGER>"
    exit 1
fi
print_step "Swarm actif"

NODE_ROLE=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null)
if [ "$NODE_ROLE" != "true" ]; then
    print_error "Ce script doit être exécuté depuis un nœud MANAGER."
    exit 1
fi
print_step "Nœud manager confirmé"

NODE_COUNT=$(docker node ls --format '{{.ID}}' | wc -l)
echo -e "  Nœuds dans le cluster : ${BLUE}${NODE_COUNT}${NC}"

if [ "$NODE_COUNT" -lt 3 ]; then
    print_warn "3 nœuds recommandés pour Patroni (actuellement: $NODE_COUNT)"
fi

# -------------------------------------------
# 2. Labels des nœuds
# -------------------------------------------
echo -e "\n${BLUE}=== [2/7] Configuration des labels ===${NC}"

# Vérifier les labels node=1, node=2, node=3
LABELED_NODES=0
for i in 1 2 3; do
    HAS_LABEL=$(docker node ls --format '{{.ID}}' | while read id; do
        labels=$(docker node inspect "$id" --format '{{range $k,$v := .Spec.Labels}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
        if echo "$labels" | grep -q "node=$i"; then echo "yes"; fi
    done | head -1)
    if [ "$HAS_LABEL" = "yes" ]; then
        LABELED_NODES=$((LABELED_NODES + 1))
    fi
done

if [ "$LABELED_NODES" -lt 3 ]; then
    print_warn "Les nœuds doivent avoir les labels node=1, node=2, node=3"
    echo ""
    echo "  Nœuds disponibles :"
    docker node ls --format "  {{.ID}}  {{.Hostname}}  {{.Status}}  {{.ManagerStatus}}"
    echo ""
    echo "  Appliquez les labels manuellement :"
    echo "    docker node update --label-add node=1 <NODE1_HOSTNAME>"
    echo "    docker node update --label-add node=2 <NODE2_HOSTNAME>"
    echo "    docker node update --label-add node=3 <NODE3_HOSTNAME>"
    echo ""
    read -p "  Voulez-vous les attribuer automatiquement dans l'ordre affiché ? (o/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Oo]$ ]]; then
        NODE_NUM=1
        for id in $(docker node ls --format '{{.ID}}'); do
            if [ $NODE_NUM -le 3 ]; then
                HOSTNAME=$(docker node inspect "$id" --format '{{.Description.Hostname}}')
                docker node update --label-add "node=$NODE_NUM" "$id" > /dev/null
                print_step "Label node=$NODE_NUM → $HOSTNAME"
                NODE_NUM=$((NODE_NUM + 1))
            fi
        done
    else
        print_error "Appliquez les labels et relancez le script."
        exit 1
    fi
else
    print_step "Labels node=1, node=2, node=3 configurés"
fi

# -------------------------------------------
# 3. Vérification des fichiers
# -------------------------------------------
echo -e "\n${BLUE}=== [3/7] Vérification des fichiers ===${NC}"

for f in ".env" "config/odoo.conf" "Dockerfile" "patroni/Dockerfile" "patroni/patroni.yml" "patroni/entrypoint.sh" "haproxy/haproxy.cfg" "docker-stack.yml"; do
    if [ ! -f "$f" ]; then
        print_error "Fichier manquant : $f"
        exit 1
    fi
done
print_step "Tous les fichiers de configuration présents"

if [ ! -d "oca-addons" ] || [ -z "$(ls -A oca-addons 2>/dev/null)" ]; then
    print_warn "Dossier oca-addons vide. Exécutez ./init-s3-modules.sh d'abord."
fi

# -------------------------------------------
# 4. Build des images
# -------------------------------------------
echo -e "\n${BLUE}=== [4/7] Construction des images Docker ===${NC}"

echo "  Build de l'image Odoo..."
docker build -t adakal-odoo:18.0 -f Dockerfile .
print_step "Image adakal-odoo:18.0 construite"

echo "  Build de l'image Patroni..."
docker build -t adakal-patroni:16 -f patroni/Dockerfile patroni/
print_step "Image adakal-patroni:16 construite"

echo ""
print_warn "Les images doivent être présentes sur CHAQUE nœud."
echo "  Distribuez avec :"
echo "    docker save adakal-odoo:18.0 | ssh user@node2 docker load"
echo "    docker save adakal-patroni:16 | ssh user@node2 docker load"
echo "  (répétez pour chaque nœud)"
echo ""
read -p "  Images distribuées ou prêtes ? (O/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Distribuez les images et relancez le script."
    exit 0
fi

# -------------------------------------------
# 5. Déployer les configs dans Swarm
# -------------------------------------------
echo -e "\n${BLUE}=== [5/7] Déploiement des configurations ===${NC}"

# HAProxy config
docker config rm ${STACK_NAME}_haproxy-cfg 2>/dev/null || true
docker config create ${STACK_NAME}_haproxy-cfg haproxy/haproxy.cfg
print_step "Config HAProxy déployée"

# Odoo config
docker config rm ${STACK_NAME}_odoo-conf 2>/dev/null || true
docker config create ${STACK_NAME}_odoo-conf config/odoo.conf
print_step "Config Odoo déployée"

# -------------------------------------------
# 6. Déployer la stack
# -------------------------------------------
echo -e "\n${BLUE}=== [6/7] Déploiement de la stack ===${NC}"

export $(grep -v '^#' .env | grep -v '^\s*$' | xargs)

docker stack deploy -c docker-stack.yml "$STACK_NAME"
print_step "Stack '$STACK_NAME' déployée"

# -------------------------------------------
# 7. Vérification
# -------------------------------------------
echo -e "\n${BLUE}=== [7/7] Vérification du démarrage ===${NC}"

echo -n "Attente des services (peut prendre 1-2 min)"
for i in $(seq 1 40); do
    RUNNING=$(docker stack services "$STACK_NAME" --format '{{.Replicas}}' 2>/dev/null | grep -c "1/1" || true)
    TOTAL=$(docker stack services "$STACK_NAME" --format '{{.Replicas}}' 2>/dev/null | wc -l)
    if [ "$RUNNING" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        echo -e " ${GREEN}OK${NC}"
        break
    fi
    echo -n "."
    sleep 5
done

echo ""
docker stack services "$STACK_NAME"

# -------------------------------------------
# Résumé
# -------------------------------------------
MANAGER_IP=$(docker node inspect self --format '{{.Status.Addr}}' 2>/dev/null || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  DÉPLOIEMENT SWARM + PATRONI TERMINÉ !${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  ${BLUE}Architecture :${NC}"
echo -e "  ┌─────────────────────────────────────────┐"
echo -e "  │  Client → Reverse Proxy → Odoo (:8069)  │"
echo -e "  │                ↓                         │"
echo -e "  │         HAProxy (:5432)                  │"
echo -e "  │         ↙     ↓     ↘                    │"
echo -e "  │  Patroni1  Patroni2  Patroni3            │"
echo -e "  │  (primary)  (replica) (replica)           │"
echo -e "  │         ↕     ↕     ↕                    │"
echo -e "  │    etcd1    etcd2    etcd3                │"
echo -e "  └─────────────────────────────────────────┘"
echo ""
echo -e "  Interface Odoo    : ${BLUE}http://${MANAGER_IP}:${ODOO_PORT:-8069}${NC}"
echo -e "  HAProxy Stats     : ${BLUE}http://${MANAGER_IP}:7000${NC}"
echo -e "  (accessible via l'IP de N'IMPORTE quel nœud)"
echo ""
echo -e "  ${YELLOW}Commandes Patroni :${NC}"
echo -e "  Voir le cluster PG    : docker exec \$(docker ps -q -f name=patroni1) patronictl list"
echo -e "  Failover manuel       : docker exec \$(docker ps -q -f name=patroni1) patronictl failover"
echo -e "  Switchover planifié   : docker exec \$(docker ps -q -f name=patroni1) patronictl switchover"
echo ""
echo -e "  ${YELLOW}Commandes Stack :${NC}"
echo -e "  Voir les services     : docker stack services ${STACK_NAME}"
echo -e "  Logs Odoo             : docker service logs ${STACK_NAME}_odoo -f"
echo -e "  Logs Patroni          : docker service logs ${STACK_NAME}_patroni1 -f"
echo -e "  Supprimer la stack    : docker stack rm ${STACK_NAME}"
echo ""
