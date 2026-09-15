# Microsoft HPC Tooling — Official Documentation Reference

This document consolidates all official Microsoft public documentation, GitHub repositories, and reference links for the three components in this repository:
**HPC Pack 2019**, **Azure CycleCloud**, and **Azure HPC Bash Automation**.

All links are verified against `learn.microsoft.com`, `techcommunity.microsoft.com`, and `github.com/Azure`.

---

## Table of Contents

- [Microsoft HPC Pack 2019](#-microsoft-hpc-pack-2019)
- [Azure CycleCloud](#-azure-cyclecloud)
- [Azure HPC Bash Automation (azurehpc)](#-azure-hpc-bash-automation-azurehpc)
- [Azure HPC Infrastructure](#-azure-hpc-infrastructure)
- [Related Azure Services](#-related-azure-services)
- [Downloads](#-downloads)
- [GitHub Repositories](#-github-repositories)
- [Community & Support](#-community--support)

---

## 📦 Microsoft HPC Pack 2019

> ⚠️ **Retirement Notice:** Microsoft HPC Pack 2019 is scheduled for retirement on **August 30, 2027**.
> See the [retirement announcement](https://techcommunity.microsoft.com/blog/AzureHighPerformanceComputingBlog/retirement-of-microsoft-hpc-pack/4550183) for migration guidance.

### Overview & Getting Started

| Topic | Link |
|-------|------|
| HPC Pack Documentation Overview | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/overview?view=hpc19-ps) |
| What's New in HPC Pack 2019 Update 3 | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/what-s-new-in-hpc-pack-2019-update-3?view=hpc19-ps) |
| Release Notes — HPC Pack 2019 Update 3 | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/release-notes-for-hpc-pack-2019-update-3?view=hpc19-ps) |
| Retirement Announcement | [techcommunity.microsoft.com](https://techcommunity.microsoft.com/blog/AzureHighPerformanceComputingBlog/retirement-of-microsoft-hpc-pack/4550183) |

### PowerShell Module (`Microsoft.Hpc`)

The `Microsoft.Hpc` PowerShell module (v6.0.0.0) is included in this repo at `hpc-pack/powershell/Microsoft.Hpc/`.

| Topic | Link |
|-------|------|
| HPC Pack PowerShell Reference (hpc19-ps) | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/overview?view=hpc19-ps) |
| `Get-HpcJob` Cmdlet | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/get-hpcjob?view=hpc19-ps) |
| `Submit-HpcJob` Cmdlet | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/submit-hpcjob?view=hpc19-ps) |
| `Add-HpcNode` Cmdlet | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/add-hpcnode?view=hpc19-ps) |
| `Get-HpcNode` Cmdlet | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/get-hpcnode?view=hpc19-ps) |

### Job Submission CLI (`job.exe`, `clusrun.exe`)

| Topic | Link |
|-------|------|
| HPC Command-Line Reference | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/overview?view=hpc19-ps) |
| Job Schema Reference (job-v4.xsd) | Included: `hpc-pack/bin/job-v4.xsd` |
| Task Schema Reference (task-v4.xsd) | Included: `hpc-pack/bin/task-v4.xsd` |
| Node Configuration Schema | Included: `hpc-pack/bin/NodeConfigurationFile.xsd` |

### Azure Auto-Scale for HPC Pack

| Topic | Link |
|-------|------|
| AzureAutoGrowShrink.ps1 Reference | Included: `hpc-pack/bin/AzureAutoGrowShrink.ps1` |
| HPC Pack Azure Integration Guide | [learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/high-performance-computing/overview?view=hpc19-ps) |

---

## ☁️ Azure CycleCloud

CycleCloud CLI **8.9.4-3895** is installed (Windows + WSL). Installers and Python SDK are in `cyclecloud-dist/`.

### Overview & Architecture

| Topic | Link |
|-------|------|
| Azure CycleCloud Overview | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |
| CycleCloud Architecture | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |
| Azure HPC Architecture Guide | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/architecture/topics/high-performance-computing) |

### Installation

| Topic | Link |
|-------|------|
| Install CycleCloud CLI | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/install-cyclecloud-cli) |
| Manual CycleCloud Server Install | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/install-manual) |
| CycleCloud on Azure Marketplace | [portal.azure.com](https://portal.azure.com/#create/Microsoft.CycleCloud) |

### Cluster Management

| Topic | Link |
|-------|------|
| Create a Cluster | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/create-cluster) |
| Cluster Templates | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/projects) |
| Mount a Fileserver (NFS/BeeGFS) | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/mount-fileserver) |
| Node Customization with cloud-init | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/cloud-init) |
| CycleCloud Projects (cluster-init) | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/projects) |

