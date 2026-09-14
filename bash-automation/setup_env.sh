#!/usr/bin/env bash
# =============================================================================
# setup_env.sh - Microsoft HPC Tooling Environment Setup
# Source this file: . setup_env.sh
# =============================================================================
set -euo pipefail

export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
export AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-my-hpc-rg}"
export AZURE_LOCATION="${AZURE_LOCATION:-eastus}"

export HPC_SCHEDULER="${HPC_SCHEDULER:-headnode.example.com}"
export HPC_BIN="/mnt/c/Works/hpc-pack/bin"
export PATH="$HPC_BIN:$PATH"

export CYCLECLOUD_URL="${CYCLECLOUD_URL:-https://your-cyclecloud-server.example.com}"
export CYCLECLOUD_USERNAME="${CYCLECLOUD_USERNAME:-admin}"

AZHPC_DIR="$HOME/azurehpc"
if [[ -d "$AZHPC_DIR" ]]; then
    source "$AZHPC_DIR/install.sh"
fi

echo "=== HPC Tooling Environment ==="
echo "CycleCloud CLI : $(cyclecloud --version 2>/dev/null || echo not found)"
echo "Azure CLI      : $(az --version 2>/dev/null | head -1 || echo not found)"
echo "jq             : $(jq --version 2>/dev/null || echo not found)"
echo "azhpc-build    : $(command -v azhpc-build 2>/dev/null && echo available || echo not found)"
echo "HPC_SCHEDULER  : ${HPC_SCHEDULER}"
echo "CYCLECLOUD_URL : ${CYCLECLOUD_URL}"
echo "AZURE_LOCATION : ${AZURE_LOCATION}"
echo "================================"
echo "Next: set AZURE_SUBSCRIPTION_ID, HPC_SCHEDULER, CYCLECLOUD_URL, run: az login, cyclecloud initialize"