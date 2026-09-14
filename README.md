# Microsoft HPC Tooling — Setup, Prerequisites & Running Bash Jobs

This workspace (`C:\Works`) contains a fully configured Microsoft HPC tooling stack for both **Windows** (PowerShell/CMD) and **Linux** (WSL2 Ubuntu/Bash). This guide covers prerequisites, environment setup, and how to run batch/bash jobs end-to-end.

---

## Table of Contents

1. [Workspace Layout](#workspace-layout)
2. [Prerequisites](#prerequisites)
   - [Windows Prerequisites](#windows-prerequisites)
   - [WSL / Linux Prerequisites](#wsl--linux-prerequisites)
3. [First-Time Setup](#first-time-setup)
4. [Running Bash Jobs](#running-bash-jobs)
   - [Option A — HPC Pack (clusrun / job.exe)](#option-a--hpc-pack-clusrun--jobexe)
   - [Option B — Azure CycleCloud CLI](#option-b--azure-cyclecloud-cli)
   - [Option C — azurehpc Automation Framework](#option-c--azurehpc-automation-framework)
   - [Option D — Custom Automation Scripts](#option-d--custom-automation-scripts)
5. [Bash Automation Scripts Reference](#bash-automation-scripts-reference)
6. [HPC Pack CLI Reference](#hpc-pack-cli-reference)
7. [CycleCloud CLI Reference](#cyclecloud-cli-reference)
8. [Troubleshooting](#troubleshooting)

---

## Workspace Layout

```
C:\Works\
├── hpc-pack\                        HPC Pack 2019 Client Utilities
│   ├── bin\                         CLI executables (job.exe, clusrun.exe, etc.)
│   └── powershell\Microsoft.Hpc\    PowerShell module (v6.0.0.0)
│
├── bash-automation\                 Custom Bash automation scripts
│   ├── setup_env.sh                 Environment bootstrap (EDIT THIS FIRST)
│   ├── deploy_cyclecloud_cluster.sh Deploy a CycleCloud cluster from template
│   ├── submit_hpc_job.sh            Submit parallel jobs via HPC Pack
│   └── cluster_health_check.sh     Cluster diagnostics & health check
│
├── cyclecloud-dist\                 CycleCloud CLI packages & Python SDK wheel
│   ├── cyclecloud-cli.zip           Windows CLI installer (used during setup)
│   ├── cyclecloud-cli-linux-amd64.tar.gz  Linux CLI (used during setup)
│   └── cyclecloud_api-8.9.4-py2.py3-none-any.whl  Python SDK
│
├── cyclecloud-installer\            Extracted CycleCloud CLI installer files
│
└── hpc-pack-client\                 Original MSI administrative extract

WSL Ubuntu ~/azurehpc\              Microsoft azurehpc automation framework
C:\Users\banda\.cycle\cli\bin\      CycleCloud Windows CLI (cyclecloud.exe)
/usr/local/bin/cyclecloud           CycleCloud Linux CLI (WSL)
```

---

## Prerequisites

### Windows Prerequisites

| Tool | Version Installed | Required |
|------|------------------|----------|
| Windows 10/11 or Windows Server | — | ✅ |
| WSL2 (Ubuntu) | Ubuntu 24.04 | ✅ |
| Python | 3.12.10 | ✅ |
| Azure CLI | 2.90.0 | ✅ |
| Git | 2.55.0 | ✅ |
| HPC Pack 2019 Client | 6.0.7205.0 | ✅ Installed |
| CycleCloud CLI | 8.9.4-3895 | ✅ Installed |
| CycleCloud Python SDK | 8.9.4 | ✅ Installed |

> **Note:** To install HPC Pack globally (for all users), run the MSI as Administrator:
> ```powershell
> Start-Process msiexec -ArgumentList '/i "$env:TEMP\HpcClient_x64.msi" /qn' -Verb RunAs -Wait
> ```
> The download is at: https://www.microsoft.com/en-us/download/details.aspx?id=101361

---

### WSL / Linux Prerequisites

| Tool | Version Installed | Required |
|------|------------------|----------|
| WSL2 Ubuntu | 24.04 (Noble) | ✅ |
| Bash | 5.3.9 | ✅ |
| Python 3 | 3.14.4 | ✅ |
| Azure CLI (native Linux) | 2.90.0 | ✅ Installed |
| CycleCloud CLI | 8.9.4-3895 | ✅ Installed |
| jq | 1.8.1 | ✅ Installed |
| rsync | 3.4.1 | ✅ Installed |
| git | 2.53.0 | ✅ Installed |
| azurehpc framework | latest | ✅ Cloned |

To install missing prerequisites manually in WSL:
```bash
# Update package lists
sudo apt-get update

# Install core tools
sudo apt-get install -y jq rsync git curl wget python3 python3-pip

# Install Azure CLI (native Linux)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install CycleCloud CLI (from local package)
tar -xzf /mnt/c/Works/cyclecloud-dist/cyclecloud-cli-linux-amd64.tar.gz -C /tmp/
sudo /tmp/cyclecloud-cli-installer/install.sh -y
```

---

## First-Time Setup

### Step 1 — Edit Environment Configuration

Open `C:\Works\bash-automation\setup_env.sh` and set your values:

```bash
# In WSL:
nano /mnt/c/Works/bash-automation/setup_env.sh

# Set these three variables:
export AZURE_SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export HPC_SCHEDULER="your-headnode.example.com"
export CYCLECLOUD_URL="https://your-cyclecloud-server.example.com"
```

### Step 2 — Authenticate with Azure

```bash
# In WSL Bash (or Windows PowerShell):
az login

# Set active subscription (if you have multiple)
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# Verify
az account show
```

### Step 3 — Connect CycleCloud CLI to your Server

```bash
# In WSL Bash:
cyclecloud initialize

# Follow prompts:
#   CycleCloud URL: https://your-cyclecloud-server.example.com
#   Username:       admin
#   Password:       (your CycleCloud admin password)
```

```powershell
# In Windows PowerShell:
cyclecloud initialize
```

### Step 4 — Load HPC Pack PowerShell Module

```powershell
# In PowerShell — module is already on PSModulePath:
Import-Module Microsoft.Hpc

# Verify (will hang if no head node reachable — that is expected):
Get-HpcJob -Scheduler your-headnode.example.com | Select-Object -First 5
```

### Step 5 — Activate azurehpc (WSL)

```bash
# Open a new WSL session — azurehpc is sourced automatically via ~/.bashrc
# Or manually source it:
source ~/azurehpc/install.sh

# Verify all azhpc commands are available:
azhpc-build   --help
azhpc-run     --help
azhpc-connect --help
azhpc-destroy --help
azhpc-status  --help
```

---

## Running Bash Jobs

### Option A — HPC Pack (`clusrun` / `job.exe`)

HPC Pack lets you run commands across cluster nodes. These work from both PowerShell and WSL Bash.

#### Run a command on all nodes simultaneously (`clusrun`)

```bash
# From WSL Bash:
/mnt/c/Works/hpc-pack/bin/clusrun.exe \
    /scheduler:your-headnode.example.com \
    /all \
    hostname

# Run a bash script on all Linux compute nodes:
/mnt/c/Works/hpc-pack/bin/clusrun.exe \
    /scheduler:your-headnode.example.com \
    /all \
    bash /shared/scripts/my_job.sh
```

```powershell
# From PowerShell:
clusrun.exe /scheduler:your-headnode.example.com /all hostname

# Run on specific nodes:
clusrun.exe /scheduler:your-headnode.example.com /nodes:"node1,node2,node3" bash /shared/scripts/run.sh

# Run on a node group:
clusrun.exe /scheduler:your-headnode.example.com /nodegroup:ComputeNodes "mpirun -np 8 ./my_app"
```

#### Submit a queued job (`job.exe`)

```bash
# Submit a new job:
/mnt/c/Works/hpc-pack/bin/job.exe new \
    /scheduler:your-headnode.example.com \
    /numcores:4-8 \
    /jobname:"MyBashJob" \
    /stdout:/shared/logs/job.out \
    /stderr:/shared/logs/job.err \
    /commandline:"bash /shared/scripts/my_batch_job.sh"

# List all jobs:
/mnt/c/Works/hpc-pack/bin/job.exe list /scheduler:your-headnode.example.com

# View a specific job:
/mnt/c/Works/hpc-pack/bin/job.exe view <JobId> /scheduler:your-headnode.example.com

# Cancel a job:
/mnt/c/Works/hpc-pack/bin/job.exe cancel <JobId> /scheduler:your-headnode.example.com
```

#### Submit via PowerShell HPC cmdlets

```powershell
Import-Module Microsoft.Hpc
$scheduler = "your-headnode.example.com"

# Create and submit a job
$job = New-HpcJob -Scheduler $scheduler -Name "MyBashJob" -NumCores 1,8
$task = Add-HpcTask -Job $job -CommandLine "bash /shared/scripts/run.sh" -WorkDir "/shared"
Submit-HpcJob -Job $job -Scheduler $scheduler

# Monitor
Get-HpcJob -Scheduler $scheduler -State Running | Select-Object Id, Name, State
```

---

### Option B — Azure CycleCloud CLI

Use `cyclecloud` to manage clusters and submit work via the scheduler running inside CycleCloud (Slurm, PBS, etc.).

#### Manage clusters

```bash
# List all clusters
cyclecloud show_cluster

# Start a cluster
cyclecloud start_cluster MyCluster

# Show node status
cyclecloud show_nodes MyCluster

# Scale up compute nodes
cyclecloud add_node MyCluster --count 4 --target-state Started

# SSH into the head node
cyclecloud connect MyCluster -u azureuser
```

#### Submit jobs once connected to the head node via SSH

```bash
# After: cyclecloud connect MyCluster
# You are now on the head node — submit via scheduler:

# Slurm:
sbatch my_job.sh

# PBS/OpenPBS:
qsub my_job.sh

# HPC Pack on CycleCloud:
job.exe new /commandline:"bash my_job.sh"
```

#### Example Slurm batch script (`my_job.sh`)

```bash
#!/bin/bash
#SBATCH --job-name=my_hpc_job
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=16
#SBATCH --time=02:00:00
#SBATCH --output=/shared/logs/%j.out
#SBATCH --error=/shared/logs/%j.err

# Load modules (if applicable)
module load mpi/openmpi

# Run your application
mpirun -np 64 ./my_parallel_app --input /shared/data/input.dat --output /shared/data/output.dat
```

---

### Option C — azurehpc Automation Framework

The `azurehpc` framework automates full HPC environment deployment with JSON config files.

#### Workflow

```
1. azhpc-init    →  Create a starter config.json
2. azhpc-build   →  Provision Azure infrastructure
3. azhpc-run     →  Run commands / install software on nodes
4. azhpc-connect →  SSH into any resource
5. azhpc-destroy →  Tear down all resources
```

#### Quickstart

```bash
# Open WSL and activate azurehpc
source ~/azurehpc/install.sh

# Create a starter config (interactive)
mkdir ~/my-hpc-env && cd ~/my-hpc-env
azhpc-init --config config.json

# OR copy and edit an example:
cp ~/azurehpc/examples/simple_hpc_pbs/config.json .
# Edit config.json — set your subscription, location, vm_size, etc.

# Build the environment (provisions all Azure resources)
azhpc-build --config config.json

# Check status
azhpc-status --config config.json

# Run a command on the head node
azhpc-run --config config.json "hostname; uname -a" headnode

# Run a bash script on all compute nodes
azhpc-run --config config.json "bash /scratch/my_setup.sh" compute

# Copy files to nodes
azhpc-scp --config config.json my_script.sh headnode:/shared/

# SSH into the head node
azhpc-connect --config config.json headnode

# Tear down when done
azhpc-destroy --config config.json
```

#### Minimal `config.json` example

```json
{
    "location": "eastus",
    "resource_group": "my-hpc-rg",
    "install_from": "headnode",
    "admin_user": "azureuser",
    "variables": {
        "vm_type": "Standard_HB120rs_v2",
        "hpc_image": "OpenLogic:CentOS-HPC:7_9-gen2:latest"
    },
    "resources": {
        "headnode": {
            "type": "vm",
            "vm_type": "Standard_D4s_v3",
            "image": "{{hpc_image}}",
            "public_ip": true
        },
        "compute": {
            "type": "vmss",
            "vm_type": "{{vm_type}}",
            "image": "{{hpc_image}}",
            "instances": 4
        }
    }
}
```

---

### Option D — Custom Automation Scripts

All scripts live in `C:\Works\bash-automation\` and are accessible from WSL at `/mnt/c/Works/bash-automation/`.

#### Run the environment setup script

```bash
# Always source this first in every new session:
source /mnt/c/Works/bash-automation/setup_env.sh
```

#### Deploy a CycleCloud cluster

```bash
# Usage: ./deploy_cyclecloud_cluster.sh <cluster_name> <template_file>
./deploy_cyclecloud_cluster.sh MySlurm ~/templates/slurm-cluster.ini
```

#### Submit an HPC batch job

```bash
# Usage: ./submit_hpc_job.sh --scheduler <headnode> --command "<cmd>" [--nodes <n>]
./submit_hpc_job.sh \
    --scheduler your-headnode.example.com \
    --command "bash /shared/scripts/run.sh" \
    --nodes 8
```

#### Run a cluster health check

```bash
# Check CycleCloud cluster AND HPC Pack scheduler:
./cluster_health_check.sh \
    --cyclecloud MyCluster \
    --hpc your-headnode.example.com

# CycleCloud only:
./cluster_health_check.sh --cyclecloud MyCluster

# HPC Pack only:
./cluster_health_check.sh --hpc your-headnode.example.com
```

---

## Bash Automation Scripts Reference

| Script | Description | Required Env Vars |
|--------|-------------|-------------------|
| `setup_env.sh` | Bootstrap — source this first. Loads all env vars and activates azurehpc | `AZURE_SUBSCRIPTION_ID`, `HPC_SCHEDULER`, `CYCLECLOUD_URL` |
| `deploy_cyclecloud_cluster.sh` | Import a cluster template and start the cluster | `CYCLECLOUD_URL` (via setup_env.sh) |
| `submit_hpc_job.sh` | Run a command across N cluster nodes via `clusrun.exe` | `HPC_SCHEDULER` (via setup_env.sh) |
| `cluster_health_check.sh` | Report node states and active jobs for CycleCloud and/or HPC Pack | `HPC_SCHEDULER`, `CYCLECLOUD_URL` |

---

## HPC Pack CLI Reference

All binaries at: `C:\Works\hpc-pack\bin\`  
From WSL prefix with: `/mnt/c/Works/hpc-pack/bin/`

| Command | Purpose | Example |
|---------|---------|---------|
| `job.exe new` | Create a new job | `job.exe new /scheduler:hn /commandline:"bash run.sh"` |
| `job.exe submit` | Submit an existing job | `job.exe submit <id> /scheduler:hn` |
| `job.exe list` | List jobs | `job.exe list /scheduler:hn /status:Running` |
| `job.exe view` | View job details | `job.exe view <id> /scheduler:hn` |
| `job.exe cancel` | Cancel a job | `job.exe cancel <id> /scheduler:hn` |
| `clusrun.exe` | Run command on nodes | `clusrun.exe /scheduler:hn /all hostname` |
| `node.exe list` | List all nodes | `node.exe list /scheduler:hn` |
| `cluscfg.exe` | Cluster configuration | `cluscfg.exe listcerts /scheduler:hn` |
| `task.exe` | Manage tasks within jobs | `task.exe view <jobid>.<taskid>` |
| `hpccred.exe` | Manage credentials | `hpccred.exe setcreds /scheduler:hn` |

---

## CycleCloud CLI Reference

Binary: `cyclecloud` (Windows: `cyclecloud.exe`)

| Command | Description | Example |
|---------|-------------|---------|
| `initialize` | Connect CLI to a CycleCloud server | `cyclecloud initialize` |
| `show_cluster` | List all clusters | `cyclecloud show_cluster` |
| `show_nodes <name>` | Show node details for a cluster | `cyclecloud show_nodes MyCluster` |
| `start_cluster <name>` | Start a cluster | `cyclecloud start_cluster MyCluster` |
| `terminate_cluster <name>` | Terminate a cluster | `cyclecloud terminate_cluster MyCluster` |
| `add_node <name>` | Add nodes to running cluster | `cyclecloud add_node MyCluster --count 4` |
| `connect <name>` | SSH into a cluster node | `cyclecloud connect MyCluster` |
| `import_cluster <name>` | Create cluster from template file | `cyclecloud import_cluster MyCluster --file c.ini` |
| `export_parameters <name>` | Export cluster parameters | `cyclecloud export_parameters MyCluster` |
| `create_cluster <name>` | Create from existing template | `cyclecloud create_cluster MyCluster --cluster-type Slurm` |

---

## Troubleshooting

### `Microsoft.Hpc` PowerShell module hangs on import
**Cause**: The module immediately tries to reach an HPC head node.  
**Fix**: This is expected when no head node is reachable. Always use with `/scheduler:` flags on individual commands instead.

### `cyclecloud` commands fail with "not initialized"
**Fix**: Run `cyclecloud initialize` first and provide your server URL, username, and password.

### `azhpc-build` fails with "exec: C:\Program: not found"
**Cause**: WSL was finding the Windows Azure CLI (`az.cmd`) instead of the native Linux one.  
**Fix**: The native Linux Azure CLI has been installed at `/usr/bin/az`. If this recurs, add this to `~/.bashrc`:
```bash
alias az=/usr/bin/az
```

### `clusrun.exe` returns "No nodes found"
**Cause**: All nodes are offline or the scheduler name is wrong.  
**Fix**: Check node status first: `node.exe list /scheduler:your-headnode`

### WSL cannot reach Azure resources
**Fix**: Ensure you have logged in with the native Linux `az`:
```bash
/usr/bin/az login
/usr/bin/az account set --subscription "your-subscription-id"
```