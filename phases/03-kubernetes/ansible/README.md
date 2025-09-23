# Kubernetes Deployment with Ansible

## Overview
This Ansible setup deploys MicroK8s clusters:
- **Switch Cluster**: 3-node HA cluster for Mojaloop core services
- **FSP Clusters**: Individual single-node clusters per FSP

## Prerequisites
1. Infrastructure deployed via Terraform (Phase 02)
2. Inventory file at `../../02-infrastructure/artifacts/inventory.yaml`
3. SSH config configured from artifacts
4. Ansible installed locally

## Quick Start

### Deploy Everything
```bash
cd phases/03-kubernetes/ansible
make deploy
```

### Step-by-Step Deployment
```bash
# 1. Install MicroK8s on all nodes
make install

# 2. Configure switch cluster
make switch-cluster

# 3. Configure FSP clusters
make fsp-clusters

# 4. Generate kubeconfig files
make kubeconfig
```

## Using the Clusters

### Access Switch Cluster
```bash
export KUBECONFIG=../../02-infrastructure/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml
kubectl get nodes
```

### Access FSP Cluster
```bash
export KUBECONFIG=../../02-infrastructure/artifacts/kubeconfigs/kubeconfig-fsp101.yaml
kubectl get nodes
```

## Configuration

All configuration is read from:
- `../../02-infrastructure/config.yaml` - Main configuration
- `group_vars/all.yml` - Ansible variables

### K8s Configuration in config.yaml
```yaml
k8s:
  microk8s_version: "1.30/stable"
  switch_cluster_name: "mojaloop-switch"
  addons:
    switch_cluster: [dns, storage, ingress, metrics-server]
    fsp_clusters: [dns, storage, ingress, metrics-server]
```

## Playbooks

| Playbook | Description |
|----------|-------------|
| `01-install-microk8s.yml` | Installs MicroK8s on all nodes |
| `02-configure-switch-cluster.yml` | Forms the 3-node switch cluster |
| `03-configure-fsp-clusters.yml` | Configures individual FSP clusters |
| `04-generate-kubeconfigs.yml` | Creates kubeconfig files with ProxyCommand |
| `deploy-k8s.yml` | Main playbook that runs all steps |

## Generated Artifacts

After deployment, find these in `../../02-infrastructure/artifacts/`:

```
artifacts/
├── kubeconfigs/
│   ├── kubeconfig-mojaloop-switch.yaml
│   ├── kubeconfig-fsp101.yaml
│   ├── kubeconfig-fsp102.yaml
│   └── kubeconfig-fsp103.yaml
└── k8s-access.txt  # Access instructions
```

## Kubeconfig with ProxyCommand

All generated kubeconfigs use SSH ProxyCommand for transparent access through the bastion:

```yaml
clusters:
- cluster:
    server: https://10.110.2.x:16443
    proxy-command: ssh -W %h:%p -q ubuntu@<bastion-ip>
```

This means you can use `kubectl` from your local machine without manual port forwarding!

## Troubleshooting

### Check Connectivity
```bash
make ping
```

### Check Cluster Status
```bash
make status
```

### View Ansible Logs
```bash
ansible-playbook playbooks/deploy-k8s.yml -vvv
```

### Manual MicroK8s Commands
```bash
# On switch primary node
ansible sw1-n1 -m shell -a "microk8s status" --become
ansible sw1-n1 -m shell -a "microk8s kubectl get nodes" --become

# On FSP node
ansible fsp101 -m shell -a "microk8s kubectl get pods -A" --become
```

## Clean Up

To completely remove MicroK8s from all nodes:
```bash
make uninstall  # WARNING: Destructive!
```