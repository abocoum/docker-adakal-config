#!/bin/bash
###############################################
# ADAKAL GROUP - Full Cleanup Script
# Removes stack + all volumes on ALL 3 nodes
# Run this from the MANAGER node
###############################################

set -e

echo "========================================="
echo "  ADAKAL - Full Stack Cleanup"
echo "========================================="

# 1. Remove the stack
echo ""
echo "[1/3] Removing stack 'odoo'..."
docker stack rm odoo 2>/dev/null && echo "  Stack removed." || echo "  Stack not found, skipping."

# Wait for services to fully stop
echo "  Waiting for services to stop..."
sleep 15

# 2. Clean volumes on THIS node (manager)
echo ""
echo "[2/3] Cleaning volumes on THIS node..."
for vol in $(docker volume ls -q 2>/dev/null); do
    case "$vol" in
        *patroni*|*etcd*|*odoo*)
            docker volume rm "$vol" 2>/dev/null && echo "  Removed: $vol"
            ;;
    esac
done

# 3. Clean volumes on WORKER nodes
echo ""
echo "[3/3] Cleaning volumes on WORKER nodes..."
WORKER_IPS=()

# Detect worker nodes
for NODE_ID in $(docker node ls -q); do
    ROLE=$(docker node inspect "$NODE_ID" --format '{{.Spec.Role}}')
    if [ "$ROLE" = "worker" ]; then
        # Get the node hostname/IP
        ADDR=$(docker node inspect "$NODE_ID" --format '{{.Status.Addr}}')
        HOSTNAME=$(docker node inspect "$NODE_ID" --format '{{.Description.Hostname}}')
        WORKER_IPS+=("$ADDR")
        echo "  Found worker: $HOSTNAME ($ADDR)"
    fi
done

if [ ${#WORKER_IPS[@]} -eq 0 ]; then
    echo "  No worker nodes found. If you have workers, clean them manually:"
    echo "    ssh <worker-ip> 'docker volume ls -q | grep -E \"patroni|etcd|odoo\" | xargs -r docker volume rm'"
else
    for WORKER_IP in "${WORKER_IPS[@]}"; do
        echo ""
        echo "  Cleaning volumes on $WORKER_IP ..."
        ssh -o StrictHostKeyChecking=no "$WORKER_IP" \
            'docker volume ls -q | grep -E "patroni|etcd|odoo" | xargs -r docker volume rm' \
            2>/dev/null && echo "  Done: $WORKER_IP" \
            || echo "  WARNING: Could not SSH to $WORKER_IP. Clean manually with:"
        echo "    ssh $WORKER_IP 'docker volume ls -q | grep -E \"patroni|etcd|odoo\" | xargs -r docker volume rm'"
    done
fi

# 4. Prune stopped containers
echo ""
echo "[4/4] Pruning stopped containers..."
docker container prune -f 2>/dev/null

echo ""
echo "========================================="
echo "  Cleanup complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Update admin_passwd in config/odoo.conf"
echo "  2. Rebuild Patroni image:"
echo "     cd ~/odoo-docker/patroni && docker build -t adakal-patroni:16 ."
echo "  3. Redeploy:"
echo "     cd ~/odoo-docker && bash deploy-swarm.sh"
echo ""