### CLI & API Reference

| Topic | Link |
|-------|------|
| CycleCloud CLI Reference | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/cli) |
| CycleCloud REST API Reference | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/api) |
| CycleCloud Python API | Included: `cyclecloud-dist/cyclecloud_api-8.9.4-py2.py3-none-any.whl` |

### Supported Schedulers

| Scheduler | CycleCloud Docs |
|-----------|----------------|
| **Slurm** | [learn.microsoft.com — Slurm on CycleCloud](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |
| **PBS Professional / OpenPBS** | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |
| **Microsoft HPC Pack** | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |
| **LSF (IBM Spectrum)** | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |
| **Grid Engine** | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |

---

## 🔧 Azure HPC Bash Automation (`azurehpc`)

The `azurehpc` framework is cloned in WSL at `~/azurehpc`. This repo's `bash-automation/` scripts are built on top of it.

### Official Resources

| Topic | Link |
|-------|------|
| azurehpc GitHub Repository | [github.com/Azure/azurehpc](https://github.com/Azure/azurehpc) |
| azurehpc README & Quickstart | [github.com/Azure/azurehpc#readme](https://github.com/Azure/azurehpc#readme) |
| Example Configurations | [github.com/Azure/azurehpc/tree/master/examples](https://github.com/Azure/azurehpc/tree/master/examples) |
| azurehpc Application Catalogue | [github.com/Azure/azurehpc/tree/master/apps](https://github.com/Azure/azurehpc/tree/master/apps) |
| azhpc-diagnostics Tool | [github.com/Azure/azhpc-diagnostics](https://github.com/Azure/azhpc-diagnostics) |

### azhpc Command Reference

| Command | Description |
|---------|-------------|
| `azhpc-init` | Initialize a new config.json |
| `azhpc-build` | Provision Azure resources from config |
| `azhpc-run` | Execute commands on cluster nodes |
| `azhpc-connect` | SSH into a named resource |
| `azhpc-destroy` | Delete all provisioned resources |
| `azhpc-status` | Show status of deployed resources |
| `azhpc-scp` | Copy files to/from nodes |
| `azhpc-get` | Retrieve files from nodes |
| `azhpc-preprocess` | Pre-process config file variables |

---

## 🖥️ Azure HPC Infrastructure

### HPC VM Series

| VM Series | Use Case | Docs |
|-----------|----------|------|
| HBv4-series | Memory-bandwidth intensive (CFD, weather) | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv4-series) |
| HBv3-series | AMD EPYC, high memory BW | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv3-series) |
| HC-series | Compute-intensive (FEA, molecular dynamics) | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/virtual-machines/hc-series) |
| NDv4/NDv5-series | AI + HPC GPU workloads | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/virtual-machines/ndv4-series) |

### Networking & Storage

| Topic | Link |
|-------|------|
| InfiniBand on Azure HPC VMs | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/enable-infiniband) |
| Azure HPC Cache | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/hpc-cache/hpc-cache-overview) |
| Azure NetApp Files for HPC | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-introduction) |
| Lustre / Managed Lustre | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/azure-managed-lustre/amlfs-overview) |

### Architecture Guidance

| Topic | Link |
|-------|------|
| HPC on Azure — Architecture Center | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/architecture/topics/high-performance-computing) |
| Run HPC applications on Azure | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/architecture/topics/high-performance-computing) |
| Azure HPC Landing Zone Accelerator | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/azure-hpc/) |

---

## 🔗 Related Azure Services

