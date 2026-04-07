#!/bin/bash
# ============================================
# Fetch OCA modules for Odoo 18.0
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCA_DIR="$SCRIPT_DIR/oca-addons"
BRANCH="18.0"

mkdir -p "$OCA_DIR"

# OCA repos to fetch
REPOS=(
    "OCA/web"
    "OCA/server-ux"
    "OCA/reporting-engine"
)

echo "=== Fetching OCA modules (branch: $BRANCH) ==="

for repo in "${REPOS[@]}"; do
    name=$(basename "$repo")
    target="$OCA_DIR/_repos/$name"

    if [ -d "$target" ]; then
        echo "Updating $repo..."
        git -C "$target" pull --ff-only
    else
        echo "Cloning $repo..."
        mkdir -p "$OCA_DIR/_repos"
        git clone --depth 1 --branch "$BRANCH" "https://github.com/$repo.git" "$target"
    fi

    # Symlink each addon into the flat oca-addons directory
    for addon in "$target"/*/; do
        addon_name=$(basename "$addon")
        # Skip non-addon dirs (setup, .github, etc.)
        if [ -f "$addon/__manifest__.py" ]; then
            ln -sfn "$addon" "$OCA_DIR/$addon_name"
        fi
    done
done

echo ""
echo "=== OCA modules ready ==="
echo "Addons available in: $OCA_DIR"
ls -1 "$OCA_DIR" | grep -v _repos | head -30
echo "..."
echo "Total: $(ls -1 "$OCA_DIR" | grep -v _repos | wc -l) modules"
