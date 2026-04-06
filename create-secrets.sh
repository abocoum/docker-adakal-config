#!/bin/bash
# ============================================
# ADAKAL GROUP - Création sécurisée des Docker Secrets
# ============================================
# Ce script crée les secrets Docker Swarm de manière sécurisée :
#   - Lecture silencieuse (pas d'affichage, pas d'historique shell)
#   - Fichier temporaire détruit après utilisation
# À exécuter UNE SEULE FOIS depuis le nœud MANAGER
# ============================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Vérifier qu'on est dans un Swarm manager
if ! docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q "true"; then
    echo -e "${RED}[✗]${NC} Ce script doit être exécuté depuis un nœud MANAGER du Swarm."
    exit 1
fi

TMP_FILE=$(mktemp /tmp/.docker_secret_XXXXXX)
trap 'shred -u "$TMP_FILE" 2>/dev/null || rm -f "$TMP_FILE"' EXIT

create_secret() {
    local secret_name="$1"
    local prompt_msg="$2"

    # Vérifier si le secret existe déjà
    if docker secret inspect "$secret_name" > /dev/null 2>&1; then
        echo -e "${YELLOW}[!]${NC} Le secret '${secret_name}' existe déjà. Passer ? (O/n) "
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            return 0
        fi
        echo -e "  Suppression de l'ancien secret..."
        docker secret rm "$secret_name" > /dev/null 2>&1 || true
    fi

    echo -n -e "${BLUE}${prompt_msg}${NC} "
    read -s val
    echo

    if [ -z "$val" ]; then
        echo -e "${RED}[✗]${NC} Valeur vide non autorisée pour '${secret_name}'."
        exit 1
    fi

    printf '%s' "$val" > "$TMP_FILE"
    docker secret create "$secret_name" "$TMP_FILE" > /dev/null
    shred -u "$TMP_FILE" 2>/dev/null || rm -f "$TMP_FILE"
    TMP_FILE=$(mktemp /tmp/.docker_secret_XXXXXX)

    echo -e "${GREEN}[✓]${NC} Secret '${secret_name}' créé"
}

echo -e "\n${BLUE}============================================${NC}"
echo -e "${BLUE}  ADAKAL GROUP - Création des Docker Secrets${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Les mots de passe ne seront PAS affichés.\n"

create_secret "postgres_password"             "Mot de passe PostgreSQL (utilisateur odoo) :"
create_secret "patroni_superuser_password"    "Mot de passe superuser PostgreSQL :"
create_secret "patroni_replication_password"  "Mot de passe réplication Patroni :"
create_secret "odoo_admin_passwd"             "Mot de passe master Odoo (admin_passwd) :"
create_secret "s3_access_key"                 "Clé d'accès S3 (Access Key) :"
create_secret "s3_secret_key"                 "Clé secrète S3 (Secret Key) :"

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  Tous les secrets ont été créés !${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "\nVérification :"
docker secret ls
echo ""
