#!/usr/bin/env bash
# =============================================================================
# submit_hpc_job.sh
# Usage: ./submit_hpc_job.sh --scheduler <headnode> --command "<cmd>" [--nodes <n>]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

SCHEDULER="${HPC_SCHEDULER:-}"; COMMAND=""; NUM_NODES="1"
while [[ $# -gt 0 ]]; do
    case $1 in
        --scheduler) SCHEDULER="$2"; shift 2 ;;
        --command)   COMMAND="$2";   shift 2 ;;
        --nodes)     NUM_NODES="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done
[[ -z "$SCHEDULER" ]] && { echo "ERROR: --scheduler required"; exit 1; }
[[ -z "$COMMAND" ]]   && { echo "ERROR: --command required";   exit 1; }

HPC_CLUSRUN="/mnt/c/Works/hpc-pack/bin/clusrun.exe"
HPC_JOB="/mnt/c/Works/hpc-pack/bin/job.exe"

echo "=== Submitting HPC Job ==="
echo "Scheduler : $SCHEDULER | Nodes: $NUM_NODES | Command: $COMMAND"
"$HPC_CLUSRUN" /scheduler:"$SCHEDULER" /nodes:"$NUM_NODES" "$COMMAND"
echo "=== Done. List jobs: $HPC_JOB list /scheduler:$SCHEDULER ==="