| Service | Description | Docs |
|---------|-------------|------|
| **Azure Batch** | Managed job scheduling as-a-service | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/batch/batch-technical-overview) |
| **Azure Batch CLI** | Submit and manage Batch jobs | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/batch/quick-create-cli) |
| **Azure CycleCloud Workspaces for Slurm** | Simplified Slurm on Azure | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/cyclecloud/overview) |
| **Azure Container Instances** | Run HPC containers | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-overview) |
| **Azure Virtual Machine Scale Sets** | Elastic compute for HPC | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/overview) |
| **Azure Spot VMs** | Cost-optimized compute for HPC | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms) |

---

## 📥 Downloads

| Package | Version | Download |
|---------|---------|----------|
| HPC Pack 2019 Client Utilities (x64 MSI) | 6.0.7205.0 | [microsoft.com](https://www.microsoft.com/en-us/download/details.aspx?id=101361) |
| HPC Pack 2019 Full Package (latest fixes) | 6.3.8363 | [microsoft.com](https://www.microsoft.com/en-us/download/details.aspx?id=108832) |
| CycleCloud CLI (Windows ZIP) | 8.9.4 | Included: `cyclecloud-dist/cyclecloud-cli-8.9.4.zip` |
| CycleCloud CLI (Linux tar.gz) | 8.9.4 | Download from your CycleCloud server: `https://<server>/static/tools/cyclecloud-cli.zip` |
| CycleCloud Python API (wheel) | 8.9.4 | Included: `cyclecloud-dist/cyclecloud_api-8.9.4-py2.py3-none-any.whl` |
| CycleCloud Server (Debian/Ubuntu) | 8.9.4 | [packages.microsoft.com](https://packages.microsoft.com/repos/cyclecloud/) |
| CycleCloud Server (RHEL/CentOS/Alma) | 8.9.4 | [packages.microsoft.com](https://packages.microsoft.com/yumrepos/cyclecloud/) |

---

## 🐙 GitHub Repositories

| Repository | Description |
|-----------|-------------|
| [Azure/hpcpack](https://github.com/Azure/hpcpack) | HPC Pack announcements, issue tracker, and release notes |
| [Azure/hpcpack-template](https://github.com/Azure/hpcpack-template) | ARM templates for deploying HPC Pack on Azure |
| [Azure/cyclecloud-slurm](https://github.com/Azure/cyclecloud-slurm) | Slurm cluster project for CycleCloud |
| [Azure/azurehpc](https://github.com/Azure/azurehpc) | Azure HPC automation framework (archived Aug 2026) |
| [Azure/azhpc-diagnostics](https://github.com/Azure/azhpc-diagnostics) | Diagnostic scripts for Azure HPC VMs |
| [Azure/cyclecloud-pbspro](https://github.com/Azure/cyclecloud-pbspro) | OpenPBS cluster project for CycleCloud |
| [Azure/cyclecloud-lsf](https://github.com/Azure/cyclecloud-lsf) | LSF cluster project for CycleCloud |
| **This repository** | [github.com/sschinna/microsoft-hpc-tooling](https://github.com/sschinna/microsoft-hpc-tooling) |

---

## 💬 Community & Support

| Resource | Link |
|----------|------|
| Microsoft Q&A — Azure CycleCloud | [learn.microsoft.com/answers](https://learn.microsoft.com/en-us/answers/tags/130/azure-cyclecloud) |
| Microsoft Q&A — HPC on Azure | [learn.microsoft.com/answers](https://learn.microsoft.com/en-us/answers/tags/178/azure-high-performance-computing) |
| Azure HPC Tech Community Blog | [techcommunity.microsoft.com](https://techcommunity.microsoft.com/category/AzureHighPerformanceComputingBlog) |
| Azure Updates — HPC | [azure.microsoft.com/updates](https://azure.microsoft.com/en-us/updates/?category=compute&query=hpc) |
| Stack Overflow — azure-cyclecloud | [stackoverflow.com](https://stackoverflow.com/questions/tagged/azure-cyclecloud) |
| HPC Pack Retirement Info | [techcommunity.microsoft.com](https://techcommunity.microsoft.com/blog/AzureHighPerformanceComputingBlog/retirement-of-microsoft-hpc-pack/4550183) |

---

> **Last verified:** September 2026  
> **Maintained by:** [sschinna/microsoft-hpc-tooling](https://github.com/sschinna/microsoft-hpc-tooling)