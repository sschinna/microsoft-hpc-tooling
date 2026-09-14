#!/usr/bin/env bash
# =============================================================================
# deploy_cyclecloud_cluster.sh
# Usage: ./deploy_cyclecloud_cluster.sh <cluster_name> <template_file>
# =============================================================================
set -euo pipefail

CLUSTER_NAME="${1:?Usage: $0 <cluster_name> <template_file>}"
TEMPLATE_FILE="${2:?Usage: $0 <cluster_name> <template_file>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

command -v cyclecloud >/dev/null || { echo "ERROR: cyclecloud CLI not found"; exit 1; }
[[ -f "$TEMPLATE_FILE" ]] || { echo "ERROR: Template not found: $TEMPLATE_FILE"; exit 1; }

echo "=== Deploying CycleCloud Cluster: $CLUSTER_NAME ==="
cyclecloud import_cluster "$CLUSTER_NAME" --file "$TEMPLATE_FILE" --force
cyclecloud start_cluster "$CLUSTER_NAME"
echo "Waiting 15s for cluster to initialize..."
sleep 15
cyclecloud show_cluster "$CLUSTER_NAME"
echo "=== Cluster '$CLUSTER_NAME' deployed! ==="
echo "Monitor: cyclecloud show_nodes $CLUSTER_NAME"