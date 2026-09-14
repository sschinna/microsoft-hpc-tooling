#!/usr/bin/env bash
# =============================================================================
# cluster_health_check.sh
# Usage: ./cluster_health_check.sh [--cyclecloud <cluster>] [--hpc <scheduler>]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

CC_CLUSTER=""; HPC_SCHED="${HPC_SCHEDULER:-}"
while [[ $# -gt 0 ]]; do
    case $1 in
        --cyclecloud) CC_CLUSTER="$2"; shift 2 ;;
        --hpc)        HPC_SCHED="$2";  shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

echo "=== HPC Cluster Health Check === $(date)"
if [[ -n "$CC_CLUSTER" ]]; then
    echo "--- CycleCloud: $CC_CLUSTER ---"
    cyclecloud show_cluster "$CC_CLUSTER" 2>/dev/null || echo "WARNING: CycleCloud unreachable"
    cyclecloud show_nodes "$CC_CLUSTER" 2>/dev/null   || echo "WARNING: Could not get nodes"
fi
if [[ -n "$HPC_SCHED" ]]; then
    echo "--- HPC Pack: $HPC_SCHED ---"
    /mnt/c/Works/hpc-pack/bin/node.exe list /scheduler:"$HPC_SCHED" 2>/dev/null || echo "WARNING: HPC scheduler unreachable"
    /mnt/c/Works/hpc-pack/bin/job.exe  list /scheduler:"$HPC_SCHED" /status:Running 2>/dev/null || echo "No running jobs or cannot connect"
fi
echo "=== Health Check Complete ==="