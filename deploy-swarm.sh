#!/bin/bash
# ============================================
# ADAKAL GROUP - Deploy Odoo 18 on Docker Swarm
# Patroni (PostgreSQL HA) + etcd + HAProxy
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

STACK_NAME="adakal-odoo"
REGISTRY="ghcr.io/abocoum"
VERSION=$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC} $1"; }
header()   { echo -e "\n${BLUE}=== $1 ===${NC}"; }

die() { log_err "$1"; exit 1; }

# ============================================
# 1. Preflight checks
# ============================================
header "[1/5] Preflight checks"

# Swarm active & manager role
docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active" \
    || die "This node is not in an active Swarm. Run: docker swarm init --advertise-addr <IP>"
[ "$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null)" = "true" ] \
    || die "This script must run on a MANAGER node."
log_ok "Swarm manager confirmed"

# Node count
NODE_COUNT=$(docker node ls -q | wc -l)
echo -e "  Nodes in cluster: ${BLUE}${NODE_COUNT}${NC}"
[ "$NODE_COUNT" -lt 3 ] && log_warn "3 nodes recommended for HA (current: $NODE_COUNT)"

# Node labels
for i in 1 2 3; do
    FOUND="no"
    for nid in $(docker node ls -q); do
        LABEL=$(docker node inspect "$nid" --format '{{index .Spec.Labels "node"}}' 2>/dev/null || true)
        if [ "$LABEL" = "$i" ]; then
            FOUND="yes"
            break
        fi
    done
    [ "$FOUND" = "yes" ] || die "Missing label node=$i. Assign with: docker node update --label-add node=$i <HOSTNAME>"
done
log_ok "Node labels node=1,2,3 present"

# Required files
for f in docker-stack.yml VERSION config/odoo.conf haproxy/haproxy.cfg; do
    [ -f "$f" ] || die "Missing file: $f"
done
log_ok "Configuration files present"

# Docker secrets
REQUIRED_SECRETS=(postgres_password patroni_superuser_password patroni_replication_password odoo_admin_passwd s3_access_key s3_secret_key)
for s in "${REQUIRED_SECRETS[@]}"; do
    docker secret inspect "$s" > /dev/null 2>&1 || die "Missing secret: $s — Run: bash create-secrets.sh"
done
log_ok "Docker secrets present"

# ============================================
# 2. Pull images from registry
# ============================================
header "[2/5] Pull images (v${VERSION})"

IMAGES=(
    "${REGISTRY}/adakal-odoo:${VERSION}"
    "${REGISTRY}/adakal-patroni:${VERSION}"
)

for img in "${IMAGES[@]}"; do
    docker pull "$img"
    log_ok "$img"
done

# ============================================
# 3. Deploy Swarm configs
# ============================================
header "[3/5] Deploy Swarm configs"

deploy_config() {
    local name="$1" file="$2"
    if docker config inspect "$name" > /dev/null 2>&1; then
        log_warn "Config $name already exists (skipping). Remove stack first to update."
    else
        docker config create "$name" "$file"
        log_ok "Config $name created"
    fi
}

deploy_config "${STACK_NAME}_haproxy-cfg" haproxy/haproxy.cfg
deploy_config "${STACK_NAME}_odoo-conf"   config/odoo.conf

# ============================================
# 4. Deploy stack
# ============================================
header "[4/5] Deploy stack"

if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

docker stack deploy -c docker-stack.yml --with-registry-auth "$STACK_NAME"
log_ok "Stack '${STACK_NAME}' deployed"

# ============================================
# 5. Health check
# ============================================
header "[5/5] Health check"

TIMEOUT=120
INTERVAL=5
ELAPSED=0

echo -n "  Waiting for services"
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    RUNNING=$(docker stack services "$STACK_NAME" --format '{{.Replicas}}' 2>/dev/null | grep -c "1/1" || true)
    TOTAL=$(docker stack services "$STACK_NAME" --format '{{.Replicas}}' 2>/dev/null | wc -l)
    if [ "$RUNNING" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        echo -e " ${GREEN}OK${NC}"
        break
    fi
    echo -n "."
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo ""
    log_warn "Timeout after ${TIMEOUT}s — some services may still be starting"
fi

echo ""
docker stack services "$STACK_NAME"

# ============================================
# Summary
# ============================================
MANAGER_IP=$(docker node inspect self --format '{{.Status.Addr}}' 2>/dev/null || hostname -I | awk '{print $1}')

cat <<EOF

${GREEN}============================================${NC}
${GREEN}  DEPLOYMENT COMPLETE (v${VERSION})${NC}
${GREEN}============================================${NC}

  ${BLUE}Access:${NC}
  Odoo           http://${MANAGER_IP}:8069
  HAProxy Stats  http://${MANAGER_IP}:7000

  ${YELLOW}Useful commands:${NC}
  docker stack services ${STACK_NAME}
  docker service logs ${STACK_NAME}_odoo -f
  docker exec \$(docker ps -q -f name=patroni1) patronictl list
  docker stack rm ${STACK_NAME}
EOF
