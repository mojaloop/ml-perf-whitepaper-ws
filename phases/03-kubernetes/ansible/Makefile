# Makefile for K8s deployment with Ansible

.PHONY: all install configure kubeconfig clean help check

# Default target
all: deploy

# Check prerequisites
check:
	@echo "Checking prerequisites..."
	@test -f ../../02-infrastructure/artifacts/inventory.yaml || (echo "ERROR: Inventory not found. Run Terraform first." && exit 1)
	@test -f ../../02-infrastructure/config.yaml || (echo "ERROR: Config file not found." && exit 1)
	@ansible --version > /dev/null 2>&1 || (echo "ERROR: Ansible not installed." && exit 1)
	@echo "✓ All prerequisites met"

# Deploy everything
deploy: check
	ansible-playbook playbooks/deploy-k8s.yml

# Install MicroK8s only
install: check
	ansible-playbook playbooks/01-install-microk8s.yml

# Configure Switch cluster only
switch-cluster: check
	ansible-playbook playbooks/02-configure-switch-cluster.yml

# Configure FSP clusters only
fsp-clusters: check
	ansible-playbook playbooks/03-configure-fsp-clusters.yml

# Generate kubeconfigs only
kubeconfig: check
	ansible-playbook playbooks/04-generate-kubeconfigs.yml

# Run specific playbook with tags
install-only: check
	ansible-playbook playbooks/deploy-k8s.yml --tags install

configure-only: check
	ansible-playbook playbooks/deploy-k8s.yml --tags configure

# Test connectivity
ping: check
	ansible all -m ping

# Check cluster status
status: check
	@echo "Checking Switch cluster status..."
	@ansible switch -m shell -a "microk8s kubectl get nodes" --become
	@echo "\nChecking FSP clusters status..."
	@ansible dfsps -m shell -a "microk8s kubectl get nodes" --become

# Clean up (be careful!)
uninstall:
	@echo "WARNING: This will remove MicroK8s from all nodes!"
	@read -p "Are you sure? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 1
	ansible switch:dfsps -m shell -a "snap remove microk8s" --become

# Help
help:
	@echo "Available targets:"
	@echo "  make deploy        - Full deployment (install + configure + kubeconfig)"
	@echo "  make install       - Install MicroK8s on all nodes"
	@echo "  make switch-cluster - Configure switch cluster only"
	@echo "  make fsp-clusters  - Configure FSP clusters only"
	@echo "  make kubeconfig    - Generate kubeconfig files"
	@echo "  make ping          - Test Ansible connectivity"
	@echo "  make status        - Check cluster status"
	@echo "  make uninstall     - Remove MicroK8s (DESTRUCTIVE)"
	@echo ""
	@echo "Configuration files:"
	@echo "  Config: ../../02-infrastructure/config.yaml"
	@echo "  Inventory: ../../02-infrastructure/artifacts/inventory.yaml"
	@echo ""
	@echo "Output:"
	@echo "  Kubeconfigs: ../../02-infrastructure/artifacts/kubeconfigs/"