#!/usr/bin/env bash
set -e

BASHRC="$HOME/.bashrc"
MARKER="# === Microsoft HPC Tooling ==="

if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
cat >> "$BASHRC" << 'EOF'

# === Microsoft HPC Tooling ===
source ~/azurehpc/install.sh 2>/dev/null || true
export HPC_WIN_BIN="/mnt/c/Works/hpc-pack/bin"
# === End HPC Tooling ===
EOF
  echo "Added HPC tooling to ~/.bashrc"
else
  echo "HPC tooling already in ~/.bashrc"
fi

# Verify bash scripts
bash -n /mnt/c/Works/bash-automation/setup_env.sh && echo "setup_env.sh    : OK"
bash -n /mnt/c/Works/bash-automation/deploy_cyclecloud_cluster.sh && echo "deploy_*.sh     : OK"
bash -n /mnt/c/Works/bash-automation/submit_hpc_job.sh && echo "submit_*.sh     : OK"
bash -n /mnt/c/Works/bash-automation/cluster_health_check.sh && echo "health_check.sh : OK"